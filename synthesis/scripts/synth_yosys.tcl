# =============================================================================
# Yosys Open-Source Synthesis Script for DMA Controller
# Targets: Generic Technology Library Synthesis & Gate Count Analysis
# =============================================================================

# Read Verilog source
read_verilog -sv rtl/dma_final.v

# Set top module
hierarchy -check -top dma_final

# High-level synthesis & optimization
proc
opt
fsm
opt
brief

# Technology mapping (generic gates)
techmap
opt

# Map flip-flops
dfflibmap -liberty docs/design_notes/sample_lib.lib 2>/dev/null || dff2ops

# Map combinational logic
abc -g AND,OR,XOR,MUX

# Output netlist
write_verilog synthesis/reports/dma_synth_netlist.v

# Print area and cell reports
stat
