#!/usr/bin/env bash
# Check prerequisites only; simulation/build and JTAG discovery provide runtime proof.
set -uo pipefail
if [[ $# == 1 && $1 == --help ]]; then
    printf 'Usage: bash scripts/check_setup.sh [--hardware]\n'
    printf 'Check host tools and installation files; --hardware also checks USB permissions and namespace support.\n'
    printf 'No packages installed, no Vivado/JTAG session opened. Runtime support still needs simulation/build/discovery.\n'
    exit 0
fi
if (( $# > 1 )) || { (( $# == 1 )) && [[ $1 != --hardware ]]; }; then
    printf 'Usage: bash scripts/check_setup.sh [--hardware]\n' >&2
    exit 2
fi
failures=0
pass() { printf 'PASS %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }
need() { if command -v "$1" >/dev/null 2>&1; then pass "$1 available"; else fail "$1 missing from PATH"; fi; }

if [[ $(uname -s) == Linux && $(uname -m) == x86_64 ]]; then pass 'Linux x86-64'; else fail 'Linux x86-64 required for the documented tools'; fi
if (( BASH_VERSINFO[0] >= 4 )); then pass "Bash $BASH_VERSION"; else fail 'Bash 4 or newer required'; fi
if [[ -r /etc/os-release ]]; then
    source /etc/os-release
    if [[ ${PRETTY_NAME:-} == 'Ubuntu 22.04.5 LTS' ]]; then pass "$PRETTY_NAME (tested host)"; else warn "${PRETTY_NAME:-unknown OS}: host differs from tested Ubuntu 22.04.5 LTS"; fi
else
    warn 'Cannot identify host release; tested host is Ubuntu 22.04.5 LTS'
fi
for utility in timeout mktemp realpath sha256sum tee; do
    if command -v "$utility" >/dev/null 2>&1 && utility_version=$("$utility" --version 2>/dev/null) && [[ $utility_version == *'GNU coreutils'* ]]; then
        pass "GNU $utility"
    else
        fail "GNU $utility required"
    fi
done
need grep
if command -v python3 >/dev/null 2>&1 && python_version=$(python3 -B -c 'import argparse,csv,hashlib,importlib.util,io,json,pathlib,re,sys,unittest,xml.etree.ElementTree; assert sys.version_info.major == 3; print(sys.version.split()[0])' 2>/dev/null); then
    pass "Python $python_version and required standard-library modules"
    [[ $python_version == 3.10.12 ]] || warn 'Python differs from tested 3.10.12; run the saved-data tests'
else
    fail 'Python 3 with the required standard-library modules is unavailable'
fi
vivado_root=${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}
if [[ -r $vivado_root/settings64.sh ]]; then pass "Vivado settings readable: $vivado_root/settings64.sh"; else fail "Vivado settings missing or unreadable: $vivado_root/settings64.sh"; fi
for executable in vivado xvhdl xvlog xelab xsim; do
    if [[ -x $vivado_root/bin/$executable ]]; then pass "$executable executable"; else fail "$vivado_root/bin/$executable missing or not executable"; fi
done
[[ $vivado_root == /opt/Xilinx/Vivado/2018.1 ]] || warn "Selected Vivado root differs from tested /opt/Xilinx/Vivado/2018.1: $vivado_root"
warn 'Exact installed Vivado version is unchecked; the tested version is 2018.1 build 2188600'

if [[ ${1:-} == --hardware ]]; then
    for utility in unshare ip lsusb; do need "$utility"; done
    if [[ -x $vivado_root/bin/hw_server ]]; then pass 'hw_server executable'; else fail "$vivado_root/bin/hw_server missing or not executable"; fi
    IFS=: read -r -a preload_files <<< "${REUSE_HW_PRELOAD:-/lib/x86_64-linux-gnu/libudev.so.1:/lib/x86_64-linux-gnu/libselinux.so.1}"
    for library in "${preload_files[@]}"; do
        if [[ -f $library && -r $library ]]; then pass "Preload library readable: $library"; else fail "Preload library missing or unreadable: $library"; fi
    done
    if command -v timeout >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 && command -v ip >/dev/null 2>&1; then
        if timeout --signal=TERM --kill-after=2s 10s unshare --user --map-root-user --net ip link show lo >/dev/null 2>&1; then
            pass 'Private user/network namespace available'
        else
            fail 'Private user/network namespace unavailable; hardware launcher cannot run'
        fi
    fi
    if command -v lsusb >/dev/null 2>&1; then
        if usb_devices=$(lsusb -d 0403:6010 2>/dev/null) && [[ -n $usb_devices ]]; then
            while read -r _ usb_bus _ usb_device _; do
                usb_node="/dev/bus/usb/$usb_bus/${usb_device%:}"
                if [[ -c $usb_node && -r $usb_node && -w $usb_node ]]; then pass "USB 0403:6010 node readable/writable: $usb_node"; else fail "USB 0403:6010 node not readable/writable: $usb_node"; fi
            done <<< "$usb_devices"
        else
            fail 'No USB interface 0403:6010 found; check board power and programming cable'
        fi
    fi
    warn 'USB enumeration and permissions do not prove board identity or JTAG access'
fi
printf 'Scope: prerequisite files and commands only; tool launch, device/IP support and licenses need simulation/build checks.\n'
printf 'JTAG identity, access and ownership need a separate hardware discovery session.\n'
if (( failures )); then printf 'CHECK_SETUP_FAIL failures=%s\n' "$failures"; exit 1; fi
printf 'CHECK_SETUP_PASS (prerequisites checked; heed any WARN lines)\n'
