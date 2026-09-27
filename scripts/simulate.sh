#!/usr/bin/env bash
set -euo pipefail
if (( $# )); then
    printf 'Usage: bash scripts/simulate.sh\n'
    [[ $# == 1 && $1 == --help ]] && exit 0
    exit 2
fi
source "$(dirname -- "${BASH_SOURCE[0]}")/runner_common.sh"
reuse_setup_vivado
reuse_new_run simulation
printf 'Running core and board-control simulation; log: %s/simulation.log\n' "$reuse_run"
timeout --signal=TERM --kill-after=10s 1200s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log simulation.log -journal simulation.jou \
    -source "$reuse_repo/scripts/run_sim.tcl" \
    -tclargs "$reuse_repo" "$reuse_run/sim" > console.log 2>&1
grep -Fxq TEMPORAL_REUSE_ALL_TESTS_PASSED "$reuse_run/sim/simulation_pass.txt"
grep -Fxq BOARD_CONTROL_SIMULATION_PASS "$reuse_run/sim/simulation_pass.txt"
printf 'SIMULATE_PASS\nWaveforms and detailed logs: %s/sim\n' "$reuse_run"
