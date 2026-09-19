# =============================================================================
# Quartus Prime Synthesis & Timing Analysis Script
# Target Family: Cyclone IV E (EP4CE115F29C7)
# Top Module: dma_final
# =============================================================================

package require ::quartus::project
package require ::quartus::flow

set project_name "dma_synth"
set top_module   "dma_final"

# Create project
if {[project_exists $project_name]} {
    project_open $project_name -force
} else {
    project_new $project_name -overwrite
}

# Set target device
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE115F29C7
set_global_assignment -name TOP_LEVEL_ENTITY $top_module

# Add source files
set_global_assignment -name VERILOG_FILE "rtl/dma_final.v"
set_global_assignment -name SDC_FILE "synthesis/constraints/constraints.sdc"

# Synthesis Optimization Flags
set_global_assignment -name OPTIMIZATION_MODE "BALANCED"

# Run Synthesis (Analysis & Synthesis)
puts "============================================================"
puts " Starting Analysis & Synthesis..."
puts "============================================================"
execute_module -tool map

# Run Fitter (Place & Route)
puts "============================================================"
puts " Starting Fitter (Place & Route)..."
puts "============================================================"
execute_module -tool fit

# Run TimeQuest Timing Analyzer
puts "============================================================"
puts " Starting Timing Analysis..."
puts "============================================================"
execute_module -tool sta

project_close
puts "============================================================"
puts " Quartus Synthesis Flow Completed Successfully."
puts "============================================================"
