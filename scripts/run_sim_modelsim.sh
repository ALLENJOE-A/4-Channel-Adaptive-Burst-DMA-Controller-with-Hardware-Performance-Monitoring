#!/bin/bash
# =============================================================================
# DMA Controller - ModelSim Simulation Script
# =============================================================================
# Usage: source scripts/run_sim_modelsim.sh
#        (or run from repository root)
#
# Prerequisites:
#   - ModelSim/QuestaSim must be in PATH
#   - Run from the repository root directory
# =============================================================================

set -e

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="${PROJ_ROOT}/simulation"
WORK_DIR="${SIM_DIR}/work"

echo "============================================"
echo " DMA Controller - ModelSim Simulation"
echo "============================================"

# Create work library
echo "[1/3] Creating work library..."
rm -rf "${WORK_DIR}"
vlib "${WORK_DIR}"

# Compile
echo "[2/3] Compiling RTL and testbench..."
vlog -work "${WORK_DIR}" \
  "${PROJ_ROOT}/rtl/dma_final.v" \
  "${PROJ_ROOT}/tb/tb_dma_final.v" \
  2>&1 | tee "${SIM_DIR}/logs/compile.log"

# Simulate
echo "[3/3] Running simulation..."
vsim -batch -do "run -all; quit -f" \
  -lib "${WORK_DIR}" tb_dma_final \
  2>&1 | tee "${SIM_DIR}/logs/simulation.log"

echo ""
echo "============================================"
echo " Simulation complete."
echo " Logs saved to: simulation/logs/"
echo "============================================"
