#!/usr/bin/env bash
# Programming is an explicit subcommand; discovery never programs a device.
set -euo pipefail
usage() {
    printf 'Usage: bash scripts/hardware.sh discover\n'
    printf '       bash scripts/hardware.sh run BUILD_DIR EXACT_TARGET\n'
    printf 'run programs the selected board and verifies four fresh captures.\n'
}
if [[ $# == 1 && $1 == --help ]]; then usage; exit 0; fi
if [[ $# == 1 && $1 == discover ]]; then
    reuse_action=discover
elif [[ $# == 3 && $1 == run ]]; then
    reuse_action=run
    reuse_build=$(realpath -e -- "$2")
    reuse_target=$3
    if [[ -z "$reuse_target" || "$reuse_target" == *[\*\?\[\]\<\>]* ]]; then
        printf 'Use the exact target from discovery, not a wildcard or placeholder.\n' >&2
        exit 2
    fi
    for artifact in temporal_reuse.bit temporal_reuse.ltx implementation_checks.txt; do
        if [[ ! -s "$reuse_build/$artifact" ]]; then
            printf 'Missing build artifact: %s/%s\n' "$reuse_build" "$artifact" >&2
            exit 1
        fi
    done
    grep -Fxq IMPLEMENTATION_CHECKS_PASS "$reuse_build/implementation_checks.txt"
else
    usage >&2
    exit 2
fi
source "$(dirname -- "${BASH_SOURCE[0]}")/runner_common.sh"
reuse_setup_vivado
reuse_new_run "hardware-$reuse_action"
printf 'Close competing Hardware Manager sessions before using this command.\n'
if [[ $reuse_action == discover ]]; then
    bash "$reuse_repo/scripts/hardware_session.sh" "$reuse_repo/scripts/discover_board.tcl" > console.log 2>&1
    grep -q '^TARGET:' hardware_client.log
    grep -q '^DEVICES:' hardware_client.log
    grep -E '^(TARGET:|DEVICES:)' hardware_client.log
    printf 'DISCOVERY_COMPLETE: identify your intended xc7z010_1; no programming performed.\n'
else
    printf 'Programming the explicitly selected board; log: %s/hardware_client.log\n' "$reuse_run"
    bash "$reuse_repo/scripts/hardware_session.sh" \
        "$reuse_repo/scripts/run_hardware.tcl" "$reuse_target" \
        "$reuse_build/temporal_reuse.bit" "$reuse_build/temporal_reuse.ltx" \
        "$reuse_run/captures" > console.log 2>&1
    grep -q '^HARDWARE_CAPTURE_COMPLETE:' hardware_client.log
    python3 -B "$reuse_repo/scripts/check_capture.py" --radix HEX \
        --run A 3 "$reuse_run/captures/A_w3.csv" --run B 3 "$reuse_run/captures/B_w3.csv" \
        --run A -2 "$reuse_run/captures/A_wminus2.csv" --run B -2 "$reuse_run/captures/B_wminus2.csv" \
        | tee "$reuse_run/capture_checks.txt"
    grep -Fxq FOUR_RUN_CAPTURE_CHECK_PASS "$reuse_run/capture_checks.txt"
    printf 'HARDWARE_PASS\nCAPTURES_DIR=%s/captures\n' "$reuse_run"
fi
