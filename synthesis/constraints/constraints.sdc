# =============================================================================
# Synopsys Design Constraints (SDC) for DMA Controller
# Target Clock: 100 MHz (10.0 ns period)
# =============================================================================

# Create main clock constraint (100 MHz)
create_clock -name clk -period 10.000 [get_ports {clk}]

# Derive clock uncertainty
derive_clock_uncertainty

# Input delay constraints (2.0 ns assumption for external signals)
set_input_delay -clock clk -max 2.000 [get_ports {rst_n cfg_addr* cfg_wdata* cfg_write_en cfg_read_en mem_rdata* mem_ready}]
set_input_delay -clock clk -min 0.500 [get_ports {rst_n cfg_addr* cfg_wdata* cfg_write_en cfg_read_en mem_rdata* mem_ready}]

# Output delay constraints (2.0 ns assumption for output driving)
set_output_delay -clock clk -max 2.000 [get_ports {cfg_rdata* cfg_ready mem_addr* mem_wdata* mem_write_en mem_read_en mem_valid burst_done current_burst_level*}]
set_output_delay -clock clk -min 0.500 [get_ports {cfg_rdata* cfg_ready mem_addr* mem_wdata* mem_write_en mem_read_en mem_valid burst_done current_burst_level*}]
