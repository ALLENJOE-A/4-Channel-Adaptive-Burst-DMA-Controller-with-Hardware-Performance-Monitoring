# DMA Benchmark Results

> Extracted from simulation output on 2026-09-19
> All values measured by hardware PMU counters
> Baseline: Fixed burst = 4 words, Adaptation disabled
> Adaptive: Initial burst = 4 words, Dynamic sizing enabled

## Cycle Count Comparison

| Transfer (words) | Baseline Cycles | Adaptive Cycles | Cycle Improvement |
|----------------:|----------------:|----------------:|------------------:|
| 32              | 160             | 160             | 0.00%             |
| 64              | 303             | 303             | 0.00%             |
| 128             | 589             | 576             | 2.21%             |
| 256             | 1161            | 1122            | 3.36%             |
| 512             | 2318            | 2188            | 5.61%             |

## Burst Count Comparison

| Transfer (words) | Fixed Bursts | Adaptive Bursts | Burst Reduction |
|----------------:|-------------:|----------------:|----------------:|
| 32              | 8            | 8               | 0.00%           |
| 64              | 16           | 16              | 0.00%           |
| 128             | 32           | 28              | 12.50%          |
| 256             | 64           | 44              | 31.25%          |
| 512             | 128          | 64              | 50.00%          |

## Grant Count Comparison

| Transfer (words) | Fixed Grants | Adaptive Grants | Grant Reduction |
|----------------:|-------------:|----------------:|----------------:|
| 32              | 8            | 8               | 0.00%           |
| 64              | 16           | 16              | 0.00%           |
| 128             | 32           | 28              | 12.50%          |
| 256             | 64           | 44              | 31.25%          |
| 512             | 128          | 64              | 50.00%          |

## Detailed Metrics

| Transfer | Mode     | Cycles | Busy Cyc | Words | Bursts | Grants | Cyc/Word | Words/Burst | Grants/Word | Words/BusyCyc |
|---------:|----------|-------:|---------:|------:|-------:|-------:|---------:|------------:|------------:|--------------:|
| 32       | Baseline | 160    | 128      | 32    | 8      | 8      | 5.00     | 4.00        | 0.25        | 0.25          |
| 32       | Adaptive | 160    | 128      | 32    | 8      | 8      | 5.00     | 4.00        | 0.25        | 0.25          |
| 64       | Baseline | 303    | 256      | 64    | 16     | 16     | 4.73     | 4.00        | 0.25        | 0.25          |
| 64       | Adaptive | 303    | 256      | 64    | 16     | 16     | 4.73     | 4.00        | 0.25        | 0.25          |
| 128      | Baseline | 589    | 512      | 128   | 32     | 32     | 4.60     | 4.00        | 0.25        | 0.25          |
| 128      | Adaptive | 576    | 512      | 128   | 28     | 28     | 4.50     | 4.57        | 0.22        | 0.25          |
| 256      | Baseline | 1161   | 1024     | 256   | 64     | 64     | 4.54     | 4.00        | 0.25        | 0.25          |
| 256      | Adaptive | 1122   | 1024     | 256   | 44     | 44     | 4.38     | 5.82        | 0.17        | 0.25          |
| 512      | Baseline | 2318   | 2048     | 512   | 128    | 128    | 4.53     | 4.00        | 0.25        | 0.25          |
| 512      | Adaptive | 2188   | 2048     | 512   | 64     | 64     | 4.27     | 8.00        | 0.13        | 0.25          |

## Key Observations

1. **Small transfers (32-64 words)**: No improvement - burst size adaptation requires
   multiple burst boundaries to detect utilization patterns and begin upgrading.
2. **Medium transfers (128 words)**: Adaptive mode begins showing benefit with 2.21%
   cycle reduction and 12.50% burst/grant reduction as burst size starts upgrading.
3. **Large transfers (256-512 words)**: Significant improvement - up to 5.61% cycle
   reduction and 50% burst reduction at 512 words as burst level reaches maximum (16 words).
4. **Words/Burst ratio**: Increases from 4.00 (fixed) to 8.00 (adaptive) at 512 words,
   confirming successful burst size adaptation from 4 to 16 words.
5. **Bus efficiency**: Busy cycles remain identical between modes (same total data moved),
   confirming that improvement comes from reduced arbitration overhead.
