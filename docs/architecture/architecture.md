# DMA Controller Architecture

## Top-Level Block Diagram

```mermaid
graph TB
    subgraph HOST["Host / Configuration Interface"]
        CFG["cfg_addr[7:0], cfg_wdata[31:0]<br/>cfg_write_en, cfg_read_en<br/>cfg_rdata[31:0], cfg_ready"]
    end

    subgraph TOP["dma_final — Top Module"]
        REG["Register File<br/>& Control Logic"]

        subgraph CHANNELS["DMA Channel Array"]
            CH0["dma_channel_final #0<br/>FSM + Datapath + Adaptive"]
            CH1["dma_channel_final #1<br/>FSM + Datapath + Adaptive"]
            CH2["dma_channel_final #2<br/>FSM + Datapath + Adaptive"]
            CH3["dma_channel_final #3<br/>FSM + Datapath + Adaptive"]
        end

        ARB["dma_arbiter_final<br/>4-Channel Round-Robin<br/>with Burst Lock"]
        MUX["Memory Interface<br/>Multiplexer"]
        PMU["Performance<br/>Monitoring Unit"]
    end

    subgraph MEM["Memory Interface"]
        BUS["mem_addr[31:0], mem_wdata[31:0]<br/>mem_rdata[31:0]<br/>mem_read_en, mem_write_en<br/>mem_valid, mem_ready"]
    end

    CFG --> REG
    REG --> CH0
    REG --> CH1
    REG --> CH2
    REG --> CH3

    CH0 -- "req/grant" --> ARB
    CH1 -- "req/grant" --> ARB
    CH2 -- "req/grant" --> ARB
    CH3 -- "req/grant" --> ARB

    CH0 -- "burst_active" --> ARB
    CH1 -- "burst_active" --> ARB
    CH2 -- "burst_active" --> ARB
    CH3 -- "burst_active" --> ARB

    ARB -- "sel_ch" --> MUX
    CH0 -- "mem signals" --> MUX
    CH1 -- "mem signals" --> MUX
    CH2 -- "mem signals" --> MUX
    CH3 -- "mem signals" --> MUX

    MUX --> BUS

    CH0 -- "burst_done, words" --> PMU
    CH1 -- "burst_done, words" --> PMU
    CH2 -- "burst_done, words" --> PMU
    CH3 -- "burst_done, words" --> PMU
    ARB -- "grants" --> PMU
    MUX -- "bus_busy" --> PMU

    PMU --> REG
```

## Channel FSM State Diagram

```mermaid
stateDiagram-v2
    [*] --> IDLE
    
    IDLE --> BURST_REQ : start_bit && length > 0
    
    BURST_REQ --> READ_WAIT : grant
    
    READ_WAIT --> WRITE_WAIT : mem_ready
    
    WRITE_WAIT --> DONE_STATE : mem_ready && rem_len == 1
    WRITE_WAIT --> BURST_REQ : mem_ready && burst_cnt == burst_len-1
    WRITE_WAIT --> READ_WAIT : mem_ready && (more words in burst)
    
    DONE_STATE --> IDLE : (1 cycle)
    
    note right of IDLE
        Load src/dst/length from registers
        Apply burst_size_reg if update pending
        Reset efficiency_score to 7
    end note

    note right of WRITE_WAIT
        Address increment: +4 bytes/word
        Adaptive logic evaluates at burst boundaries
        Efficiency score updated per completion
    end note
```

## Adaptive Burst Controller Detail

```mermaid
graph TB
    subgraph ADAPTIVE["Adaptive Burst Controller (per channel)"]
        SCORE["Efficiency Score<br/>[3:0], init = 7"]
        LEVEL["Burst Level<br/>[1:0], init = 01"]
        EVAL["Boundary<br/>Evaluation"]
        DECODE["Level Decoder<br/>00→1, 01→4<br/>10→8, 11→16"]
    end

    FULL["Full burst<br/>completed?"] --> |Yes| INCR["score += 1"]
    FULL --> |No: partial| DECR["score -= 2"]
    
    INCR --> CHECK_UP{"score >= 12?"}
    CHECK_UP --> |Yes| UP["level += 1<br/>score = 7<br/>(saturate at 3)"]
    CHECK_UP --> |No| HOLD1["Hold level"]

    DECR --> CHECK_DN{"score <= 3?"}
    CHECK_DN --> |Yes| DN["level -= 1<br/>score = 7<br/>(saturate at 0)"]
    CHECK_DN --> |No| HOLD2["Hold level"]

    EVAL --> FULL
    LEVEL --> DECODE
```

## Arbiter Architecture

```mermaid
graph LR
    subgraph INPUTS
        R0["req[0]"]
        R1["req[1]"]
        R2["req[2]"]
        R3["req[3]"]
    end

    subgraph ARBITER["Round-Robin Arbiter"]
        LG["last_grant[1:0]"]
        BUSY["bus_busy<br/>(OR of burst_active)"]
        LOGIC["Priority Scanner<br/>(starts after last_grant)"]
    end

    subgraph OUTPUTS
        G0["grant[0]"]
        G1["grant[1]"]
        G2["grant[2]"]
        G3["grant[3]"]
    end

    R0 --> LOGIC
    R1 --> LOGIC
    R2 --> LOGIC
    R3 --> LOGIC
    LG --> LOGIC
    BUSY --> |"!bus_busy"| LOGIC
    LOGIC --> G0
    LOGIC --> G1
    LOGIC --> G2
    LOGIC --> G3
```

## Memory Interface Timing

```
         ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐
  clk    │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │
       ──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──

         ┌─────────┐                 ┌─────────┐
  req    │         │                 │         │
       ──┘         └─────────────────┘         └───────────

               ┌────┐                     ┌────┐
  grant        │    │                     │    │
       ────────┘    └─────────────────────┘    └───────────

                    ┌─────────┐                ┌──────────
  mem_valid         │  READ   │  ┌─WRITE──┐    │  READ
       ─────────────┘         └──┘        └────┘

                         ┌────┐       ┌────┐        ┌────
  mem_ready              │    │       │    │        │
       ──────────────────┘    └───────┘    └────────┘

  Phase:  IDLE | BURST_REQ | READ_WAIT | WRITE_WAIT | READ_WAIT ...
```

## Data Flow per Word Transfer

```
  Source Memory              DMA Channel              Destination Memory
  ┌──────────┐            ┌──────────────┐            ┌──────────┐
  │          │  READ      │              │  WRITE     │          │
  │ mem[src] │──────────→ │ read_data_buf│──────────→ │ mem[dst] │
  │          │  mem_ready │              │  mem_ready  │          │
  └──────────┘            │ src += 4     │            └──────────┘
                          │ dst += 4     │
                          │ rem_len -= 1 │
                          │ burst_cnt += 1│
                          └──────────────┘
```
