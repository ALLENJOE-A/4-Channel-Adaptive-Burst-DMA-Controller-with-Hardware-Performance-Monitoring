# Adaptive Burst Control Algorithm

> Derived directly from `rtl/dma_final.v`, module `dma_channel_final`, lines 95-216.

## Overview

The adaptive burst controller dynamically adjusts each channel's burst size based on observed
transfer utilization. The algorithm runs independently per channel and modifies burst size only
at safe burst boundaries to prevent data corruption.

## Design Goal

Reduce arbitration overhead for large, aligned transfers by increasing burst size, while
preventing bus monopolization for small or misaligned transfers by decreasing burst size.

## Algorithm Parameters

| Parameter            | Value    | Description                                      |
|---------------------|----------|--------------------------------------------------|
| Initial burst level | 2'b01    | 4 words (configurable via burst_size_reg)        |
| Efficiency score width | 4 bits | Range [0, 15]                                   |
| Neutral score       | 7        | Score after reset or burst level change           |
| Upgrade threshold   | >= 12    | Score must reach 12 to trigger burst upgrade      |
| Downgrade threshold | <= 3     | Score must drop to 3 to trigger burst downgrade   |
| Score increment     | +1       | Added per full burst completion                   |
| Score decrement     | -2       | Subtracted per partial burst (end of transfer with fewer words than burst_len) |
| Burst levels        | 4        | 1, 4, 8, 16 words                                |
| Saturation bounds   | [0, 3]   | Burst level clamped to 2-bit range (level 0=1 word, level 3=16 words) |

## Burst Level Encoding

| Level (2-bit) | Words per Burst |
|:-------------:|:---------------:|
| 2'b00         | 1               |
| 2'b01         | 4               |
| 2'b10         | 8               |
| 2'b11         | 16              |

## Algorithm Flow

```
                    ┌─────────────┐
                    │   RESET     │
                    │ score = 7   │
                    │ level = 01  │
                    └──────┬──────┘
                           │
                           v
              ┌────────────────────────┐
              │  Transfer in progress  │
              │  (WRITE_WAIT state)    │
              │  mem_ready asserted    │
              └────────────┬───────────┘
                           │
                  ┌────────┴────────┐
                  │ adaptive_en=1?  │
                  └───┬─────────┬───┘
                   No │         │ Yes
                      v         v
              ┌──────────┐  ┌──────────────────────┐
              │ Hold      │  │ Is this the last     │
              │ burst_level│  │ word of the entire   │
              │ = cfg_reg │  │ transfer? (rem==1)   │
              │ score = 7 │  └────┬────────────┬────┘
              └──────────┘       │ Yes         │ No
                                 v             v
                    ┌──────────────┐  ┌──────────────────┐
                    │ Was it a     │  │ Is burst_cnt ==  │
                    │ full burst?  │  │ burst_len - 1?   │
                    │ (cnt==len-1) │  │ (end of burst)   │
                    └──┬────────┬──┘  └──┬────────────┬──┘
                   Yes │        │ No  Yes│            │ No
                       v        v       v            (no update)
              ┌──────────┐ ┌──────────┐ ┌──────────┐
              │FULL BURST│ │ PARTIAL  │ │FULL BURST│
              │at end of │ │ BURST    │ │ (inter-  │
              │transfer  │ │          │ │ mediate) │
              └────┬─────┘ └────┬─────┘ └────┬─────┘
                   │            │             │
                   v            v             v
         ┌────────────────┐ ┌──────────┐ ┌────────────────┐
         │ score >= 12?   │ │score<=3? │ │ score >= 12?   │
         └──┬──────────┬──┘ └──┬────┬──┘ └──┬──────────┬──┘
         Yes│          │No  Yes│    │No  Yes│          │No
            v          v       v    v       v          v
     ┌──────────┐ ┌────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐
     │ UPGRADE  │ │score   │ │DOWNGRADE │ │ UPGRADE  │ │score   │
     │ level+=1 │ │+= 1    │ │ level-=1 │ │ level+=1 │ │+= 1    │
     │ score =7 │ │        │ │ score =7 │ │ score =7 │ │        │
     │(sat at 3)│ │        │ │(sat at 0)│ │(sat at 3)│ │        │
     └──────────┘ └────────┘ └──────────┘ └──────────┘ └────────┘
```

## Detailed State Transitions

### Score Update Rules

The efficiency score is a 4-bit counter (range 0-15) initialized to 7 (neutral). It acts as
a hysteresis mechanism to prevent oscillation between burst levels.

**At a full burst completion** (burst_cnt == burst_len - 1):
1. If `score >= 12`: upgrade burst level, reset score to 7
2. Otherwise: `score += 1`

**At a partial burst** (end of transfer with burst_cnt != burst_len - 1):
1. If `score <= 3`: downgrade burst level, reset score to 7
2. Otherwise: `score -= 2`

### Convergence Analysis

- **Upgrade path**: Starting from score=7, requires 5 consecutive full bursts to reach 12
  (7 -> 8 -> 9 -> 10 -> 11 -> 12). At score=12, level is upgraded and score resets to 7.
- **Downgrade path**: Starting from score=7, requires 2 partial bursts to reach 3
  (7 -> 5 -> 3). At score=3, level is downgraded and score resets to 7.
- **Asymmetry**: The asymmetric increment/decrement (+1 / -2) makes downgrade faster than
  upgrade. This is a conservative design choice that prevents burst size from growing too
  aggressively for workloads with mixed transfer sizes.

### Boundary Safety

The burst level is **only** modified at burst boundaries:
- End of a full burst (burst_cnt == burst_len - 1)
- End of the entire transfer (rem_len == 1)

The burst level is **never** modified mid-burst. This is verified by the continuous
boundary rule monitor in the testbench, which checks that `current_burst_level` does not
change while `burst_active` is asserted.

### Fixed Burst Mode

When `adaptive_en = 0` (register 0x98, bit[0] = 0):
- `burst_level` is held to the configured `burst_size_reg` value every cycle
- `efficiency_score` is held at the neutral value (7)
- No adaptation occurs

This mode enables isolated baseline benchmarking for performance comparison.

## Adaptation Example

Consider a 128-word transfer with initial burst size of 4 words:

```
Burst  1-5 (4 words each): score: 7->8->9->10->11->12 → UPGRADE to 8 words, score=7
Burst  6-10 (8 words each): score: 7->8->9->10->11->12 → UPGRADE to 16 words, score=7  
Burst 11-12 (16 words each): score: 7->8
Transfer completes

Result: Adapted from 4 → 8 → 16 words during a single transfer
```

## Verified Behaviors

From simulation results:

| Scenario               | Initial | Final | Result |
|-----------------------|---------|-------|--------|
| 15x 32-word transfers  | 4       | 16    | Adaptive UP verified |
| 15x 2-word transfers   | 4       | 1     | Adaptive DOWN verified |
| CH0 large + CH1 small  | 4 / 4   | 16 / 1| Independent adaptation confirmed |
| All transfers          | N/A     | [1,16]| Saturation bounds respected |
| All transfers          | N/A     | N/A   | 0 mid-burst level changes |
