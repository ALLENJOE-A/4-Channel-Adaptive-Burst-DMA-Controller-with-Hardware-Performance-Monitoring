# =============================================================================
# Xilinx Vivado Non-Project Batch Synthesis Script
# Target Family: Artix-7 (xc7a100tcsg324-1)
# =============================================================================

# Define output directory
set output_dir "synthesis/reports"
file mkdir $output_dir

# Read RTL design files
read_verilog -sv rtl/dma_final.v

# Read SDC constraints
read_xdc synthesis/constraints/constraints.sdc 2>/dev/null || true

# Run synthesis
synth_design -top dma_final -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt

# Write utilization & timing reports
report_utilization -file "$output_dir/utilization_report.txt"
report_timing_summary -file "$output_dir/timing_report.txt"
report_power -file "$output_dir/power_report.txt"

# Write gate-level netlist
write_verilog -force "$output_dir/dma_netlist.v"
