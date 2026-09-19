@echo off
REM =============================================================================
REM DMA Controller - ModelSim Simulation Script (Windows)
REM =============================================================================
REM Usage: scripts\run_sim_modelsim.bat
REM        (run from repository root)
REM
REM Prerequisites:
REM   - ModelSim/QuestaSim bin directory must be in PATH
REM   - Run from the repository root directory
REM =============================================================================

echo ============================================
echo  DMA Controller - ModelSim Simulation
echo ============================================

REM Create work library
echo [1/3] Creating work library...
if exist simulation\work rmdir /s /q simulation\work
vlib simulation\work

REM Compile
echo [2/3] Compiling RTL and testbench...
vlog -work simulation\work rtl\dma_final.v tb\tb_dma_final.v > simulation\logs\compile.log 2>&1
type simulation\logs\compile.log

REM Simulate
echo [3/3] Running simulation...
vsim -batch -do "run -all; quit -f" -lib simulation\work tb_dma_final > simulation\logs\simulation.log 2>&1
type simulation\logs\simulation.log

echo.
echo ============================================
echo  Simulation complete.
echo  Logs saved to: simulation\logs\
echo ============================================
