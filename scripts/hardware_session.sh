#!/usr/bin/env bash
# Run the USB/JTAG server and Vivado in the same private network namespace.
set -euo pipefail
if (( $# < 1 )); then
    echo "Usage: bash hardware_session.sh SCRIPT.tcl [TCL_ARGUMENTS...]" >&2
    exit 2
fi
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
export REUSE_HW_PRELOAD="${REUSE_HW_PRELOAD:-/lib/x86_64-linux-gnu/libudev.so.1:/lib/x86_64-linux-gnu/libselinux.so.1}"
IFS=: read -r -a reuse_preload_files <<< "$REUSE_HW_PRELOAD"
for reuse_library in "${reuse_preload_files[@]}"; do
    test -r "$reuse_library"
done
test -r "$REUSE_VIVADO_ROOT/settings64.sh"
# The vendor setup script is not compatible with nounset.
set +u
source "$REUSE_VIVADO_ROOT/settings64.sh"
set -u
test ! -e hardware_server.log
test ! -e hardware_client.log
exec unshare --user --map-root-user --net bash -c '
    set -euo pipefail
    ip link set lo up
    "$REUSE_VIVADO_ROOT/bin/hw_server" -s tcp:127.0.0.1:3121 -I3600 >hardware_server.log 2>&1 &
    reuse_server_pid=$!
    trap '\''kill "$reuse_server_pid" 2>/dev/null || true; wait "$reuse_server_pid" 2>/dev/null || true'\'' EXIT
    sleep 1
    kill -0 "$reuse_server_pid"
    # Load the host udev/SELinux libraries first to avoid the 2018.1 licensing/WebTalk
    # allocator crash at Hardware Manager shutdown. No installed files change.
    timeout --signal=TERM --kill-after=10s 300s \
        env LD_PRELOAD="$REUSE_HW_PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}" \
        "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
        -log hardware_client.log -journal hardware_client.jou \
        -source "$1" -tclargs "${@:2}"
' bash "$@"
