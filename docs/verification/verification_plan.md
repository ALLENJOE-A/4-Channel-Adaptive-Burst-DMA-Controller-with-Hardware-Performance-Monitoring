# DMA Controller Verification Plan

> Based on testbench `tb/tb_dma_final.v` — all test categories, stimuli, and results
> derived from the actual testbench implementation and simulation output.

## Verification Environment

| Component        | Implementation                                          |
|-----------------|---------------------------------------------------------|
| Language         | Verilog-2001                                            |
| Methodology      | Directed test with independent scoreboard              |
| Simulator        | ModelSim ALTERA 10.5b (verification performed 2026-09-19) |
| DUT              | `dma_final` (top module)                                |
| Memory Model     | 64K x 32-bit synchronous array with 1-cycle ready     |
| Clock            | 100 MHz (10 ns period)                                  |
| Reset            | Asynchronous active-low, 10-cycle assertion            |
| Timeout          | 10 ms simulation watchdog                               |
| VCD Dump         | `dump.vcd` — full hierarchy                             |

## Verification Features

| Feature                    | Present | Description                              |
|---------------------------|---------|------------------------------------------|
| Directed tests             | Yes     | 13 structured test categories            |
| Data scoreboard            | Yes     | `verify_transfer` compares src vs dst    |
| Continuous assertion       | Yes     | Burst boundary rule monitor              |
| Performance benchmarking   | Yes     | 5-point baseline vs adaptive comparison  |
| PMU invariant checks       | Yes     | Mathematical consistency verification    |
| Overrun detection          | Yes     | Sentinel words placed after dst range    |
| Multi-channel concurrency  | Yes     | All channel pairs + all-4 simultaneous   |
| UVM                        | No      | Not implemented                          |
| SystemVerilog assertions   | No      | Pure Verilog-2001 testbench              |
| Functional coverage        | No      | Not implemented                          |
| Constrained random         | No      | Directed stimulus only                   |

## Test Categories

### 1. Single-Channel Transfers (Functional)

| Test         | Stimulus                    | Expected Behavior           | Result |
|-------------|-----------------------------|-----------------------------|--------|
| CH0-Only    | 8 words, src=0x1000, dst=0x2000 | All 8 words transferred correctly | PASS |
| CH1-Only    | 8 words, src=0x1100, dst=0x2100 | All 8 words transferred correctly | PASS |
| CH2-Only    | 8 words, src=0x1200, dst=0x2200 | All 8 words transferred correctly | PASS |
| CH3-Only    | 8 words, src=0x1300, dst=0x2300 | All 8 words transferred correctly | PASS |

### 2. Multi-Channel Concurrent Transfers

| Test              | Channels | Words/Ch | Expected Behavior             | Result |
|------------------|----------|----------|-------------------------------|--------|
| CH0+CH1          | 0, 1     | 16       | Both complete, data correct   | PASS   |
| CH0+CH2          | 0, 2     | 16       | Both complete, data correct   | PASS   |
| CH0+CH3          | 0, 3     | 16       | Both complete, data correct   | PASS   |
| CH1+CH2          | 1, 2     | 16       | Both complete, data correct   | PASS   |
| CH1+CH3          | 1, 3     | 16       | Both complete, data correct   | PASS   |
| CH2+CH3          | 2, 3     | 16       | Both complete, data correct   | PASS   |
| All 4 channels   | 0,1,2,3  | 32       | All complete, data correct    | PASS   |

### 3. Burst Size Verification

| Test             | Burst Level | Words | Expected Behavior             | Result |
|-----------------|-------------|-------|-------------------------------|--------|
| Burst-1          | 0 (1 word)  | 8     | 8 single-word bursts          | PASS   |
| Burst-4          | 1 (4 words) | 16    | 4 four-word bursts            | PASS   |
| Burst-8          | 2 (8 words) | 16    | 2 eight-word bursts           | PASS   |
| Burst-16         | 3 (16 words)| 32    | 2 sixteen-word bursts         | PASS   |
| Mixed (CH0=1,CH1=4,CH2=8,CH3=16) | Mixed | 16 each | All channels correct | PASS |

### 4. Exhaustive Transfer Length Tests

22 transfer lengths tested with overrun detection:

| Lengths Tested | All Passed |
|----------------|-----------|
| 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 255, 256, 512 | PASS (all 22) |

Each test places a sentinel value (`0xDEAD_FACE`) after the destination range and verifies:
1. All transferred words match expected values
2. Sentinel is not overwritten (zero overruns)

### 5. Corner-Case Tests

| Test                    | Condition                   | Expected                    | Result |
|------------------------|-----------------------------|-----------------------------|--------|
| Length = 1              | Smallest possible transfer  | 1 word, no overrun          | PASS   |
| Length < burst (3 < 16) | len < burst_len             | Capped to 3 words, no overrun | PASS |
| Length == burst (16=16)  | Exact burst fit             | 1 full burst, data correct  | PASS   |
| Length == burst+1 (17)   | 1 word past burst boundary  | 16 + 1 words, split burst   | PASS   |

### 6. Address Testing

| Test              | Condition                      | Expected                    | Result |
|------------------|--------------------------------|-----------------------------|--------|
| Offset address    | src=0x1020, dst=0x5080        | Correct transfer, aligned   | PASS   |
| Boundary address  | src=0xFC00 (near 64K)         | Correct transfer            | PASS   |
| Word increment    | Sequential addresses           | +4 bytes per word verified  | PASS   |

