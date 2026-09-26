#!/usr/bin/env bash
# Keep an interactive Vivado client and its JTAG server in one private namespace.
set -euo pipefail
if (( $# < 4 || $# > 5 )); then
    echo "Usage: bash hardware_gui.sh TARGET BITSTREAM PROBES OUTPUT_DIR [--program]" >&2
    exit 2
fi
export REUSE_GUI_SCRIPT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/interactive_hardware.tcl"
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
export REUSE_HW_PRELOAD="${REUSE_HW_PRELOAD:-/lib/x86_64-linux-gnu/libudev.so.1:/lib/x86_64-linux-gnu/libselinux.so.1}"
test -n "${DISPLAY:-}" || { echo "A graphical desktop session is required." >&2; exit 1; }
test -r "$REUSE_GUI_SCRIPT"
test -r "$2"
test -r "$3"
test ! -e "$4" || { echo "OUTPUT_DIR must be new." >&2; exit 1; }
if (( $# == 5 )) && [[ $5 != --program ]]; then
    echo "The only optional argument is --program." >&2
    exit 2
fi
IFS=: read -r -a reuse_preload_files <<< "$REUSE_HW_PRELOAD"
for reuse_library in "${reuse_preload_files[@]}"; do
    test -r "$reuse_library"
done
set +u
source "$REUSE_VIVADO_ROOT/settings64.sh"
set -u
test ! -e hardware_gui.log
test ! -e hardware_gui.jou
test ! -e hardware_server.log
exec unshare --user --map-root-user --net bash -c '
    set -euo pipefail
    ip link set lo up
    "$REUSE_VIVADO_ROOT/bin/hw_server" -s tcp:127.0.0.1:3121 -I3600 >hardware_server.log 2>&1 &
    reuse_server_pid=$!
    trap '\''kill "$reuse_server_pid" 2>/dev/null || true; wait "$reuse_server_pid" 2>/dev/null || true'\'' EXIT
    sleep 1
    kill -0 "$reuse_server_pid"
    env LD_PRELOAD="$REUSE_HW_PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}" \
        "$REUSE_VIVADO_ROOT/bin/vivado" -mode gui \
        -log hardware_gui.log -journal hardware_gui.jou \
        -source "$REUSE_GUI_SCRIPT" -tclargs "$@"
' bash "$@"
