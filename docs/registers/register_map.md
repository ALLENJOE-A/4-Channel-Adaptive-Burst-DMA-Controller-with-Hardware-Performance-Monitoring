# DMA Controller Register Map

> Extracted from `rtl/dma_final.v` — all addresses and fields derived directly from RTL.

## Register Address Space

The DMA controller uses an 8-bit address space (`cfg_addr[7:0]`) with 32-bit data words.
Registers are accessed via the host configuration interface using `cfg_write_en` / `cfg_read_en`
with a `cfg_ready` handshake.

## Channel Configuration Registers

Each channel occupies a 16-byte (4-register) block for source, destination, length, and control.

### Channel 0 (Base: 0x00)

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x00    | CH0_SRC_ADDR    | R/W    | Channel 0 source address                 | 0x00000000  |
| 0x04    | CH0_DST_ADDR    | R/W    | Channel 0 destination address            | 0x00000000  |
| 0x08    | CH0_LENGTH      | R/W    | Channel 0 transfer length (words)        | 0x00000000  |
| 0x0C    | CH0_CONTROL     | R/W    | Channel 0 control / status               | 0x00000000  |

**CH0_CONTROL (0x0C) — Write:**

| Bit | Field    | Description                        |
|-----|----------|------------------------------------|
| 0   | START    | Write 1 to start transfer (self-clearing pulse) |
| 31:1| Reserved | Ignored on write                   |

**CH0_CONTROL (0x0C) — Read:**

| Bit | Field    | Description                        |
|-----|----------|------------------------------------|
| 0   | Reserved | Reads 0                            |
| 1   | BUSY     | 1 = channel transfer in progress   |
| 2   | DONE     | 1 = channel transfer complete      |
| 31:3| Reserved | Reads 0                            |

### Channel 1 (Base: 0x10)

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x10    | CH1_SRC_ADDR    | R/W    | Channel 1 source address                 | 0x00000000  |
| 0x14    | CH1_DST_ADDR    | R/W    | Channel 1 destination address            | 0x00000000  |
| 0x18    | CH1_LENGTH      | R/W    | Channel 1 transfer length (words)        | 0x00000000  |
| 0x1C    | CH1_CONTROL     | R/W    | Channel 1 control / status               | 0x00000000  |

### Channel 2 (Base: 0x20)

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x20    | CH2_SRC_ADDR    | R/W    | Channel 2 source address                 | 0x00000000  |
| 0x24    | CH2_DST_ADDR    | R/W    | Channel 2 destination address            | 0x00000000  |
| 0x28    | CH2_LENGTH      | R/W    | Channel 2 transfer length (words)        | 0x00000000  |
| 0x2C    | CH2_CONTROL     | R/W    | Channel 2 control / status               | 0x00000000  |

### Channel 3 (Base: 0x30)

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x30    | CH3_SRC_ADDR    | R/W    | Channel 3 source address                 | 0x00000000  |
| 0x34    | CH3_DST_ADDR    | R/W    | Channel 3 destination address            | 0x00000000  |
| 0x38    | CH3_LENGTH      | R/W    | Channel 3 transfer length (words)        | 0x00000000  |
| 0x3C    | CH3_CONTROL     | R/W    | Channel 3 control / status               | 0x00000000  |

## Burst Size Configuration Registers

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x40    | CH0_BURST_SIZE  | R/W    | Channel 0 burst size configuration       | 0x00000001  |
| 0x44    | CH1_BURST_SIZE  | R/W    | Channel 1 burst size configuration       | 0x00000001  |
| 0x48    | CH2_BURST_SIZE  | R/W    | Channel 2 burst size configuration       | 0x00000001  |
| 0x4C    | CH3_BURST_SIZE  | R/W    | Channel 3 burst size configuration       | 0x00000001  |

**Burst Size Encoding (bits [1:0]):**

| Value | Burst Size (words) |
|-------|-------------------|
| 2'b00 | 1                 |
| 2'b01 | 4 (default)       |
| 2'b10 | 8                 |
| 2'b11 | 16                |

Writing to a burst size register sets a `burst_size_update` flag. The new burst size is applied
when the channel next enters IDLE and a `start_bit` is asserted.

## PMU (Performance Monitoring Unit) Counters — Read Only

