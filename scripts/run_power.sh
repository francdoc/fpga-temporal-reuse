#!/usr/bin/env bash
# Run with bash. REUSE_POWER_PARENT selects an existing durable output parent;
# REUSE_VIVADO_ROOT selects Vivado and REUSE_POWER_BATCHES selects K (default 1024).
# REUSE_POWER_BUILD_DIR optionally reuses a previously generated core checkpoint.
set -euo pipefail
source_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
vivado_root=${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}
batches=${REUSE_POWER_BATCHES:-1024}
if [[ ! $batches =~ ^[1-9][0-9]*$ ]]; then printf 'Invalid REUSE_POWER_BATCHES\n' >&2; exit 1; fi
output_parent=$(realpath "${REUSE_POWER_PARENT:-${TMPDIR:-/tmp}}")
case "$output_parent/" in "$source_root/"*) printf 'Power output must be outside the source tree\n' >&2; exit 1 ;; esac
run_root=$(mktemp -d "$output_parent/fpga-temporal-reuse-power.XXXXXX")
printf 'POWER_RUN_DIR=%s\n' "$run_root"
trap 'status=$?; if ((status)); then printf "POWER_RUN_FAILED status=%s artifacts=%s\n" "$status" "$run_root" >&2; fi' EXIT
set +u
source "$vivado_root/settings64.sh"
set -u
export REUSE_POWER_WINDOW_NS=$((batches * 140))
cd "$run_root"
if [[ -n ${REUSE_POWER_BUILD_DIR:-} ]]; then
    for artifact in routed.dcp core_funcsim.v tb_power_pins.vh mapping.tsv; do
        test -s "$REUSE_POWER_BUILD_DIR/$artifact"
    done
    ln -s "$(realpath "$REUSE_POWER_BUILD_DIR")" "$run_root/build"
else
    mkdir build
    timeout --signal=TERM --kill-after=10s 600s "$vivado_root/bin/vivado" -mode batch -source "$source_root/scripts/power_build.tcl" -tclargs "$source_root" "$run_root/build" > build.log 2>&1
    rg -q POWER_BUILD_PASS build.log
fi
timeout --signal=TERM --kill-after=10s 180s "$vivado_root/bin/xvlog" -i "$run_root/build" "$run_root/build/core_funcsim.v" "$source_root/tb/tb_power_temporal_reuse.v" "$vivado_root/data/verilog/src/glbl.v" > compile.log 2>&1
timeout --signal=TERM --kill-after=10s 180s "$vivado_root/bin/xelab" tb_power_temporal_reuse glbl -L unisims_ver -debug all -s power_sim > elaborate.log 2>&1
for weight in 7 9; do
    for mode in 0 1; do
        case_dir="$run_root/weight${weight}_mode${mode}"
        mkdir "$case_dir"
        ln -s "$run_root/xsim.dir" "$case_dir/xsim.dir"
        cd "$case_dir"
        timeout --signal=TERM --kill-after=10s 180s "$vivado_root/bin/xsim" power_sim -testplusarg "power_mode=$mode" -testplusarg "power_weight=$weight" -testplusarg "power_batches=$batches" -tclbatch "$source_root/scripts/power_trace.tcl" > simulate.log 2>&1
        rg -q POWER_SIMULATION_PASS simulate.log
        rg -q POWER_SAIF_PASS simulate.log
        timeout --signal=TERM --kill-after=10s 300s "$vivado_root/bin/vivado" -mode batch -source "$source_root/scripts/power_report.tcl" -tclargs "$run_root/build/routed.dcp" "$case_dir/activity.saif" "$case_dir" > report.log 2>&1
        rg -q POWER_REPORT_PASS report.log
        printf 'POWER_CASE_PASS weight=%s mode=%s directory=%s\n' "$weight" "$mode" "$case_dir"
    done
done
python3 "$source_root/scripts/power_summary.py" "$run_root"
printf 'POWER_RUN_PASS %s\n' "$run_root"
