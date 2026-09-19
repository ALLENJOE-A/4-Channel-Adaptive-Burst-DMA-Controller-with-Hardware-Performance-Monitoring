# Synthesis Flow & Implementation Readiness

> Status: Tool scripts prepared for Yosys, Quartus Prime, and Xilinx Vivado.
> Synthesis execution result: Not yet generated (synthesis tool license / device library unavailable in local execution environment).

## Synthesis Flow Overview

The repository includes reproducible synthesis scripts and timing constraint files for major EDA synthesis tools:

1. **Yosys Open-Source ASIC/FPGA Synthesis** (`synthesis/scripts/synth_yosys.tcl`)
2. **Intel Quartus Prime FPGA Flow** (`synthesis/scripts/synth_quartus.tcl`)
3. **Xilinx Vivado Non-Project Flow** (`synthesis/scripts/synth_vivado.tcl`)
4. **Timing Constraints File (SDC)** (`synthesis/constraints/constraints.sdc`)

## Clock Constraints

- **Target Clock**: `clk` at 100 MHz (10.0 ns period)
- **Input Delay**: 2.0 ns max, 0.5 ns min
- **Output Delay**: 2.0 ns max, 0.5 ns min

## Synthesis Results Policy

Per project verification guidelines:
- Synthesis results (area, cell count, maximum operating frequency, power) are **not fabricated**.
- Since physical device libraries were unavailable during local environment run, metrics are marked as **Not yet generated**.
- Run `synthesis/scripts/` in your local EDA environment to generate full synthesis reports.
