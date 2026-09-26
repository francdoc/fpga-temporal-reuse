#!/usr/bin/env bash
# Whole implemented PL estimate; no hardware connection or board source edits.
set -euo pipefail
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# != 1 ]]; then printf 'Usage: bash run_board_power.sh ROUTED_BOARD_DCP\n' >&2; exit 1; fi
checkpoint=$(realpath "$1")
vivado_root=${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}
batches=${REUSE_BOARD_POWER_BATCHES:-256}
if [[ ! $batches =~ ^[1-9][0-9]*$ ]] || ((batches > 16777215)); then printf 'Invalid REUSE_BOARD_POWER_BATCHES\n' >&2; exit 1; fi
output_parent=$(realpath "${REUSE_POWER_PARENT:-${TMPDIR:-/tmp}}")
case "$output_parent/" in "$source_root/"*) printf 'Output must be outside source tree\n' >&2; exit 1 ;; esac
run_root=$(mktemp -d "$output_parent/fpga-temporal-board-power.XXXXXX")
exec > >(tee "$run_root/runner.log") 2>&1
printf 'BOARD_POWER_RUN_DIR=%s\n' "$run_root"
trap 'status=$?; if ((status)); then printf "BOARD_POWER_RUN_FAILED status=%s artifacts=%s\n" "$status" "$run_root" >&2; fi' EXIT
set +u
source "$vivado_root/settings64.sh"
set -u
export REUSE_BOARD_POWER_WINDOW_NS=$((batches * 140))
export REUSE_BOARD_POWER_EXPORT_DIR="$run_root/export"
cd "$run_root"
rg -n 'force ' "$source_root/tb/tb_power_board.v" > forces_manifest.txt
sha256sum "$checkpoint" "$source_root/tb/tb_power_board.v" "$source_root/scripts/power_board_export.tcl" "$source_root/scripts/power_board_trace.tcl" "$source_root/scripts/power_board_report.tcl" "$source_root/scripts/power_board_summary.py" "$source_root/scripts/run_board_power.sh" > source_identity.sha256
timeout --signal=TERM --kill-after=10s 300s vivado -mode batch -source "$source_root/scripts/power_board_export.tcl" -tclargs "$checkpoint" "$run_root/export" > export.log 2>&1
rg -q BOARD_POWER_EXPORT_PASS export.log
timeout --signal=TERM --kill-after=10s 180s xvlog -i "$run_root/export" "$run_root/export/board_funcsim.v" "$source_root/tb/tb_power_board.v" "$vivado_root/data/verilog/src/glbl.v" > compile.log 2>&1
timeout --signal=TERM --kill-after=10s 300s xelab tb_power_board glbl -L unisims_ver -debug all -s board_power_sim > elaborate.log 2>&1
for mode in 0 1; do
    case_dir="$run_root/mode${mode}"
    mkdir "$case_dir"
    ln -s "$run_root/xsim.dir" "$case_dir/xsim.dir"
    cd "$case_dir"
    timeout --signal=TERM --kill-after=10s 300s xsim board_power_sim -testplusarg "power_mode=$mode" -testplusarg "power_batches=$batches" -tclbatch "$source_root/scripts/power_board_trace.tcl" > simulate.log 2>&1
    rg -q BOARD_POWER_SIMULATION_PASS simulate.log
    rg -q BOARD_POWER_SAIF_PASS simulate.log
    timeout --signal=TERM --kill-after=10s 300s vivado -mode batch -source "$source_root/scripts/power_board_report.tcl" -tclargs "$checkpoint" "$case_dir/activity.saif" "$case_dir" > report.log 2>&1
    rg -q BOARD_POWER_REPORT_PASS report.log
    printf 'BOARD_POWER_CASE_PASS mode=%s directory=%s\n' "$mode" "$case_dir"
done
python3 -B "$source_root/scripts/power_board_summary.py" "$run_root"
printf 'BOARD_POWER_RUN_PASS %s\n' "$run_root"
