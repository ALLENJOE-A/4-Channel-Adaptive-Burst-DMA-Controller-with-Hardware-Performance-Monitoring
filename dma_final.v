// =============================================================================
// Project: Final 4-Channel Adaptive Burst DMA Controller
// Target : ASIC-Ready Functional RTL
// Language: Pure Verilog-2001 Only
// File   : dma_final.v
//
// Features:
//   - 4 Independent DMA Channels (CH0, CH1, CH2, CH3)
//   - Fair 4-Channel Round-Robin Arbiter with Burst Lock
//   - Fixed Burst Modes: 1, 4, 8, 16 words
//   - Burst Utilization-Based Adaptive Burst Selection (Novelty)
//       * Initial burst size: 4 words
//       * Adaptive levels: 1 <-> 4 <-> 8 <-> 16 words
//       * Saturated bounds: [1, 16] words
//       * Dynamic threshold adaptation at burst boundaries only
//       * Overrun protection: burst size strictly capped to remaining transfer length
//   - Hardware Performance Monitoring Unit (PMU):
//       * Global: Total Cycles, Busy Cycles, Total Words, Total Bursts, Total Grants
//       * Per-Channel: Words Transferred, Bursts Executed, Current Burst Size
//       * Deterministic PMU Clear Register (0x94)
//       * Adaptive Enable / Mode Register (0x98) for isolated baseline benchmarking
//   - Deterministic Handshake Memory Interface (mem_addr, mem_read, mem_write, mem_wdata, mem_rdata, mem_ready)
//   - Waveform-friendly internal signals
//   - Fully Synthesizable: zero delays, zero TB constructs, standard asynchronous reset
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// Module: dma_channel_final
// Description: Individual DMA Channel with FSM, Datapath, and Adaptive Controller
// =============================================================================
module dma_channel_final #(
  parameter CHANNEL_ID = 0
)(
  input             clk,
  input             rst_n,

  // Register Configuration Interface
  input      [31:0] src_addr_reg,
  input      [31:0] dst_addr_reg,
  input      [31:0] length_reg,
  input      [1:0]  burst_size_reg,
  input             burst_size_update,
  input             adaptive_en,
  input             start_bit,
  output reg        busy,
  output reg        done,

  // Arbiter Handshake
  output reg        req,
  input             grant,
  output reg        burst_active,

  // Memory Bus Interface
  output reg [31:0] mem_addr,
  output reg [31:0] mem_wdata,
  input      [31:0] mem_rdata,
  output reg        mem_write_en,
  output reg        mem_read_en,
  output reg        mem_valid,
  input             mem_ready,

  // Observability & Status
  output reg        burst_done,
  output     [1:0]  current_burst_level,
  output     [4:0]  burst_size_words,
  output     [4:0]  burst_count_out,
  output     [31:0] remaining_length_out,
  output     [31:0] source_addr_out,
  output     [31:0] destination_addr_out
);

  // FSM State Encoding
  localparam [2:0] IDLE       = 3'd0;
  localparam [2:0] BURST_REQ  = 3'd1;
  localparam [2:0] READ_WAIT  = 3'd2;
  localparam [2:0] WRITE_WAIT = 3'd3;
  localparam [2:0] DONE_STATE = 3'd4;

  reg [2:0] state, next_state;
  reg burst_size_update_pending;

  // Track pending burst configuration writes
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      burst_size_update_pending <= 1'b1;
    end else if (burst_size_update) begin
      burst_size_update_pending <= 1'b1;
    end else if (state == IDLE && start_bit) begin
      burst_size_update_pending <= 1'b0;
    end
  end

  // Adaptive Burst Selection Logic
  // Score starts at 7 (neutral). Full bursts increment score; partial bursts decrement.
  // Threshold >= 12 triggers upgrade; <= 3 triggers downgrade.
  reg [3:0] efficiency_score;
  reg [1:0] burst_level;

  assign current_burst_level = burst_level;

  // Burst length decode: 2'b00->1, 2'b01->4, 2'b10->8, 2'b11->16
  reg [4:0] burst_len;
  always @* begin
    case (burst_level)
      2'b00:   burst_len = 5'd1;
      2'b01:   burst_len = 5'd4;
      2'b10:   burst_len = 5'd8;
      2'b11:   burst_len = 5'd16;
      default: burst_len = 5'd4;
    endcase
  end

  assign burst_size_words = burst_len;

  // Datapath registers
  reg [31:0] current_src_addr;
  reg [31:0] current_dst_addr;
  reg [31:0] rem_len;
  reg [31:0] read_data_buf;
  reg [4:0]  burst_cnt;

  assign source_addr_out      = current_src_addr;
  assign destination_addr_out = current_dst_addr;
  assign remaining_length_out = rem_len;
  assign burst_count_out      = burst_cnt;

  // State Register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  // Datapath & Adaptive Logic Register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_src_addr <= 32'h0;
      current_dst_addr <= 32'h0;
      rem_len          <= 32'h0;
      read_data_buf    <= 32'h0;
      burst_cnt        <= 5'h0;
      efficiency_score <= 4'd7;
      burst_level      <= 2'd1; // Initial default: 4 words
    end else begin
      case (state)
        IDLE: begin
          if (start_bit) begin
            current_src_addr <= src_addr_reg;
            current_dst_addr <= dst_addr_reg;
            rem_len          <= length_reg;
            burst_cnt        <= 5'h0;
            if (burst_size_update_pending) begin
              burst_level      <= burst_size_reg;
              efficiency_score <= 4'd7;
            end
          end
        end

        BURST_REQ: begin
          if (grant) begin
            burst_cnt <= 5'h0;
          end
        end

        READ_WAIT: begin
          if (mem_ready) begin
            read_data_buf <= mem_rdata;
          end
        end

        WRITE_WAIT: begin
          if (mem_ready) begin
            current_src_addr <= current_src_addr + 32'd4;
            current_dst_addr <= current_dst_addr + 32'd4;
            rem_len          <= rem_len - 32'd1;
            burst_cnt        <= burst_cnt + 5'd1;

            if (adaptive_en) begin
              // Adaptation rule: Update state ONLY at a valid burst boundary
              if (rem_len == 32'd1) begin
                // End of entire transfer
                if (burst_cnt != (burst_len - 5'd1)) begin
                  // Partial burst (transferred fewer words than current burst_len)
                  if (efficiency_score <= 4'd3) begin
                    if (burst_level > 2'd0) burst_level <= burst_level - 2'd1; // Saturated lower bound (1 word)
                    efficiency_score <= 4'd7;
                  end else begin
                    efficiency_score <= efficiency_score - 4'd2;
                  end
                end else begin
                  // Full burst at end of transfer
                  if (efficiency_score >= 4'd12) begin
                    if (burst_level < 2'd3) burst_level <= burst_level + 2'd1; // Saturated upper bound (16 words)
                    efficiency_score <= 4'd7;
                  end else begin
                    efficiency_score <= efficiency_score + 4'd1;
                  end
                end
              end else if (burst_cnt == (burst_len - 5'd1)) begin
                // End of full intermediate burst
                if (efficiency_score >= 4'd12) begin
                  if (burst_level < 2'd3) burst_level <= burst_level + 2'd1; // Upgrade burst size
                  efficiency_score <= 4'd7;
                end else begin
                  efficiency_score <= efficiency_score + 4'd1;
                end
              end
            end else begin
              // Fixed burst baseline mode: hold strictly to configured burst_size_reg
              burst_level      <= burst_size_reg;
              efficiency_score <= 4'd7;
            end
          end
        end

        default: begin
          // Hold datapath registers
        end
      endcase
    end
  end

  // Next State Logic
  always @* begin
    next_state = state;

    case (state)
      IDLE: begin
        if (start_bit && (length_reg > 32'd0)) begin
          next_state = BURST_REQ;
        end
      end

      BURST_REQ: begin
        if (grant) begin
          next_state = READ_WAIT;
        end
      end

      READ_WAIT: begin
        if (mem_ready) begin
          next_state = WRITE_WAIT;
        end
      end

      WRITE_WAIT: begin
        if (mem_ready) begin
          if (rem_len == 32'd1) begin
            next_state = DONE_STATE;
          end else if (burst_cnt == (burst_len - 5'd1)) begin
            next_state = BURST_REQ;
          end else begin
            next_state = READ_WAIT;
          end
        end
      end

      DONE_STATE: begin
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  // Output Generation
  always @* begin
    req          = 1'b0;
    mem_addr     = 32'h0;
    mem_wdata    = 32'h0;
    mem_write_en = 1'b0;
    mem_read_en  = 1'b0;
    mem_valid    = 1'b0;
    busy         = 1'b0;
    done         = 1'b0;
    burst_active = 1'b0;
    burst_done   = 1'b0;

    case (state)
      BURST_REQ: begin
        req          = 1'b1;
        busy         = 1'b1;
        burst_active = 1'b0;
      end

      READ_WAIT: begin
        mem_addr     = current_src_addr;
        mem_read_en  = 1'b1;
        mem_valid    = 1'b1;
        busy         = 1'b1;
        burst_active = 1'b1;
      end

      WRITE_WAIT: begin
        mem_addr     = current_dst_addr;
        mem_wdata    = read_data_buf;
        mem_write_en = 1'b1;
        mem_valid    = 1'b1;
        busy         = 1'b1;
        burst_active = 1'b1;
        if (mem_ready) begin
          if (rem_len == 32'd1 || burst_cnt == (burst_len - 5'd1)) begin
            burst_done = 1'b1;
          end
        end
      end

      DONE_STATE: begin
        done = 1'b1;
      end

      default: begin
        busy = (state != IDLE);
      end
    endcase
  end

endmodule


// =============================================================================
// Module: dma_arbiter_final
// Description: Fair 4-Channel Round-Robin Arbiter with Active Burst Bus Locking
// =============================================================================
module dma_arbiter_final(
  input            clk,
  input            rst_n,
  input      [3:0] req,
  input            bus_busy,
  output reg [3:0] grant
);

  reg [1:0] last_grant;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_grant <= 2'd3;
      grant      <= 4'b0000;
    end else begin
      grant <= 4'b0000;

      // Only evaluate arbitration when bus is not locked by an active burst
      if (!bus_busy && (grant == 4'b0000)) begin
        case (last_grant)
          2'd0: begin
            if      (req[1]) begin grant[1] <= 1'b1; last_grant <= 2'd1; end
            else if (req[2]) begin grant[2] <= 1'b1; last_grant <= 2'd2; end
            else if (req[3]) begin grant[3] <= 1'b1; last_grant <= 2'd3; end
            else if (req[0]) begin grant[0] <= 1'b1; last_grant <= 2'd0; end
          end
          2'd1: begin
            if      (req[2]) begin grant[2] <= 1'b1; last_grant <= 2'd2; end
            else if (req[3]) begin grant[3] <= 1'b1; last_grant <= 2'd3; end
            else if (req[0]) begin grant[0] <= 1'b1; last_grant <= 2'd0; end
            else if (req[1]) begin grant[1] <= 1'b1; last_grant <= 2'd1; end
          end
          2'd2: begin
            if      (req[3]) begin grant[3] <= 1'b1; last_grant <= 2'd3; end
            else if (req[0]) begin grant[0] <= 1'b1; last_grant <= 2'd0; end
            else if (req[1]) begin grant[1] <= 1'b1; last_grant <= 2'd1; end
            else if (req[2]) begin grant[2] <= 1'b1; last_grant <= 2'd2; end
          end
          2'd3: begin
            if      (req[0]) begin grant[0] <= 1'b1; last_grant <= 2'd0; end
            else if (req[1]) begin grant[1] <= 1'b1; last_grant <= 2'd1; end
            else if (req[2]) begin grant[2] <= 1'b1; last_grant <= 2'd2; end
            else if (req[3]) begin grant[3] <= 1'b1; last_grant <= 2'd3; end
          end
          default: begin
            grant      <= 4'b0000;
            last_grant <= 2'd0;
          end
        endcase
      end
    end
  end

endmodule


// =============================================================================
// Top Module: dma_final
// Description: Complete Self-Contained Synthesizable 4-Channel DMA Controller
// =============================================================================
module dma_final(
  input             clk,
  input             rst_n,

  // Host Configuration Register Interface
  input      [7:0]  cfg_addr,
  input      [31:0] cfg_wdata,
  output reg [31:0] cfg_rdata,
  input             cfg_write_en,
  input             cfg_read_en,
  output reg        cfg_ready,

  // Memory Interface (Deterministic Handshake)
  output reg [31:0] mem_addr,
  output reg [31:0] mem_wdata,
  input      [31:0] mem_rdata,
  output reg        mem_write_en,
  output reg        mem_read_en,
  output reg        mem_valid,
  input             mem_ready,

  // Observability
  output reg        burst_done,
  output     [1:0]  current_burst_level
);

  // ---------------------------------------------------------------------------
  // Hardware Performance Monitoring Unit (PMU) Counters
  // ---------------------------------------------------------------------------
  reg [31:0] total_cycles;
  reg [31:0] busy_cycles;
  reg [31:0] total_words;
  reg [31:0] total_bursts;
  reg [31:0] total_grants;

  reg [31:0] ch0_words, ch0_bursts;
  reg [31:0] ch1_words, ch1_bursts;
  reg [31:0] ch2_words, ch2_bursts;
  reg [31:0] ch3_words, ch3_bursts;

  // Global Mode / Configuration
  reg        adaptive_en; // 1 = Adaptive Burst Enabled (default), 0 = Fixed Burst Baseline

  // ---------------------------------------------------------------------------
  // Channel Configuration Registers
  // ---------------------------------------------------------------------------
  reg [31:0] ch0_src_addr, ch0_dst_addr, ch0_length;
  reg [1:0]  ch0_burst_size;
  reg        ch0_start, ch0_burst_size_update;
  wire       ch0_busy, ch0_done, ch0_burst_active, ch0_burst_done;
  wire [1:0] ch0_current_burst;
  wire [4:0] ch0_burst_words, ch0_burst_cnt;
  wire [31:0] ch0_rem_len, ch0_src_out, ch0_dst_out;

  reg [31:0] ch1_src_addr, ch1_dst_addr, ch1_length;
  reg [1:0]  ch1_burst_size;
  reg        ch1_start, ch1_burst_size_update;
  wire       ch1_busy, ch1_done, ch1_burst_active, ch1_burst_done;
  wire [1:0] ch1_current_burst;
  wire [4:0] ch1_burst_words, ch1_burst_cnt;
  wire [31:0] ch1_rem_len, ch1_src_out, ch1_dst_out;

  reg [31:0] ch2_src_addr, ch2_dst_addr, ch2_length;
  reg [1:0]  ch2_burst_size;
  reg        ch2_start, ch2_burst_size_update;
  wire       ch2_busy, ch2_done, ch2_burst_active, ch2_burst_done;
  wire [1:0] ch2_current_burst;
  wire [4:0] ch2_burst_words, ch2_burst_cnt;
  wire [31:0] ch2_rem_len, ch2_src_out, ch2_dst_out;

  reg [31:0] ch3_src_addr, ch3_dst_addr, ch3_length;
  reg [1:0]  ch3_burst_size;
  reg        ch3_start, ch3_burst_size_update;
  wire       ch3_busy, ch3_done, ch3_burst_active, ch3_burst_done;
  wire [1:0] ch3_current_burst;
  wire [4:0] ch3_burst_words, ch3_burst_cnt;
  wire [31:0] ch3_rem_len, ch3_src_out, ch3_dst_out;

  // Channel Bus Handshake Signals
  wire        ch0_req, ch0_grant;
  wire [31:0] ch0_mem_addr, ch0_mem_wdata;
  reg  [31:0] ch0_mem_rdata;
  wire        ch0_mem_write_en, ch0_mem_read_en, ch0_mem_valid;
  reg         ch0_mem_ready;

  wire        ch1_req, ch1_grant;
  wire [31:0] ch1_mem_addr, ch1_mem_wdata;
  reg  [31:0] ch1_mem_rdata;
  wire        ch1_mem_write_en, ch1_mem_read_en, ch1_mem_valid;
  reg         ch1_mem_ready;

  wire        ch2_req, ch2_grant;
  wire [31:0] ch2_mem_addr, ch2_mem_wdata;
  reg  [31:0] ch2_mem_rdata;
  wire        ch2_mem_write_en, ch2_mem_read_en, ch2_mem_valid;
  reg         ch2_mem_ready;

  wire        ch3_req, ch3_grant;
  wire [31:0] ch3_mem_addr, ch3_mem_wdata;
  reg  [31:0] ch3_mem_rdata;
  wire        ch3_mem_write_en, ch3_mem_read_en, ch3_mem_valid;
  reg         ch3_mem_ready;

  // ---------------------------------------------------------------------------
  // Register Read/Write Access Logic
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ch0_src_addr          <= 32'h0;
      ch0_dst_addr          <= 32'h0;
      ch0_length            <= 32'h0;
      ch0_burst_size        <= 2'b01; // Default 4 words
      ch0_start             <= 1'b0;
      ch0_burst_size_update <= 1'b0;

      ch1_src_addr          <= 32'h0;
      ch1_dst_addr          <= 32'h0;
      ch1_length            <= 32'h0;
      ch1_burst_size        <= 2'b01;
      ch1_start             <= 1'b0;
      ch1_burst_size_update <= 1'b0;

      ch2_src_addr          <= 32'h0;
      ch2_dst_addr          <= 32'h0;
      ch2_length            <= 32'h0;
      ch2_burst_size        <= 2'b01;
      ch2_start             <= 1'b0;
      ch2_burst_size_update <= 1'b0;

      ch3_src_addr          <= 32'h0;
      ch3_dst_addr          <= 32'h0;
      ch3_length            <= 32'h0;
      ch3_burst_size        <= 2'b01;
      ch3_start             <= 1'b0;
      ch3_burst_size_update <= 1'b0;

      adaptive_en           <= 1'b1; // Default: Adaptive Mode Enabled
      cfg_rdata             <= 32'h0;
      cfg_ready             <= 1'b0;
    end else begin
      ch0_start             <= 1'b0;
      ch1_start             <= 1'b0;
      ch2_start             <= 1'b0;
      ch3_start             <= 1'b0;
      ch0_burst_size_update <= 1'b0;
      ch1_burst_size_update <= 1'b0;
      ch2_burst_size_update <= 1'b0;
      ch3_burst_size_update <= 1'b0;
      cfg_ready             <= 1'b0;

      // Register Writes
      if (cfg_write_en) begin
        case (cfg_addr)
          8'h00: ch0_src_addr   <= cfg_wdata;
          8'h04: ch0_dst_addr   <= cfg_wdata;
          8'h08: ch0_length     <= cfg_wdata;
          8'h0C: ch0_start      <= cfg_wdata[0];

          8'h10: ch1_src_addr   <= cfg_wdata;
          8'h14: ch1_dst_addr   <= cfg_wdata;
          8'h18: ch1_length     <= cfg_wdata;
          8'h1C: ch1_start      <= cfg_wdata[0];

          8'h20: ch2_src_addr   <= cfg_wdata;
          8'h24: ch2_dst_addr   <= cfg_wdata;
          8'h28: ch2_length     <= cfg_wdata;
          8'h2C: ch2_start      <= cfg_wdata[0];

          8'h30: ch3_src_addr   <= cfg_wdata;
          8'h34: ch3_dst_addr   <= cfg_wdata;
          8'h38: ch3_length     <= cfg_wdata;
          8'h3C: ch3_start      <= cfg_wdata[0];

          8'h40: begin ch0_burst_size <= cfg_wdata[1:0]; ch0_burst_size_update <= 1'b1; end
          8'h44: begin ch1_burst_size <= cfg_wdata[1:0]; ch1_burst_size_update <= 1'b1; end
          8'h48: begin ch2_burst_size <= cfg_wdata[1:0]; ch2_burst_size_update <= 1'b1; end
          8'h4C: begin ch3_burst_size <= cfg_wdata[1:0]; ch3_burst_size_update <= 1'b1; end

          8'h98: adaptive_en    <= cfg_wdata[0]; // Mode Control: 1=Adaptive, 0=Fixed Baseline

          default: begin
            // Other addresses ignore write or handle PMU clear separately
          end
        endcase
        cfg_ready <= 1'b1;
      end

      // Register Reads
      if (cfg_read_en) begin
        case (cfg_addr)
          8'h00: cfg_rdata <= ch0_src_addr;
          8'h04: cfg_rdata <= ch0_dst_addr;
          8'h08: cfg_rdata <= ch0_length;
          8'h0C: cfg_rdata <= {29'h0, ch0_done, ch0_busy, 1'b0};

          8'h10: cfg_rdata <= ch1_src_addr;
          8'h14: cfg_rdata <= ch1_dst_addr;
          8'h18: cfg_rdata <= ch1_length;
          8'h1C: cfg_rdata <= {29'h0, ch1_done, ch1_busy, 1'b0};

          8'h20: cfg_rdata <= ch2_src_addr;
          8'h24: cfg_rdata <= ch2_dst_addr;
          8'h28: cfg_rdata <= ch2_length;
          8'h2C: cfg_rdata <= {29'h0, ch2_done, ch2_busy, 1'b0};

          8'h30: cfg_rdata <= ch3_src_addr;
          8'h34: cfg_rdata <= ch3_dst_addr;
          8'h38: cfg_rdata <= ch3_length;
          8'h3C: cfg_rdata <= {29'h0, ch3_done, ch3_busy, 1'b0};

          8'h40: cfg_rdata <= {30'h0, ch0_burst_size};
          8'h44: cfg_rdata <= {30'h0, ch1_burst_size};
          8'h48: cfg_rdata <= {30'h0, ch2_burst_size};
          8'h4C: cfg_rdata <= {30'h0, ch3_burst_size};

          8'h50: cfg_rdata <= total_cycles;
          8'h54: cfg_rdata <= busy_cycles;
          8'h58: cfg_rdata <= total_words;
          8'h5C: cfg_rdata <= total_bursts;
          8'h60: cfg_rdata <= total_grants;

          8'h64: cfg_rdata <= ch0_words;
          8'h68: cfg_rdata <= ch1_words;
          8'h6C: cfg_rdata <= ch2_words;
          8'h70: cfg_rdata <= ch3_words;

          8'h74: cfg_rdata <= ch0_bursts;
          8'h78: cfg_rdata <= ch1_bursts;
          8'h7C: cfg_rdata <= ch2_bursts;
          8'h80: cfg_rdata <= ch3_bursts;

          8'h84: cfg_rdata <= (ch0_current_burst == 2'd0) ? 32'd1  :
                              (ch0_current_burst == 2'd1) ? 32'd4  :
                              (ch0_current_burst == 2'd2) ? 32'd8  : 32'd16;

          8'h88: cfg_rdata <= (ch1_current_burst == 2'd0) ? 32'd1  :
                              (ch1_current_burst == 2'd1) ? 32'd4  :
                              (ch1_current_burst == 2'd2) ? 32'd8  : 32'd16;

          8'h8C: cfg_rdata <= (ch2_current_burst == 2'd0) ? 32'd1  :
                              (ch2_current_burst == 2'd1) ? 32'd4  :
                              (ch2_current_burst == 2'd2) ? 32'd8  : 32'd16;

          8'h90: cfg_rdata <= (ch3_current_burst == 2'd0) ? 32'd1  :
                              (ch3_current_burst == 2'd1) ? 32'd4  :
                              (ch3_current_burst == 2'd2) ? 32'd8  : 32'd16;

          8'h98: cfg_rdata <= {31'h0, adaptive_en};

          default: cfg_rdata <= 32'hDEADBEEF;
        endcase
        cfg_ready <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Instantiate 4 DMA Channels
  // ---------------------------------------------------------------------------
  dma_channel_final #(.CHANNEL_ID(0)) ch0 (
    .clk(clk), .rst_n(rst_n),
    .src_addr_reg(ch0_src_addr), .dst_addr_reg(ch0_dst_addr),
    .length_reg(ch0_length),     .burst_size_reg(ch0_burst_size),
    .burst_size_update(ch0_burst_size_update), .adaptive_en(adaptive_en),
    .start_bit(ch0_start),
    .busy(ch0_busy),             .done(ch0_done),
    .req(ch0_req),               .grant(ch0_grant),
    .burst_active(ch0_burst_active),
    .mem_addr(ch0_mem_addr),     .mem_wdata(ch0_mem_wdata),
    .mem_rdata(ch0_mem_rdata),   .mem_write_en(ch0_mem_write_en),
    .mem_read_en(ch0_mem_read_en), .mem_valid(ch0_mem_valid),
    .mem_ready(ch0_mem_ready),
    .burst_done(ch0_burst_done), .current_burst_level(ch0_current_burst),
    .burst_size_words(ch0_burst_words), .burst_count_out(ch0_burst_cnt),
    .remaining_length_out(ch0_rem_len),
    .source_addr_out(ch0_src_out), .destination_addr_out(ch0_dst_out)
  );

  dma_channel_final #(.CHANNEL_ID(1)) ch1 (
    .clk(clk), .rst_n(rst_n),
    .src_addr_reg(ch1_src_addr), .dst_addr_reg(ch1_dst_addr),
    .length_reg(ch1_length),     .burst_size_reg(ch1_burst_size),
    .burst_size_update(ch1_burst_size_update), .adaptive_en(adaptive_en),
    .start_bit(ch1_start),
    .busy(ch1_busy),             .done(ch1_done),
    .req(ch1_req),               .grant(ch1_grant),
    .burst_active(ch1_burst_active),
    .mem_addr(ch1_mem_addr),     .mem_wdata(ch1_mem_wdata),
    .mem_rdata(ch1_mem_rdata),   .mem_write_en(ch1_mem_write_en),
    .mem_read_en(ch1_mem_read_en), .mem_valid(ch1_mem_valid),
    .mem_ready(ch1_mem_ready),
    .burst_done(ch1_burst_done), .current_burst_level(ch1_current_burst),
    .burst_size_words(ch1_burst_words), .burst_count_out(ch1_burst_cnt),
    .remaining_length_out(ch1_rem_len),
    .source_addr_out(ch1_src_out), .destination_addr_out(ch1_dst_out)
  );

  dma_channel_final #(.CHANNEL_ID(2)) ch2 (
    .clk(clk), .rst_n(rst_n),
    .src_addr_reg(ch2_src_addr), .dst_addr_reg(ch2_dst_addr),
    .length_reg(ch2_length),     .burst_size_reg(ch2_burst_size),
    .burst_size_update(ch2_burst_size_update), .adaptive_en(adaptive_en),
    .start_bit(ch2_start),
    .busy(ch2_busy),             .done(ch2_done),
    .req(ch2_req),               .grant(ch2_grant),
    .burst_active(ch2_burst_active),
    .mem_addr(ch2_mem_addr),     .mem_wdata(ch2_mem_wdata),
    .mem_rdata(ch2_mem_rdata),   .mem_write_en(ch2_mem_write_en),
    .mem_read_en(ch2_mem_read_en), .mem_valid(ch2_mem_valid),
    .mem_ready(ch2_mem_ready),
    .burst_done(ch2_burst_done), .current_burst_level(ch2_current_burst),
    .burst_size_words(ch2_burst_words), .burst_count_out(ch2_burst_cnt),
    .remaining_length_out(ch2_rem_len),
    .source_addr_out(ch2_src_out), .destination_addr_out(ch2_dst_out)
  );

  dma_channel_final #(.CHANNEL_ID(3)) ch3 (
    .clk(clk), .rst_n(rst_n),
    .src_addr_reg(ch3_src_addr), .dst_addr_reg(ch3_dst_addr),
    .length_reg(ch3_length),     .burst_size_reg(ch3_burst_size),
    .burst_size_update(ch3_burst_size_update), .adaptive_en(adaptive_en),
    .start_bit(ch3_start),
    .busy(ch3_busy),             .done(ch3_done),
    .req(ch3_req),               .grant(ch3_grant),
    .burst_active(ch3_burst_active),
    .mem_addr(ch3_mem_addr),     .mem_wdata(ch3_mem_wdata),
    .mem_rdata(ch3_mem_rdata),   .mem_write_en(ch3_mem_write_en),
    .mem_read_en(ch3_mem_read_en), .mem_valid(ch3_mem_valid),
    .mem_ready(ch3_mem_ready),
    .burst_done(ch3_burst_done), .current_burst_level(ch3_current_burst),
    .burst_size_words(ch3_burst_words), .burst_count_out(ch3_burst_cnt),
    .remaining_length_out(ch3_rem_len),
    .source_addr_out(ch3_src_out), .destination_addr_out(ch3_dst_out)
  );

  // ---------------------------------------------------------------------------
  // 4-Channel Arbiter & Bus Ownership
  // ---------------------------------------------------------------------------
  reg  [1:0] active_channel;
  wire       bus_busy;
  wire [3:0] arb_grant;

  assign ch0_grant = arb_grant[0];
  assign ch1_grant = arb_grant[1];
  assign ch2_grant = arb_grant[2];
  assign ch3_grant = arb_grant[3];

  assign bus_busy = ch0_burst_active | ch1_burst_active | ch2_burst_active | ch3_burst_active;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_channel <= 2'd0;
    end else begin
      if (|arb_grant) begin
        active_channel <= arb_grant[0] ? 2'd0 :
                          arb_grant[1] ? 2'd1 :
                          arb_grant[2] ? 2'd2 : 2'd3;
      end
    end
  end

  dma_arbiter_final arb (
    .clk     (clk),
    .rst_n   (rst_n),
    .req     ({ch3_req, ch2_req, ch1_req, ch0_req}),
    .bus_busy(bus_busy),
    .grant   (arb_grant)
  );

  // ---------------------------------------------------------------------------
  // Memory Interface Multiplexer
  // ---------------------------------------------------------------------------
  reg [1:0] sel_ch;
  always @* begin
    if (|arb_grant) begin
      if      (arb_grant[0]) sel_ch = 2'd0;
      else if (arb_grant[1]) sel_ch = 2'd1;
      else if (arb_grant[2]) sel_ch = 2'd2;
      else                   sel_ch = 2'd3;
    end else begin
      sel_ch = active_channel;
    end
  end

  always @* begin
    mem_addr      = 32'h0;
    mem_wdata     = 32'h0;
    mem_write_en  = 1'b0;
    mem_read_en   = 1'b0;
    mem_valid     = 1'b0;
    burst_done    = 1'b0;

    ch0_mem_rdata = 32'h0;
    ch0_mem_ready = 1'b0;
    ch1_mem_rdata = 32'h0;
    ch1_mem_ready = 1'b0;
    ch2_mem_rdata = 32'h0;
    ch2_mem_ready = 1'b0;
    ch3_mem_rdata = 32'h0;
    ch3_mem_ready = 1'b0;

    case (sel_ch)
      2'd0: begin
        mem_addr      = ch0_mem_addr;
        mem_wdata     = ch0_mem_wdata;
        mem_write_en  = ch0_mem_write_en;
        mem_read_en   = ch0_mem_read_en;
        mem_valid     = ch0_mem_valid;
        burst_done    = ch0_burst_done;
        ch0_mem_rdata = mem_rdata;
        ch0_mem_ready = mem_ready;
      end
      2'd1: begin
        mem_addr      = ch1_mem_addr;
        mem_wdata     = ch1_mem_wdata;
        mem_write_en  = ch1_mem_write_en;
        mem_read_en   = ch1_mem_read_en;
        mem_valid     = ch1_mem_valid;
        burst_done    = ch1_burst_done;
        ch1_mem_rdata = mem_rdata;
        ch1_mem_ready = mem_ready;
      end
      2'd2: begin
        mem_addr      = ch2_mem_addr;
        mem_wdata     = ch2_mem_wdata;
        mem_write_en  = ch2_mem_write_en;
        mem_read_en   = ch2_mem_read_en;
        mem_valid     = ch2_mem_valid;
        burst_done    = ch2_burst_done;
        ch2_mem_rdata = mem_rdata;
        ch2_mem_ready = mem_ready;
      end
      2'd3: begin
        mem_addr      = ch3_mem_addr;
        mem_wdata     = ch3_mem_wdata;
        mem_write_en  = ch3_mem_write_en;
        mem_read_en   = ch3_mem_read_en;
        mem_valid     = ch3_mem_valid;
        burst_done    = ch3_burst_done;
        ch3_mem_rdata = mem_rdata;
        ch3_mem_ready = mem_ready;
      end
    endcase
  end

  assign current_burst_level = (sel_ch == 2'd0) ? ch0_current_burst :
                               (sel_ch == 2'd1) ? ch1_current_burst :
                               (sel_ch == 2'd2) ? ch2_current_burst : ch3_current_burst;

  // ---------------------------------------------------------------------------
  // PMU Counter Updates & Clear Logic
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      total_cycles <= 32'h0;
      busy_cycles  <= 32'h0;
      total_words  <= 32'h0;
      total_bursts <= 32'h0;
      total_grants <= 32'h0;
      ch0_words    <= 32'h0;
      ch0_bursts   <= 32'h0;
      ch1_words    <= 32'h0;
      ch1_bursts   <= 32'h0;
      ch2_words    <= 32'h0;
      ch2_bursts   <= 32'h0;
      ch3_words    <= 32'h0;
      ch3_bursts   <= 32'h0;
    end else begin
      // PMU Clear Trigger (write 1 to bit 0 of 0x94)
      if (cfg_write_en && (cfg_addr == 8'h94) && cfg_wdata[0]) begin
        total_cycles <= 32'h0;
        busy_cycles  <= 32'h0;
        total_words  <= 32'h0;
        total_bursts <= 32'h0;
        total_grants <= 32'h0;
        ch0_words    <= 32'h0;
        ch0_bursts   <= 32'h0;
        ch1_words    <= 32'h0;
        ch1_bursts   <= 32'h0;
        ch2_words    <= 32'h0;
        ch2_bursts   <= 32'h0;
        ch3_words    <= 32'h0;
        ch3_bursts   <= 32'h0;
      end else begin
        total_cycles <= total_cycles + 32'd1;
        if (bus_busy) busy_cycles <= busy_cycles + 32'd1;

        if (|arb_grant) total_grants <= total_grants + 32'd1;

        // Word transfer accounting
        if (mem_valid && mem_write_en && mem_ready) begin
          total_words <= total_words + 32'd1;
          if (sel_ch == 2'd0) ch0_words <= ch0_words + 32'd1;
          if (sel_ch == 2'd1) ch1_words <= ch1_words + 32'd1;
          if (sel_ch == 2'd2) ch2_words <= ch2_words + 32'd1;
          if (sel_ch == 2'd3) ch3_words <= ch3_words + 32'd1;
        end

        // Burst completion accounting
        if (ch0_burst_done) ch0_bursts <= ch0_bursts + 32'd1;
        if (ch1_burst_done) ch1_bursts <= ch1_bursts + 32'd1;
        if (ch2_burst_done) ch2_bursts <= ch2_bursts + 32'd1;
        if (ch3_burst_done) ch3_bursts <= ch3_bursts + 32'd1;

        if (ch0_burst_done || ch1_burst_done || ch2_burst_done || ch3_burst_done) begin
          total_bursts <= total_bursts + 32'd1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Waveform-Friendly Internal Signals (Section 10 Compliance)
  // ---------------------------------------------------------------------------
  wire [1:0]  current_channel;
  wire [3:0]  grant;
  wire [3:0]  request;
  wire [4:0]  burst_count;
  wire [4:0]  burst_size;
  wire [1:0]  adaptive_level;
  wire [31:0] remaining_length;
  wire [31:0] source_addr;
  wire [31:0] destination_addr;

  assign current_channel  = sel_ch;
  assign grant            = arb_grant;
  assign request          = {ch3_req, ch2_req, ch1_req, ch0_req};
  assign burst_count      = (sel_ch == 2'd0) ? ch0_burst_cnt :
                            (sel_ch == 2'd1) ? ch1_burst_cnt :
                            (sel_ch == 2'd2) ? ch2_burst_cnt : ch3_burst_cnt;
  assign burst_size       = (sel_ch == 2'd0) ? ch0_burst_words :
                            (sel_ch == 2'd1) ? ch1_burst_words :
                            (sel_ch == 2'd2) ? ch2_burst_words : ch3_burst_words;
  assign adaptive_level   = current_burst_level;
  assign remaining_length = (sel_ch == 2'd0) ? ch0_rem_len :
                            (sel_ch == 2'd1) ? ch1_rem_len :
                            (sel_ch == 2'd2) ? ch2_rem_len : ch3_rem_len;
  assign source_addr      = (sel_ch == 2'd0) ? ch0_src_out :
                            (sel_ch == 2'd1) ? ch1_src_out :
                            (sel_ch == 2'd2) ? ch2_src_out : ch3_src_out;
  assign destination_addr = (sel_ch == 2'd0) ? ch0_dst_out :
                            (sel_ch == 2'd1) ? ch1_dst_out :
                            (sel_ch == 2'd2) ? ch2_dst_out : ch3_dst_out;

endmodule
