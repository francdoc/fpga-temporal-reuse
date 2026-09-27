#!/usr/bin/env bash
# Shared setup only; the existing Tcl/Python runners own the experiment checks.
reuse_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

reuse_setup_vivado() {
    export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
    REUSE_VIVADO_ROOT=$(realpath -e -- "$REUSE_VIVADO_ROOT")
    if [[ ! -r "$REUSE_VIVADO_ROOT/settings64.sh" || ! -x "$REUSE_VIVADO_ROOT/bin/vivado" ]]; then
        printf 'Vivado unavailable. Set REUSE_VIVADO_ROOT and run check_setup.sh.\n' >&2
        return 1
    fi
    # The vendor setup script is not compatible with nounset.
    set +u
    source "$REUSE_VIVADO_ROOT/settings64.sh"
    set -u
}

reuse_new_run() {
    local parent
    parent=$(realpath -e -- "${REUSE_RUN_PARENT:-${TMPDIR:-/tmp}}")
    if [[ ! -d "$parent" || ! -w "$parent" ]]; then
        printf 'REUSE_RUN_PARENT must be an existing writable directory.\n' >&2
        return 1
    fi
    case "$parent/" in
        "$reuse_repo/"*) printf 'Run output must be outside the checkout.\n' >&2; return 1 ;;
    esac
    reuse_run=$(mktemp -d "$parent/fpga-temporal-reuse-$1.XXXXXX")
    printf 'RUN_DIR=%s\n' "$reuse_run"
    cd "$reuse_run"
    trap 'reuse_status=$?; if ((reuse_status)); then printf "RUN_FAILED status=%s; retained logs: %s\n" "$reuse_status" "$reuse_run" >&2; fi' EXIT
}