### Global Counters

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x50    | TOTAL_CYCLES    | R      | Total clock cycles since last PMU clear  | 0x00000000  |
| 0x54    | BUSY_CYCLES     | R      | Cycles where at least one channel is active on the bus | 0x00000000  |
| 0x58    | TOTAL_WORDS     | R      | Total words transferred (all channels)   | 0x00000000  |
| 0x5C    | TOTAL_BURSTS    | R      | Total bursts completed (all channels)    | 0x00000000  |
| 0x60    | TOTAL_GRANTS    | R      | Total arbiter grants issued              | 0x00000000  |

### Per-Channel Word Counters

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x64    | CH0_WORDS       | R      | Words transferred by Channel 0           | 0x00000000  |
| 0x68    | CH1_WORDS       | R      | Words transferred by Channel 1           | 0x00000000  |
| 0x6C    | CH2_WORDS       | R      | Words transferred by Channel 2           | 0x00000000  |
| 0x70    | CH3_WORDS       | R      | Words transferred by Channel 3           | 0x00000000  |

### Per-Channel Burst Counters

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x74    | CH0_BURSTS      | R      | Bursts completed by Channel 0            | 0x00000000  |
| 0x78    | CH1_BURSTS      | R      | Bursts completed by Channel 1            | 0x00000000  |
| 0x7C    | CH2_BURSTS      | R      | Bursts completed by Channel 2            | 0x00000000  |
| 0x80    | CH3_BURSTS      | R      | Bursts completed by Channel 3            | 0x00000000  |

### Per-Channel Current Burst Size (Decoded)

| Address | Register             | Access | Description                          | Reset Value |
|---------|---------------------|--------|--------------------------------------|-------------|
| 0x84    | CH0_CURRENT_BURST   | R      | CH0 current burst size (1/4/8/16)    | 4           |
| 0x88    | CH1_CURRENT_BURST   | R      | CH1 current burst size (1/4/8/16)    | 4           |
| 0x8C    | CH2_CURRENT_BURST   | R      | CH2 current burst size (1/4/8/16)    | 4           |
| 0x90    | CH3_CURRENT_BURST   | R      | CH3 current burst size (1/4/8/16)    | 4           |

These registers return the decoded burst size in words (not the 2-bit level encoding).

## PMU Control Registers

| Address | Register         | Access | Description                              | Reset Value |
|---------|-----------------|--------|------------------------------------------|-------------|
| 0x94    | PMU_CLEAR       | W      | Write 1 to bit[0] to clear all PMU counters | N/A      |
| 0x98    | ADAPTIVE_MODE   | R/W    | Adaptive burst control                   | 0x00000001  |

**PMU_CLEAR (0x94) — Write:**

| Bit | Field    | Description                                    |
|-----|----------|------------------------------------------------|
| 0   | CLEAR    | Write 1 to reset all PMU counters to zero      |
| 31:1| Reserved | Ignored                                        |

Writing 1 to bit[0] clears: `total_cycles`, `busy_cycles`, `total_words`, `total_bursts`,
`total_grants`, and all per-channel `ch*_words` / `ch*_bursts` counters in a single cycle.

**ADAPTIVE_MODE (0x98):**

| Bit | Field       | Description                                    |
|-----|-------------|------------------------------------------------|
| 0   | ADAPTIVE_EN | 1 = Adaptive burst mode (default); 0 = Fixed burst baseline mode |
| 31:1| Reserved    | Reads 0                                        |

When `ADAPTIVE_EN = 0`, all channels hold their burst level to the configured `burst_size_reg`
value and the efficiency score is held at the neutral value (7). This enables isolated baseline
benchmarking.

## Default Read for Unmapped Addresses

Reading any address not listed above returns `0xDEADBEEF`.

## Register Map Summary

```
0x00-0x0C : Channel 0 Config (src, dst, length, control/status)
0x10-0x1C : Channel 1 Config
0x20-0x2C : Channel 2 Config
0x30-0x3C : Channel 3 Config
0x40-0x4C : Burst Size Config (CH0-CH3)
0x50-0x60 : PMU Global Counters (cycles, busy, words, bursts, grants)
0x64-0x70 : PMU Per-Channel Word Counters
0x74-0x80 : PMU Per-Channel Burst Counters
0x84-0x90 : PMU Per-Channel Current Burst Size (decoded)
0x94      : PMU Clear (write-only)
0x98      : Adaptive Mode Control
```
