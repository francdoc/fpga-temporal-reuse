#!/usr/bin/env bash
set -euo pipefail
if (( $# )); then
    printf 'Usage: bash scripts/build.sh\n'
    [[ $# == 1 && $1 == --help ]] && exit 0
    exit 2
fi
source "$(dirname -- "${BASH_SOURCE[0]}")/runner_common.sh"
reuse_setup_vivado
reuse_new_run build
printf 'Building board_top; log: %s/build.log\n' "$reuse_run"
timeout --signal=TERM --kill-after=10s 1800s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log build.log -journal build.jou \
    -source "$reuse_repo/scripts/build_board.tcl" \
    -tclargs "$reuse_repo" "$reuse_run/build" > console.log 2>&1
grep -Fxq BOARD_BUILD_PASS build.log
grep -Fxq IMPLEMENTATION_CHECKS_PASS "$reuse_run/build/implementation_checks.txt"
for artifact in temporal_reuse.bit temporal_reuse.ltx routed.dcp; do
    test -s "$reuse_run/build/$artifact"
done
printf 'BUILD_PASS\nBUILD_DIR=%s/build\nNo board was programmed.\n' "$reuse_run"
