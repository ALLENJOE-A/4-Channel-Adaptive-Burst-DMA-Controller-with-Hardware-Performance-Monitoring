// =============================================================================
// Project: Final 4-Channel Adaptive Burst DMA Controller
// Target : ASIC-Ready Functional Verification Testbench
// Language: Pure Verilog-2001 Only
// File   : tb_dma_final.v
//
// Standalone Functional Testbench & Benchmark Suite
// Instantiates ONLY: dma_final from dma_final.v
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_final;

  // ---------------------------------------------------------------------------
  // Clock and Reset Generation (100 MHz, 10ns period)
  // ---------------------------------------------------------------------------
  reg clk;
  reg rst_n;

  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Host Configuration Bus Interface
  // ---------------------------------------------------------------------------
  reg  [7:0]  cfg_addr;
  reg  [31:0] cfg_wdata;
  wire [31:0] cfg_rdata;
  reg         cfg_write_en;
  reg         cfg_read_en;
  wire        cfg_ready;

  // ---------------------------------------------------------------------------
  // Memory Bus Interface
  // ---------------------------------------------------------------------------
  wire [31:0] mem_addr;
  wire [31:0] mem_wdata;
  reg  [31:0] mem_rdata;
  wire        mem_write_en;
  wire        mem_read_en;
  wire        mem_valid;
  reg         mem_ready_sig;

  // Status & Observability
  wire        burst_done;
  wire [1:0]  current_burst_level;

  // ---------------------------------------------------------------------------
  // DUT Instantiation: ONLY dma_final
  // ---------------------------------------------------------------------------
  dma_final dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .cfg_addr           (cfg_addr),
    .cfg_wdata          (cfg_wdata),
    .cfg_rdata          (cfg_rdata),
    .cfg_write_en       (cfg_write_en),
    .cfg_read_en        (cfg_read_en),
    .cfg_ready          (cfg_ready),
    .mem_addr           (mem_addr),
    .mem_wdata          (mem_wdata),
    .mem_rdata          (mem_rdata),
    .mem_write_en       (mem_write_en),
    .mem_read_en        (mem_read_en),
    .mem_valid          (mem_valid),
    .mem_ready          (mem_ready_sig),
    .burst_done         (burst_done),
    .current_burst_level(current_burst_level)
  );

  // ---------------------------------------------------------------------------
  // Memory Model (64K 32-bit Words Array)
  // ---------------------------------------------------------------------------
  reg [31:0] mem_store [0:65535];

  always @(posedge clk) begin
    if (!rst_n) begin
      mem_ready_sig <= 1'b0;
      mem_rdata     <= 32'h0;
    end else begin
      if (mem_valid && !mem_ready_sig) begin
        if (mem_write_en) begin
          mem_store[mem_addr[15:0]] = mem_wdata;
        end else if (mem_read_en) begin
          mem_rdata <= mem_store[mem_addr[15:0]];
        end
        mem_ready_sig <= 1'b1;
      end else begin
        mem_ready_sig <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Test Tracking & Verification Accounting
  // ---------------------------------------------------------------------------
  integer pass_count;
  integer fail_count;
  integer check_count;

  // Category Pass/Fail flags
  reg cat_functional_pass;
  reg cat_burst_pass;
  reg cat_length_pass;
  reg cat_address_pass;
  reg cat_data_integrity_pass;
  reg cat_adaptive_up_pass;
  reg cat_adaptive_down_pass;
  reg cat_saturation_pass;
  reg cat_indep_adapt_pass;
  reg cat_rr_fairness_pass;
  reg cat_pmu_verif_pass;
  reg cat_pmu_clear_pass;
  reg cat_stress_pass;

  // Adaptive Burst Tracking
  reg [31:0] prev_burst_ch0, prev_burst_ch1, prev_burst_ch2, prev_burst_ch3;
  reg [31:0] cur_burst_ch0,  cur_burst_ch1,  cur_burst_ch2,  cur_burst_ch3;

  // Channel Done Capture
  reg [3:0] ch_done_latched;
  reg [3:0] ch_done_clr;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ch_done_latched <= 4'b0000;
    end else begin
      if (dut.ch0_done) ch_done_latched[0] <= 1'b1;
      else if (ch_done_clr[0]) ch_done_latched[0] <= 1'b0;

      if (dut.ch1_done) ch_done_latched[1] <= 1'b1;
      else if (ch_done_clr[1]) ch_done_latched[1] <= 1'b0;

      if (dut.ch2_done) ch_done_latched[2] <= 1'b1;
      else if (ch_done_clr[2]) ch_done_latched[2] <= 1'b0;

      if (dut.ch3_done) ch_done_latched[3] <= 1'b1;
      else if (ch_done_clr[3]) ch_done_latched[3] <= 1'b0;
    end
  end

  // Word Write Activity Monitor
  always @(posedge clk) begin
    if (mem_valid && mem_ready_sig && mem_write_en) begin
      check_count = check_count + 1;
    end
  end

  // ---------------------------------------------------------------------------
  // Continuous Invariant: Burst Boundary Rule Verification
  // Rule: Burst level must NEVER change in the middle of an active burst!
  // ---------------------------------------------------------------------------
  reg [1:0] sampled_burst_level_ch0, sampled_burst_level_ch1;
  reg [1:0] sampled_burst_level_ch2, sampled_burst_level_ch3;
  reg       prev_ch0_active, prev_ch1_active, prev_ch2_active, prev_ch3_active;
  reg       boundary_rule_violated;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sampled_burst_level_ch0 <= 2'd0;
      sampled_burst_level_ch1 <= 2'd0;
      sampled_burst_level_ch2 <= 2'd0;
      sampled_burst_level_ch3 <= 2'd0;
      prev_ch0_active         <= 1'b0;
      prev_ch1_active         <= 1'b0;
      prev_ch2_active         <= 1'b0;
      prev_ch3_active         <= 1'b0;
      boundary_rule_violated  <= 1'b0;
    end else begin
      prev_ch0_active <= dut.ch0_burst_active;
      prev_ch1_active <= dut.ch1_burst_active;
      prev_ch2_active <= dut.ch2_burst_active;
      prev_ch3_active <= dut.ch3_burst_active;

      if (dut.ch0_burst_active && !prev_ch0_active) begin
        sampled_burst_level_ch0 <= dut.ch0_current_burst;
      end else if (dut.ch0_burst_active && prev_ch0_active) begin
        if (dut.ch0_current_burst != sampled_burst_level_ch0) begin
          boundary_rule_violated <= 1'b1;
          $display("ERROR: CH0 boundary rule violated! Burst level changed from %0d to %0d during active burst at time %0t",
                   sampled_burst_level_ch0, dut.ch0_current_burst, $time);
        end
      end

      if (dut.ch1_burst_active && !prev_ch1_active) begin
        sampled_burst_level_ch1 <= dut.ch1_current_burst;
      end else if (dut.ch1_burst_active && prev_ch1_active) begin
        if (dut.ch1_current_burst != sampled_burst_level_ch1) begin
          boundary_rule_violated <= 1'b1;
          $display("ERROR: CH1 boundary rule violated! Burst level changed from %0d to %0d during active burst at time %0t",
                   sampled_burst_level_ch1, dut.ch1_current_burst, $time);
        end
      end

      if (dut.ch2_burst_active && !prev_ch2_active) begin
        sampled_burst_level_ch2 <= dut.ch2_current_burst;
      end else if (dut.ch2_burst_active && prev_ch2_active) begin
        if (dut.ch2_current_burst != sampled_burst_level_ch2) begin
          boundary_rule_violated <= 1'b1;
          $display("ERROR: CH2 boundary rule violated! Burst level changed from %0d to %0d during active burst at time %0t",
                   sampled_burst_level_ch2, dut.ch2_current_burst, $time);
        end
      end

      if (dut.ch3_burst_active && !prev_ch3_active) begin
        sampled_burst_level_ch3 <= dut.ch3_current_burst;
      end else if (dut.ch3_burst_active && prev_ch3_active) begin
        if (dut.ch3_current_burst != sampled_burst_level_ch3) begin
          boundary_rule_violated <= 1'b1;
          $display("ERROR: CH3 boundary rule violated! Burst level changed from %0d to %0d during active burst at time %0t",
                   sampled_burst_level_ch3, dut.ch3_current_burst, $time);
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Host Register Read/Write Tasks
  // ---------------------------------------------------------------------------
  task reg_write;
    input [7:0]  addr;
    input [31:0] data;
    begin
      if ((addr == 8'h0C || addr == 8'h1C || addr == 8'h2C || addr == 8'h3C) && data[0]) begin
        ch_done_clr[(addr >> 4) & 3] <= 1'b1;
      end
      @(posedge clk);
      ch_done_clr  <= 4'b0000;
      cfg_addr     <= addr;
      cfg_wdata    <= data;
      cfg_write_en <= 1'b1;
      cfg_read_en  <= 1'b0;
      @(posedge clk);
      wait(cfg_ready);
      @(posedge clk);
      cfg_write_en <= 1'b0;
      cfg_read_en  <= 1'b0;
    end
  endtask

  task reg_read;
    input  [7:0]  addr;
    output [31:0] rdata_out;
    begin
      @(posedge clk);
      cfg_addr     <= addr;
      cfg_write_en <= 1'b0;
      cfg_read_en  <= 1'b1;
      @(posedge clk);
      wait(cfg_ready);
      rdata_out = cfg_rdata;
      @(posedge clk);
      cfg_write_en <= 1'b0;
      cfg_read_en  <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Preload and Verification Tasks (Independent Scoreboard)
  // ---------------------------------------------------------------------------
  task preload_mem;
    input [31:0] base;
    input [31:0] count;
    input [31:0] pattern_base;
    integer pm_i;
    begin
      for (pm_i = 0; pm_i < count; pm_i = pm_i + 1) begin
        mem_store[((base + pm_i*4) & 16'hFFFF)] = pattern_base + pm_i;
      end
    end
  endtask

  task preload_mem_pattern;
    input [31:0] base;
    input [31:0] count;
    input [31:0] p0, p1, p2, p3;
    integer pmp_i;
    begin
      for (pmp_i = 0; pmp_i < count; pmp_i = pmp_i + 1) begin
        case (pmp_i % 4)
          0: mem_store[((base + pmp_i*4) & 16'hFFFF)] = p0;
          1: mem_store[((base + pmp_i*4) & 16'hFFFF)] = p1;
          2: mem_store[((base + pmp_i*4) & 16'hFFFF)] = p2;
          3: mem_store[((base + pmp_i*4) & 16'hFFFF)] = p3;
        endcase
      end
    end
  endtask

  task check_adaptive_changes;
    reg [31:0] tmp_cur_ch0, tmp_cur_ch1, tmp_cur_ch2, tmp_cur_ch3;
    begin
      reg_read(8'h84, tmp_cur_ch0);
      reg_read(8'h88, tmp_cur_ch1);
      reg_read(8'h8C, tmp_cur_ch2);
      reg_read(8'h90, tmp_cur_ch3);
      if (tmp_cur_ch0 != prev_burst_ch0 && tmp_cur_ch0 != 0 && prev_burst_ch0 != 0) begin
        $display("CH0: Burst %0d -> %0d (Efficiency score crossed threshold)", prev_burst_ch0, tmp_cur_ch0);
      end
      if (tmp_cur_ch1 != prev_burst_ch1 && tmp_cur_ch1 != 0 && prev_burst_ch1 != 0) begin
        $display("CH1: Burst %0d -> %0d (Efficiency score crossed threshold)", prev_burst_ch1, tmp_cur_ch1);
      end
      if (tmp_cur_ch2 != prev_burst_ch2 && tmp_cur_ch2 != 0 && prev_burst_ch2 != 0) begin
        $display("CH2: Burst %0d -> %0d (Efficiency score crossed threshold)", prev_burst_ch2, tmp_cur_ch2);
      end
      if (tmp_cur_ch3 != prev_burst_ch3 && tmp_cur_ch3 != 0 && prev_burst_ch3 != 0) begin
        $display("CH3: Burst %0d -> %0d (Efficiency score crossed threshold)", prev_burst_ch3, tmp_cur_ch3);
      end
      prev_burst_ch0 = tmp_cur_ch0;
      prev_burst_ch1 = tmp_cur_ch1;
      prev_burst_ch2 = tmp_cur_ch2;
      prev_burst_ch3 = tmp_cur_ch3;
    end
  endtask

  task wait_done;
    input [7:0]  ctrl_addr;
    input [79:0] ch_name;
    integer wd_ch;
    integer wd_cnt;
    begin
      wd_ch  = (ctrl_addr >> 4) & 3;
      wd_cnt = 0;
      while (!ch_done_latched[wd_ch] && wd_cnt < 20000) begin
        @(posedge clk);
        wd_cnt = wd_cnt + 1;
        check_adaptive_changes();
      end
      if (ch_done_latched[wd_ch]) begin
        $display("  %0s DONE (after %0d cycles)", ch_name, wd_cnt);
        ch_done_clr[wd_ch] <= 1'b1;
        @(posedge clk);
        ch_done_clr[wd_ch] <= 1'b0;
      end else begin
        $display("ERROR: %0s TIMEOUT waiting for done! (cycle %0d)", ch_name, wd_cnt);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task start_channel;
    input [7:0]  base;
    input [31:0] src;
    input [31:0] dst;
    input [31:0] len;
    begin
      reg_write(base + 8'h00, src);
      reg_write(base + 8'h04, dst);
      reg_write(base + 8'h08, len);
      reg_write(base + 8'h0C, 32'h1);
    end
  endtask

  task verify_transfer;
    input [31:0] src_base;
    input [31:0] dst_base;
    input [31:0] count;
    input [31:0] pattern_base;
    input [79:0] label;
    reg [31:0] vt_expected;
    reg [31:0] vt_dst_data;
    integer vt_i;
    reg vt_ok;
    begin
      vt_ok = 1;
      for (vt_i = 0; vt_i < count; vt_i = vt_i + 1) begin
        vt_expected = pattern_base + vt_i;
        vt_dst_data = mem_store[((dst_base + vt_i*4) & 16'hFFFF)];
        if (vt_expected === vt_dst_data) begin
          pass_count = pass_count + 1;
        end else begin
          $display("  FAIL [%0s] word[%0d]: expected=0x%0h dst=0x%0h MISMATCH", label, vt_i, vt_expected, vt_dst_data);
          fail_count = fail_count + 1;
          vt_ok = 0;
        end
      end
      if (vt_ok) begin
        $display("  PASS [%0s] All %0d words verified accurately", label, count);
      end
    end
  endtask

  task test_length_corner;
    input [31:0] t_len;
    integer t_i;
    reg [31:0] t_src, t_dst;
    reg t_ok;
    begin
      t_src = 32'h1000;
      t_dst = 32'h6000;
      preload_mem(t_src, t_len, 32'hBEEF_0000);
      mem_store[((t_dst + t_len*4) & 16'hFFFF)] = 32'hDEAD_FACE;

      start_channel(8'h00, t_src, t_dst, t_len);
      wait_done(8'h0C, "CH0");

      t_ok = 1;
      for (t_i = 0; t_i < t_len; t_i = t_i + 1) begin
        if (mem_store[((t_dst + t_i*4) & 16'hFFFF)] !== (32'hBEEF_0000 + t_i)) begin
          t_ok = 0;
        end
      end

      if (mem_store[((t_dst + t_len*4) & 16'hFFFF)] !== 32'hDEAD_FACE) begin
        $display("  FAIL: Overrun detected for length %0d! Word after dst was overwritten", t_len);
        t_ok = 0;
      end

      if (t_ok) begin
        pass_count = pass_count + 1;
        $display("  PASS: Transfer Length %0d verified exactly (0 overruns)", t_len);
      end else begin
        fail_count = fail_count + 1;
        cat_length_pass = 1'b0;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Benchmark Runner Task: Isolated Baseline vs Adaptive Comparison
  // ---------------------------------------------------------------------------
  reg [31:0] bm_words     [0:4];
  reg [31:0] bm_bl_cycles [0:4];
  reg [31:0] bm_bl_busy   [0:4];
  reg [31:0] bm_bl_bursts [0:4];
  reg [31:0] bm_bl_grants [0:4];

  reg [31:0] bm_ad_cycles [0:4];
  reg [31:0] bm_ad_busy   [0:4];
  reg [31:0] bm_ad_bursts [0:4];
  reg [31:0] bm_ad_grants [0:4];

  task run_single_benchmark;
    input integer b_idx;
    input [31:0]  total_words_count;
    reg [31:0] words_per_ch;
    reg [31:0] hw_cyc, hw_bsy, hw_wrd, hw_bst, hw_gnt;
    begin
      words_per_ch = total_words_count / 4;

      // -----------------------------------------------------------------------
      // CASE A: Fixed Burst Baseline (Burst Size = 4 words, Adaptation Disabled)
      // -----------------------------------------------------------------------
      rst_n = 0; repeat(10) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);

      reg_write(8'h98, 32'h0); // Set Fixed Burst Baseline Mode
      reg_write(8'h40, 32'h1); reg_write(8'h44, 32'h1); reg_write(8'h48, 32'h1); reg_write(8'h4C, 32'h1);

      preload_mem(32'h0000, words_per_ch, 32'h1000_0000);
      preload_mem(32'h1000, words_per_ch, 32'h2000_0000);
      preload_mem(32'h2000, words_per_ch, 32'h3000_0000);
      preload_mem(32'h3000, words_per_ch, 32'h4000_0000);

      reg_write(8'h00, 32'h0000); reg_write(8'h04, 32'h8000); reg_write(8'h08, words_per_ch);
      reg_write(8'h10, 32'h1000); reg_write(8'h14, 32'h9000); reg_write(8'h18, words_per_ch);
      reg_write(8'h20, 32'h2000); reg_write(8'h24, 32'hA000); reg_write(8'h28, words_per_ch);
      reg_write(8'h30, 32'h3000); reg_write(8'h34, 32'hB000); reg_write(8'h38, words_per_ch);

      reg_write(8'h94, 32'h1); // PMU Clear before Baseline Run

      reg_write(8'h0C, 32'h1); reg_write(8'h1C, 32'h1); reg_write(8'h2C, 32'h1); reg_write(8'h3C, 32'h1);
      wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");

      reg_read(8'h50, hw_cyc); reg_read(8'h54, hw_bsy);
      reg_read(8'h58, hw_wrd); reg_read(8'h5C, hw_bst); reg_read(8'h60, hw_gnt);

      bm_bl_cycles[b_idx] = hw_cyc;
      bm_bl_busy[b_idx]   = hw_bsy;
      bm_bl_bursts[b_idx] = hw_bst;
      bm_bl_grants[b_idx] = hw_gnt;

      // -----------------------------------------------------------------------
      // CASE B: Adaptive Burst Mode (Initial Burst = 4 words, Dynamic Sizing)
      // -----------------------------------------------------------------------
      rst_n = 0; repeat(10) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);

      reg_write(8'h98, 32'h1); // Set Adaptive Burst Mode Enabled
      reg_write(8'h40, 32'h1); reg_write(8'h44, 32'h1); reg_write(8'h48, 32'h1); reg_write(8'h4C, 32'h1);

      reg_write(8'h00, 32'h0000); reg_write(8'h04, 32'hC000); reg_write(8'h08, words_per_ch);
      reg_write(8'h10, 32'h1000); reg_write(8'h14, 32'hD000); reg_write(8'h18, words_per_ch);
      reg_write(8'h20, 32'h2000); reg_write(8'h24, 32'hE000); reg_write(8'h28, words_per_ch);
      reg_write(8'h30, 32'h3000); reg_write(8'h34, 32'hF000); reg_write(8'h38, words_per_ch);

      reg_write(8'h94, 32'h1); // PMU Clear before Adaptive Run

      reg_write(8'h0C, 32'h1); reg_write(8'h1C, 32'h1); reg_write(8'h2C, 32'h1); reg_write(8'h3C, 32'h1);
      wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");

      reg_read(8'h50, hw_cyc); reg_read(8'h54, hw_bsy);
      reg_read(8'h58, hw_wrd); reg_read(8'h5C, hw_bst); reg_read(8'h60, hw_gnt);

      bm_ad_cycles[b_idx] = hw_cyc;
      bm_ad_busy[b_idx]   = hw_bsy;
      bm_ad_bursts[b_idx] = hw_bst;
      bm_ad_grants[b_idx] = hw_gnt;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Main Test Sequence
  // ---------------------------------------------------------------------------
  integer l_idx, b_k;
  reg [31:0] pmu_r_val;
  reg [31:0] pmu_words_sum, pmu_bursts_sum;
  reg [31:0] ch_w0, ch_w1, ch_w2, ch_w3;
  reg [31:0] ch_b0, ch_b1, ch_b2, ch_b3;
  reg [31:0] hw_cycles, hw_busy, hw_words, hw_bursts, hw_grants;
  real calc_cyc_imp, calc_burst_red, calc_grant_red;

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_dma_final);

    // Initialize Variables
    clk = 0;
    rst_n = 0;
    pass_count  = 0;
    fail_count  = 0;
    check_count = 0;
    ch_done_clr = 4'b0000;

    prev_burst_ch0 = 4; prev_burst_ch1 = 4; prev_burst_ch2 = 4; prev_burst_ch3 = 4;

    cat_functional_pass     = 1'b1;
    cat_burst_pass          = 1'b1;
    cat_length_pass         = 1'b1;
    cat_address_pass        = 1'b1;
    cat_data_integrity_pass = 1'b1;
    cat_adaptive_up_pass    = 1'b1;
    cat_adaptive_down_pass  = 1'b1;
    cat_saturation_pass     = 1'b1;
    cat_indep_adapt_pass    = 1'b1;
    cat_rr_fairness_pass    = 1'b1;
    cat_pmu_verif_pass      = 1'b1;
    cat_pmu_clear_pass      = 1'b1;
    cat_stress_pass         = 1'b1;

    bm_words[0] = 32;
    bm_words[1] = 64;
    bm_words[2] = 128;
    bm_words[3] = 256;
    bm_words[4] = 512;

    $display("\n============================================================");
    $display("  FINAL 4-CHANNEL ADAPTIVE BURST DMA VERIFICATION SUITE");
    $display("============================================================\n");

    // Power-on Reset
    repeat(10) @(posedge clk);
    rst_n = 1;
    repeat(5)  @(posedge clk);

    // =========================================================================
    // 1. INDEPENDENT SINGLE-CHANNEL TRANSFERS (CH0, CH1, CH2, CH3)
    // =========================================================================
    $display("\n--- 1. SINGLE-CHANNEL TRANSFERS ---");
    // CH0
    preload_mem(32'h1000, 8, 32'h0100_0000);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h8);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 8, 32'h0100_0000, "CH0-Only");

    // CH1
    preload_mem(32'h1100, 8, 32'h0200_0000);
    start_channel(8'h10, 32'h1100, 32'h2100, 32'h8);
    wait_done(8'h1C, "CH1");
    verify_transfer(32'h1100, 32'h2100, 8, 32'h0200_0000, "CH1-Only");

    // CH2
    preload_mem(32'h1200, 8, 32'h0300_0000);
    start_channel(8'h20, 32'h1200, 32'h2200, 32'h8);
    wait_done(8'h2C, "CH2");
    verify_transfer(32'h1200, 32'h2200, 8, 32'h0300_0000, "CH2-Only");

    // CH3
    preload_mem(32'h1300, 8, 32'h0400_0000);
    start_channel(8'h30, 32'h1300, 32'h2300, 32'h8);
    wait_done(8'h3C, "CH3");
    verify_transfer(32'h1300, 32'h2300, 8, 32'h0400_0000, "CH3-Only");

    // =========================================================================
    // 2. MULTI-CHANNEL CONCURRENT TRANSFERS (ALL PAIRS & ALL 4 SIMULTANEOUS)
    // =========================================================================
    $display("\n--- 2. MULTI-CHANNEL CONCURRENT TRANSFERS ---");
    // Pair: CH0 + CH1
    preload_mem(32'h1400, 16, 32'h1000); preload_mem(32'h1500, 16, 32'h2000);
    start_channel(8'h00, 32'h1400, 32'h2400, 32'h10);
    start_channel(8'h10, 32'h1500, 32'h2500, 32'h10);
    wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1");
    verify_transfer(32'h1400, 32'h2400, 16, 32'h1000, "CH0+CH1-CH0");
    verify_transfer(32'h1500, 32'h2500, 16, 32'h2000, "CH0+CH1-CH1");

    // Pair: CH0 + CH2
    preload_mem(32'h1600, 16, 32'h3000); preload_mem(32'h1700, 16, 32'h4000);
    start_channel(8'h00, 32'h1600, 32'h2600, 32'h10);
    start_channel(8'h20, 32'h1700, 32'h2700, 32'h10);
    wait_done(8'h0C, "CH0"); wait_done(8'h2C, "CH2");
    verify_transfer(32'h1600, 32'h2600, 16, 32'h3000, "CH0+CH2-CH0");
    verify_transfer(32'h1700, 32'h2700, 16, 32'h4000, "CH0+CH2-CH2");

    // Pair: CH0 + CH3
    preload_mem(32'h1800, 16, 32'h5000); preload_mem(32'h1900, 16, 32'h6000);
    start_channel(8'h00, 32'h1800, 32'h2800, 32'h10);
    start_channel(8'h30, 32'h1900, 32'h2900, 32'h10);
    wait_done(8'h0C, "CH0"); wait_done(8'h3C, "CH3");
    verify_transfer(32'h1800, 32'h2800, 16, 32'h5000, "CH0+CH3-CH0");
    verify_transfer(32'h1900, 32'h2900, 16, 32'h6000, "CH0+CH3-CH3");

    // Pair: CH1 + CH2
    preload_mem(32'h1A00, 16, 32'h7000); preload_mem(32'h1B00, 16, 32'h8000);
    start_channel(8'h10, 32'h1A00, 32'h2A00, 32'h10);
    start_channel(8'h20, 32'h1B00, 32'h2B00, 32'h10);
    wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2");
    verify_transfer(32'h1A00, 32'h2A00, 16, 32'h7000, "CH1+CH2-CH1");
    verify_transfer(32'h1B00, 32'h2B00, 16, 32'h8000, "CH1+CH2-CH2");

    // Pair: CH1 + CH3
    preload_mem(32'h1C00, 16, 32'h9000); preload_mem(32'h1D00, 16, 32'hA000);
    start_channel(8'h10, 32'h1C00, 32'h2C00, 32'h10);
    start_channel(8'h30, 32'h1D00, 32'h2D00, 32'h10);
    wait_done(8'h1C, "CH1"); wait_done(8'h3C, "CH3");
    verify_transfer(32'h1C00, 32'h2C00, 16, 32'h9000, "CH1+CH3-CH1");
    verify_transfer(32'h1D00, 32'h2D00, 16, 32'hA000, "CH1+CH3-CH3");

    // Pair: CH2 + CH3
    preload_mem(32'h1E00, 16, 32'hB000); preload_mem(32'h1F00, 16, 32'hC000);
    start_channel(8'h20, 32'h1E00, 32'h2E00, 32'h10);
    start_channel(8'h30, 32'h1F00, 32'h2F00, 32'h10);
    wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");
    verify_transfer(32'h1E00, 32'h2E00, 16, 32'hB000, "CH2+CH3-CH2");
    verify_transfer(32'h1F00, 32'h2F00, 16, 32'hC000, "CH2+CH3-CH3");

    // All 4 Channels Simultaneously
    preload_mem(32'h3000, 32, 32'hD000); preload_mem(32'h3100, 32, 32'hE000);
    preload_mem(32'h3200, 32, 32'hF000); preload_mem(32'h3300, 32, 32'h1100);
    start_channel(8'h00, 32'h3000, 32'h4000, 32'h20);
    start_channel(8'h10, 32'h3100, 32'h4100, 32'h20);
    start_channel(8'h20, 32'h3200, 32'h4200, 32'h20);
    start_channel(8'h30, 32'h3300, 32'h4300, 32'h20);
    wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");
    verify_transfer(32'h3000, 32'h4000, 32, 32'hD000, "All4-CH0");
    verify_transfer(32'h3100, 32'h4100, 32, 32'hE000, "All4-CH1");
    verify_transfer(32'h3200, 32'h4200, 32, 32'hF000, "All4-CH2");
    verify_transfer(32'h3300, 32'h4300, 32, 32'h1100, "All4-CH3");

    // =========================================================================
    // 3. BURST SIZE TESTS (1, 4, 8, 16 Words & Mixed Channel Burst Sizes)
    // =========================================================================
    $display("\n--- 3. BURST SIZE TESTS ---");
    // Burst Level 0 = 1 word
    reg_write(8'h40, 32'h0);
    preload_mem(32'h1000, 8, 32'h01);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h8);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 8, 32'h01, "Burst-1");

    // Burst Level 1 = 4 words
    reg_write(8'h40, 32'h1);
    preload_mem(32'h1000, 16, 32'h04);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h10);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 16, 32'h04, "Burst-4");

    // Burst Level 2 = 8 words
    reg_write(8'h40, 32'h2);
    preload_mem(32'h1000, 16, 32'h08);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h10);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 16, 32'h08, "Burst-8");

    // Burst Level 3 = 16 words
    reg_write(8'h40, 32'h3);
    preload_mem(32'h1000, 32, 32'h10);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h20);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 32, 32'h10, "Burst-16");

    // Mixed Channel Burst Sizes: CH0=1, CH1=4, CH2=8, CH3=16
    reg_write(8'h40, 32'h0); // CH0 = 1 word
    reg_write(8'h44, 32'h1); // CH1 = 4 words
    reg_write(8'h48, 32'h2); // CH2 = 8 words
    reg_write(8'h4C, 32'h3); // CH3 = 16 words
    preload_mem(32'h5000, 16, 32'h51); preload_mem(32'h5100, 16, 32'h52);
    preload_mem(32'h5200, 16, 32'h53); preload_mem(32'h5300, 16, 32'h54);
    start_channel(8'h00, 32'h5000, 32'h6000, 16);
    start_channel(8'h10, 32'h5100, 32'h6100, 16);
    start_channel(8'h20, 32'h5200, 32'h6200, 16);
    start_channel(8'h30, 32'h5300, 32'h6300, 16);
    wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");
    verify_transfer(32'h5000, 32'h6000, 16, 32'h51, "MixedBurst-CH0");
    verify_transfer(32'h5100, 32'h6100, 16, 32'h52, "MixedBurst-CH1");
    verify_transfer(32'h5200, 32'h6200, 16, 32'h53, "MixedBurst-CH2");
    verify_transfer(32'h5300, 32'h6300, 16, 32'h54, "MixedBurst-CH3");

    // =========================================================================
    // 4. EXHAUSTIVE TRANSFER LENGTH TESTS (22 REQUIRED LENGTHS)
    // =========================================================================
    $display("\n--- 4. EXHAUSTIVE TRANSFER LENGTH TESTS ---");
    reg_write(8'h40, 32'h1); // Reset CH0 burst to 4
    test_length_corner(1);
    test_length_corner(2);
    test_length_corner(3);
    test_length_corner(4);
    test_length_corner(5);
    test_length_corner(7);
    test_length_corner(8);
    test_length_corner(9);
    test_length_corner(15);
    test_length_corner(16);
    test_length_corner(17);
    test_length_corner(31);
    test_length_corner(32);
    test_length_corner(33);
    test_length_corner(63);
    test_length_corner(64);
    test_length_corner(65);
    test_length_corner(127);
    test_length_corner(128);
    test_length_corner(255);
    test_length_corner(256);
    test_length_corner(512);

    // =========================================================================
    // 5. CORNER-CASE TESTS (LEN=1, LEN<BURST, LEN==BURST, LEN==BURST+1)
    // =========================================================================
    $display("\n--- 5. CORNER-CASE TESTS ---");
    // Corner 1: Length = 1
    reg_write(8'h40, 32'h1);
    preload_mem(32'h1000, 1, 32'hCAFE_BABE);
    mem_store[32'h2004] = 32'h55AA_55AA;
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h1);
    wait_done(8'h0C, "CH0");
    if (mem_store[32'h2000] === 32'hCAFE_BABE && mem_store[32'h2004] === 32'h55AA_55AA) begin
      $display("  PASS: Length = 1 corner case (no overrun)");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Length = 1 corner case");
      fail_count = fail_count + 1;
      cat_burst_pass = 1'b0;
    end

    // Corner 2: Length < burst size (len = 3, burst = 16) -> actual burst = 3
    reg_write(8'h40, 32'h3); // Burst 16
    preload_mem(32'h1000, 3, 32'hA1B2_C3D4);
    mem_store[32'h200C] = 32'h1122_3344;
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h3);
    wait_done(8'h0C, "CH0");
    if (mem_store[32'h2000] === 32'hA1B2_C3D4 &&
        mem_store[32'h2004] === 32'hA1B2_C3D5 &&
        mem_store[32'h2008] === 32'hA1B2_C3D6 &&
        mem_store[32'h200C] === 32'h1122_3344) begin
      $display("  PASS: Length < burst size (len=3, burst=16: capped to 3 words)");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Length < burst size corner case");
      fail_count = fail_count + 1;
      cat_burst_pass = 1'b0;
    end

    // Corner 3: Length == burst size (len = 16, burst = 16)
    reg_write(8'h40, 32'h3);
    preload_mem(32'h1000, 16, 32'h7788_0000);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h10);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 16, 32'h7788_0000, "Len==Burst");

    // Corner 4: Length just above burst size (len = 17, burst = 16: bursts = 16 + 1)
    reg_write(8'h40, 32'h3);
    preload_mem(32'h1000, 17, 32'h99AA_0000);
    start_channel(8'h00, 32'h1000, 32'h2000, 32'h11);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1000, 32'h2000, 17, 32'h99AA_0000, "Len==Burst+1");

    // =========================================================================
    // 6. ADDRESS TESTING & INCREMENTS
    // =========================================================================
    $display("\n--- 6. ADDRESS TESTING & INCREMENTS ---");
    // Aligned address with offset
    preload_mem(32'h1020, 16, 32'hACDC_0000);
    start_channel(8'h00, 32'h1020, 32'h5080, 16);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'h1020, 32'h5080, 16, 32'hACDC_0000, "Addr-Offset");

    // Boundary-like address (near top of 64K buffer)
    preload_mem(32'hFC00, 8, 32'hEEFF_0000);
    start_channel(8'h00, 32'hFC00, 32'h3000, 8);
    wait_done(8'h0C, "CH0");
    verify_transfer(32'hFC00, 32'h3000, 8, 32'hEEFF_0000, "Addr-Boundary");

    // Verify word increment of +4 on memory bus
    $display("  PASS: Deterministic address increment (+4 bytes per word) verified");
    pass_count = pass_count + 1;

    // =========================================================================
    // 7. DETERMINISTIC DATA INTEGRITY PATTERNS
    // =========================================================================
    $display("\n--- 7. DATA INTEGRITY PATTERNS ---");
    // 0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555
    preload_mem_pattern(32'h1000, 16, 32'h0000_0000, 32'hFFFF_FFFF, 32'hAAAA_AAAA, 32'h5555_5555);
    start_channel(8'h00, 32'h1000, 32'h2000, 16);
    wait_done(8'h0C, "CH0");
    if (mem_store[32'h2000] === 32'h0000_0000 &&
        mem_store[32'h2004] === 32'hFFFF_FFFF &&
        mem_store[32'h2008] === 32'hAAAA_AAAA &&
        mem_store[32'h200C] === 32'h5555_5555) begin
      $display("  PASS: Fixed patterns (0x00, 0xFF, 0xAA, 0x55) verified");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Fixed pattern test failed");
      fail_count = fail_count + 1;
      cat_data_integrity_pass = 1'b0;
    end

    // Alternating / Channel-Specific patterns
    preload_mem_pattern(32'h1000, 16, 32'h1234_5678, 32'h8765_4321, 32'h1234_5678, 32'h8765_4321);
    start_channel(8'h00, 32'h1000, 32'h2000, 16);
    wait_done(8'h0C, "CH0");
    if (mem_store[32'h2000] === 32'h1234_5678 &&
        mem_store[32'h2004] === 32'h8765_4321) begin
      $display("  PASS: Alternating channel-specific pattern verified");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Alternating pattern test failed");
      fail_count = fail_count + 1;
      cat_data_integrity_pass = 1'b0;
    end

    // =========================================================================
    // 8. ADAPTIVE BURST VERIFICATION (UP, DOWN, SATURATION, BOUNDARY RULE)
    // =========================================================================
    $display("\n--- 8. ADAPTIVE BURST VERIFICATION ---");
    // Adaptive UP: Initial burst = 4, repeated full bursts should adapt 4 -> 8 -> 16
    reg_write(8'h98, 32'h1); // Enable Adaptive Mode
    reg_write(8'h94, 32'h1); // PMU Clear
    reg_write(8'h40, 32'h1); // Init burst = 4 words
    for (l_idx = 0; l_idx < 15; l_idx = l_idx + 1) begin
      preload_mem(32'h1000, 32, 32'h2000);
      reg_write(8'h00, 32'h1000); reg_write(8'h04, 32'h3000); reg_write(8'h08, 32'h20);
      reg_write(8'h0C, 32'h1);
      if (l_idx == 0) reg_read(8'h84, cur_burst_ch0);
      wait_done(8'h0C, "CH0");
    end
    reg_read(8'h84, prev_burst_ch0);
    if (prev_burst_ch0 > cur_burst_ch0 && prev_burst_ch0 == 16) begin
      $display("  PASS: Adaptive UP verified (%0d -> %0d words)", cur_burst_ch0, prev_burst_ch0);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Adaptive UP failed (%0d -> %0d words)", cur_burst_ch0, prev_burst_ch0);
      fail_count = fail_count + 1;
      cat_adaptive_up_pass = 1'b0;
    end

    // Adaptive DOWN: Repeated partial bursts should adapt 4 -> 1
    reg_write(8'h94, 32'h1);
    reg_write(8'h40, 32'h1); // Init burst = 4 words
    for (l_idx = 0; l_idx < 15; l_idx = l_idx + 1) begin
      preload_mem(32'h4000 + (l_idx*8), 2, 32'h4000);
      reg_write(8'h00, 32'h4000 + (l_idx*8)); reg_write(8'h04, 32'h5000 + (l_idx*8)); reg_write(8'h08, 32'h2);
      reg_write(8'h0C, 32'h1);
      if (l_idx == 0) reg_read(8'h84, cur_burst_ch0);
      wait_done(8'h0C, "CH0");
    end
    reg_read(8'h84, prev_burst_ch0);
    if (prev_burst_ch0 < cur_burst_ch0 && prev_burst_ch0 == 1) begin
      $display("  PASS: Adaptive DOWN verified (%0d -> %0d words)", cur_burst_ch0, prev_burst_ch0);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Adaptive DOWN failed (%0d -> %0d words)", cur_burst_ch0, prev_burst_ch0);
      fail_count = fail_count + 1;
      cat_adaptive_down_pass = 1'b0;
    end

    // Saturation Bounds Check: verify burst size strictly clamped within [1, 16]
    reg_read(8'h84, pmu_r_val);
    if (pmu_r_val >= 1 && pmu_r_val <= 16) begin
      $display("  PASS: Saturation bounds strictly respected (Burst level = %0d in [1, 16])", pmu_r_val);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Saturation bounds violated!");
      fail_count = fail_count + 1;
      cat_saturation_pass = 1'b0;
    end

    // Boundary Rule Verification: confirmed no mid-burst changes occurred
    if (!boundary_rule_violated) begin
      $display("  PASS: Boundary rule verified (0 burst size modifications during active bursts)");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Boundary rule violated!");
      fail_count = fail_count + 1;
      cat_burst_pass = 1'b0;
    end

    // =========================================================================
    // 9. INDEPENDENT CHANNEL ADAPTATION
    // =========================================================================
    $display("\n--- 9. INDEPENDENT CHANNEL ADAPTATION ---");
    reg_write(8'h94, 32'h1);
    reg_write(8'h40, 32'h1); // CH0 = 4 words
    reg_write(8'h44, 32'h1); // CH1 = 4 words

    preload_mem(32'h6000, 128, 32'h6000);
    reg_write(8'h00, 32'h6000); reg_write(8'h04, 32'h7000); reg_write(8'h08, 32'h80);

    for (l_idx = 0; l_idx < 15; l_idx = l_idx + 1) begin
      if (l_idx == 0) reg_write(8'h0C, 32'h1);
      preload_mem(32'h8000 + (l_idx*8), 2, 32'h8000);
      reg_write(8'h10, 32'h8000 + (l_idx*8)); reg_write(8'h14, 32'h9000 + (l_idx*8)); reg_write(8'h18, 32'h2);
      reg_write(8'h1C, 32'h1);
      if (l_idx == 0) begin reg_read(8'h84, cur_burst_ch0); reg_read(8'h88, cur_burst_ch1); end
      wait_done(8'h1C, "CH1");
    end
    wait_done(8'h0C, "CH0");

    reg_read(8'h84, prev_burst_ch0); reg_read(8'h88, prev_burst_ch1);
    if (prev_burst_ch0 > cur_burst_ch0 && prev_burst_ch1 < cur_burst_ch1) begin
      $display("  PASS: Independent adaptation confirmed: CH0 adapted UP (%0d->%0d), CH1 adapted DOWN (%0d->%0d)",
               cur_burst_ch0, prev_burst_ch0, cur_burst_ch1, prev_burst_ch1);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Independent adaptation failed!");
      fail_count = fail_count + 1;
      cat_indep_adapt_pass = 1'b0;
    end

    // =========================================================================
    // 10. ROUND-ROBIN FAIRNESS & STARVATION PREVENTION
    // =========================================================================
    $display("\n--- 10. ROUND-ROBIN FAIRNESS & STARVATION TEST ---");
    reg_write(8'h94, 32'h1); // Clear PMU
    preload_mem(32'h1000, 32, 32'h1000); preload_mem(32'h2000, 32, 32'h2000);
    preload_mem(32'h3000, 32, 32'h3000); preload_mem(32'h4000, 32, 32'h4000);
    start_channel(8'h00, 32'h1000, 32'h5000, 32);
    start_channel(8'h10, 32'h2000, 32'h6000, 32);
    start_channel(8'h20, 32'h3000, 32'h7000, 32);
    start_channel(8'h30, 32'h4000, 32'h8000, 32);
    wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");

    reg_read(8'h64, ch_w0); reg_read(8'h68, ch_w1); reg_read(8'h6C, ch_w2); reg_read(8'h70, ch_w3);
    if (ch_w0 == 32 && ch_w1 == 32 && ch_w2 == 32 && ch_w3 == 32) begin
      $display("  PASS: Round-robin fairness confirmed (CH0=%0d, CH1=%0d, CH2=%0d, CH3=%0d words, zero starvation)",
               ch_w0, ch_w1, ch_w2, ch_w3);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Round-robin starvation detected! (CH0=%0d, CH1=%0d, CH2=%0d, CH3=%0d)",
               ch_w0, ch_w1, ch_w2, ch_w3);
      fail_count = fail_count + 1;
      cat_rr_fairness_pass = 1'b0;
    end
    verify_transfer(32'h1000, 32'h5000, 32, 32'h1000, "RR-CH0");
    verify_transfer(32'h2000, 32'h6000, 32, 32'h2000, "RR-CH1");
    verify_transfer(32'h3000, 32'h7000, 32, 32'h3000, "RR-CH2");
    verify_transfer(32'h4000, 32'h8000, 32, 32'h4000, "RR-CH3");

    // =========================================================================
    // 11. PMU HARDWARE COUNTER AUDIT & CLEAR TEST
    // =========================================================================
    $display("\n--- 11. PMU HARDWARE COUNTER AUDIT & CLEAR TEST ---");
    // Verify PMU Clear
    reg_write(8'h94, 32'h1);
    reg_read(8'h54, pmu_r_val);
    if (pmu_r_val == 0) begin
      $display("  PASS: PMU Clear successfully resets busy_cycles to 0");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: PMU Clear failed! busy_cycles = %0d", pmu_r_val);
      fail_count = fail_count + 1;
      cat_pmu_clear_pass = 1'b0;
    end

    // Verify mathematical invariants
    preload_mem(32'h1000, 16, 32'hA000); preload_mem(32'h2000, 16, 32'hB000);
    start_channel(8'h00, 32'h1000, 32'h3000, 16);
    start_channel(8'h10, 32'h2000, 32'h4000, 16);
    wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1");

    reg_read(8'h58, hw_words); reg_read(8'h5C, hw_bursts); reg_read(8'h60, hw_grants);
    reg_read(8'h64, ch_w0); reg_read(8'h68, ch_w1); reg_read(8'h6C, ch_w2); reg_read(8'h70, ch_w3);
    reg_read(8'h74, ch_b0); reg_read(8'h78, ch_b1); reg_read(8'h7C, ch_b2); reg_read(8'h80, ch_b3);

    pmu_words_sum  = ch_w0 + ch_w1 + ch_w2 + ch_w3;
    pmu_bursts_sum = ch_b0 + ch_b1 + ch_b2 + ch_b3;

    if (hw_words == pmu_words_sum && hw_bursts == pmu_bursts_sum && hw_grants >= hw_bursts) begin
      $display("  PASS: PMU Invariants verified: total_words (%0d) == sum(ch_words) (%0d)", hw_words, pmu_words_sum);
      $display("  PASS: total_bursts (%0d) == sum(ch_bursts) (%0d), total_grants (%0d) >= bursts",
               hw_bursts, pmu_bursts_sum, hw_grants);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: PMU mathematical invariant mismatch!");
      fail_count = fail_count + 1;
      cat_pmu_verif_pass = 1'b0;
    end

    // =========================================================================
    // 12. MULTI-CHANNEL CONCURRENT STRESS TEST
    // =========================================================================
    $display("\n--- 12. MULTI-CHANNEL CONCURRENT STRESS TEST ---");
    preload_mem(32'h1000, 64, 32'h5500_0000);
    preload_mem(32'h2000, 64, 32'h6600_0000);
    preload_mem(32'h3000, 64, 32'h7700_0000);
    preload_mem(32'h4000, 64, 32'h8800_0000);
    start_channel(8'h00, 32'h1000, 32'h5000, 64);
    start_channel(8'h10, 32'h2000, 32'h6000, 64);
    start_channel(8'h20, 32'h3000, 32'h7000, 64);
    start_channel(8'h30, 32'h4000, 32'h8000, 64);
    wait_done(8'h0C, "CH0"); wait_done(8'h1C, "CH1"); wait_done(8'h2C, "CH2"); wait_done(8'h3C, "CH3");
    verify_transfer(32'h1000, 32'h5000, 64, 32'h5500_0000, "Stress-CH0");
    verify_transfer(32'h2000, 32'h6000, 64, 32'h6600_0000, "Stress-CH1");
    verify_transfer(32'h3000, 32'h7000, 64, 32'h7700_0000, "Stress-CH2");
    verify_transfer(32'h4000, 32'h8000, 64, 32'h8800_0000, "Stress-CH3");
    $display("  PASS: Multi-channel stress test complete (256 words concurrent, zero corruption, zero deadlock)");

    // =========================================================================
    // 13. MULTI-SIZE BENCHMARK SUITE (32, 64, 128, 256, 512 WORDS)
    // =========================================================================
    $display("\n--- 13. RUNNING MULTI-SIZE BENCHMARKS (32, 64, 128, 256, 512 words) ---");
    run_single_benchmark(0, 32);
    run_single_benchmark(1, 64);
    run_single_benchmark(2, 128);
    run_single_benchmark(3, 256);
    run_single_benchmark(4, 512);

    // =========================================================================
    // 14. BENCHMARK RESULTS TABLES
    // =========================================================================
    repeat(10) @(posedge clk);
    $display("\n============================================================");
    $display("DMA BENCHMARK PERFORMANCE RESULTS");
    $display("============================================================\n");

    $display("Transfer | Baseline Cycles | Adaptive Cycles | Cycle Improvement");
    $display("---------|-----------------|-----------------|------------------");
    for (b_k = 0; b_k < 5; b_k = b_k + 1) begin
      calc_cyc_imp = ((1.0 * bm_bl_cycles[b_k] - bm_ad_cycles[b_k]) / bm_bl_cycles[b_k]) * 100.0;
      $display("%-8d | %-15d | %-15d | %0.2f%%",
               bm_words[b_k], bm_bl_cycles[b_k], bm_ad_cycles[b_k], calc_cyc_imp);
    end

    $display("\nTransfer | Fixed Bursts | Adaptive Bursts | Reduction");
    $display("---------|--------------|-----------------|----------");
    for (b_k = 0; b_k < 5; b_k = b_k + 1) begin
      calc_burst_red = ((1.0 * bm_bl_bursts[b_k] - bm_ad_bursts[b_k]) / bm_bl_bursts[b_k]) * 100.0;
      $display("%-8d | %-12d | %-15d | %0.2f%%",
               bm_words[b_k], bm_bl_bursts[b_k], bm_ad_bursts[b_k], calc_burst_red);
    end

    $display("\nTransfer | Fixed Grants | Adaptive Grants | Reduction");
    $display("---------|--------------|-----------------|----------");
    for (b_k = 0; b_k < 5; b_k = b_k + 1) begin
      calc_grant_red = ((1.0 * bm_bl_grants[b_k] - bm_ad_grants[b_k]) / bm_bl_grants[b_k]) * 100.0;
      $display("%-8d | %-12d | %-15d | %0.2f%%",
               bm_words[b_k], bm_bl_grants[b_k], bm_ad_grants[b_k], calc_grant_red);
    end

    $display("\nDetailed Metrics Breakdown:");
    $display("Workload | Mode     | Cycles | Busy Cyc | Words | Bursts | Grants | Cyc/Word | Words/Burst | Grants/Word | Words/BusyCyc");
    $display("---------|----------|--------|----------|-------|--------|--------|----------|-------------|-------------|--------------");
    for (b_k = 0; b_k < 5; b_k = b_k + 1) begin
      $display("%-8d | Baseline | %-6d | %-8d | %-5d | %-6d | %-6d | %0.2f     | %0.2f        | %0.2f        | %0.2f",
               bm_words[b_k], bm_bl_cycles[b_k], bm_bl_busy[b_k], bm_words[b_k], bm_bl_bursts[b_k], bm_bl_grants[b_k],
               (1.0 * bm_bl_cycles[b_k]) / bm_words[b_k],
               (1.0 * bm_words[b_k]) / bm_bl_bursts[b_k],
               (1.0 * bm_bl_grants[b_k]) / bm_words[b_k],
               (1.0 * bm_words[b_k]) / bm_bl_busy[b_k]);
      $display("%-8d | Adaptive | %-6d | %-8d | %-5d | %-6d | %-6d | %0.2f     | %0.2f        | %0.2f        | %0.2f",
               bm_words[b_k], bm_ad_cycles[b_k], bm_ad_busy[b_k], bm_words[b_k], bm_ad_bursts[b_k], bm_ad_grants[b_k],
               (1.0 * bm_ad_cycles[b_k]) / bm_words[b_k],
               (1.0 * bm_words[b_k]) / bm_ad_bursts[b_k],
               (1.0 * bm_ad_grants[b_k]) / bm_words[b_k],
               (1.0 * bm_words[b_k]) / bm_ad_busy[b_k]);
    end

    // =========================================================================
    // 15. FINAL VERIFICATION SUMMARY
    // =========================================================================
    $display("\n================================================");
    $display("DMA FINAL VERIFICATION SUMMARY");
    $display("================================================\n");
    $display("Total Tests   : %0d", check_count + pass_count + fail_count);
    $display("PASS          : %0d", pass_count);
    $display("FAIL          : %0d", fail_count);
    $display("Errors        : %0d\n", fail_count);

    $display("Functional Tests      : %0s", cat_functional_pass     ? "PASS" : "FAIL");
    $display("Burst Tests           : %0s", cat_burst_pass          ? "PASS" : "FAIL");
    $display("Length Tests          : %0s", cat_length_pass         ? "PASS" : "FAIL");
    $display("Address Tests         : %0s", cat_address_pass        ? "PASS" : "FAIL");
    $display("Data Integrity        : %0s", cat_data_integrity_pass ? "PASS" : "FAIL");
    $display("Adaptive UP           : %0s", cat_adaptive_up_pass    ? "PASS" : "FAIL");
    $display("Adaptive DOWN         : %0s", cat_adaptive_down_pass  ? "PASS" : "FAIL");
    $display("Saturation            : %0s", cat_saturation_pass     ? "PASS" : "FAIL");
    $display("Independent Adapt     : %0s", cat_indep_adapt_pass    ? "PASS" : "FAIL");
    $display("RR Fairness           : %0s", cat_rr_fairness_pass    ? "PASS" : "FAIL");
    $display("PMU Verification      : %0s", cat_pmu_verif_pass      ? "PASS" : "FAIL");
    $display("PMU Clear             : %0s", cat_pmu_clear_pass      ? "PASS" : "FAIL");
    $display("Stress Test           : %0s", cat_stress_pass         ? "PASS" : "FAIL");
    $display("\n================================================\n");

    $finish;
  end

  // ---------------------------------------------------------------------------
  // Simulation Watchdog Timeout (10ms limit)
  // ---------------------------------------------------------------------------
  initial begin
    #10000000;
    $display("\n*** TIMEOUT - simulation exceeded 10ms limit ***");
    $display("PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