### 7. Data Integrity Patterns

| Test                    | Pattern                                  | Result |
|------------------------|------------------------------------------|--------|
| Fixed patterns          | 0x00000000, 0xFFFFFFFF, 0xAAAAAAAA, 0x55555555 | PASS |
| Alternating patterns    | 0x12345678, 0x87654321 (alternating)     | PASS   |

### 8. Adaptive Burst Verification

| Test              | Stimulus                        | Expected                | Actual       | Result |
|------------------|--------------------------------|-------------------------|-------------|--------|
| Adaptive UP       | 15x 32-word transfers          | Burst 4 -> 16 words    | 4 -> 16     | PASS   |
| Adaptive DOWN     | 15x 2-word transfers           | Burst 4 -> 1 word      | 4 -> 1      | PASS   |
| Saturation bounds | After DOWN adaptation          | Level in [1, 16]       | Level = 1   | PASS   |
| Boundary rule     | Continuous monitor             | 0 mid-burst changes    | 0 violations| PASS   |

### 9. Independent Channel Adaptation

| Test              | CH0 Stimulus      | CH1 Stimulus       | Expected             | Result |
|------------------|------------------|--------------------|----------------------|--------|
| Independent adapt | 128 words (large) | 15x 2 words (small)| CH0 UP, CH1 DOWN    | PASS   |

Verified: CH0 adapted UP (4->16), CH1 adapted DOWN (4->1) simultaneously.

### 10. Round-Robin Fairness & Starvation Prevention

| Test              | Stimulus                          | Expected                | Result |
|------------------|----------------------------------|-------------------------|--------|
| 4-channel equal   | 32 words each, simultaneous      | CH0=CH1=CH2=CH3=32     | PASS   |

PMU per-channel word counters confirm exactly 32 words per channel — zero starvation.

### 11. PMU Hardware Counter Audit & Clear

| Test              | Stimulus                          | Expected                | Result |
|------------------|----------------------------------|-------------------------|--------|
| PMU Clear         | Write 1 to 0x94, read 0x54      | busy_cycles = 0         | PASS   |
| Word invariant    | CH0=16 + CH1=16 words           | total_words == ch0+ch1  | PASS   |
| Burst invariant   | After multi-channel transfer     | total_bursts == sum(ch) | PASS   |
| Grant invariant   | After multi-channel transfer     | total_grants >= bursts  | PASS   |

### 12. Multi-Channel Stress Test

| Test              | Stimulus                          | Expected                | Result |
|------------------|----------------------------------|-------------------------|--------|
| 4x64 words       | 256 words total, concurrent      | Zero corruption         | PASS   |
|                   |                                  | Zero deadlock           | PASS   |
|                   |                                  | All data verified       | PASS   |

### 13. Multi-Size Benchmark Suite

5-point benchmark comparing fixed vs adaptive burst mode:

| Transfer (words) | Baseline Cycles | Adaptive Cycles | Improvement |
|----------------:|----------------:|----------------:|------------:|
| 32              | 160             | 160             | 0.00%       |
| 64              | 303             | 303             | 0.00%       |
| 128             | 589             | 576             | 2.21%       |
| 256             | 1161            | 1122            | 3.36%       |
| 512             | 2318            | 2188            | 5.61%       |

## Verification Matrix Summary

| #  | Category                    | Tests | Checks | Result |
|----|-----------------------------|-------|--------|--------|
| 1  | Single-Channel Transfers    | 4     | 32     | PASS   |
| 2  | Multi-Channel Concurrent    | 7     | 256    | PASS   |
| 3  | Burst Size Tests            | 5     | 96     | PASS   |
| 4  | Transfer Length Tests       | 22    | ~2000  | PASS   |
| 5  | Corner-Case Tests           | 4     | 40     | PASS   |
| 6  | Address Tests               | 3     | 41     | PASS   |
| 7  | Data Integrity Patterns     | 2     | 34     | PASS   |
| 8  | Adaptive Burst Verification | 4     | 4      | PASS   |
| 9  | Independent Adaptation      | 1     | 1      | PASS   |
| 10 | Round-Robin Fairness        | 1     | 129    | PASS   |
| 11 | PMU Counter Audit           | 4     | 2      | PASS   |
| 12 | Stress Test                 | 1     | 256    | PASS   |
| 13 | Benchmark Suite             | 5     | ~3300  | PASS   |
|    | **TOTAL**                   | **63**| **6266**| **ALL PASS** |

## Continuous Monitors

| Monitor                  | Scope      | Method                                        | Violations |
|-------------------------|-----------|------------------------------------------------|-----------|
| Burst boundary rule      | All channels | Sample burst_level at burst start, compare mid-burst | 0 |
| Word write counter       | Global     | Increment on mem_valid && mem_ready && mem_write_en | Used for total check count |
| Channel done latch       | Per-channel | Latch done signal; clear on next test start    | N/A       |
| Adaptive burst tracker   | Per-channel | Poll registers 0x84-0x90 between test iterations | Reported transitions |

## Reproducibility

```bash
# Using ModelSim (Linux/Windows)
vlib work
vlog -work work rtl/dma_final.v tb/tb_dma_final.v
vsim -batch -do "run -all; quit -f" -lib work tb_dma_final

# Or use provided scripts:
scripts/run_sim_modelsim.sh     # Linux
scripts/run_sim_modelsim.bat    # Windows
```
