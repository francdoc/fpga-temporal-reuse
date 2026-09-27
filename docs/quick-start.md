# Quick Start

Run the same four-input computation on one physical circuit: A reads the
weight four times; B reads it once and retains it. Both produce the same
products in 12 clock periods. Start with saved data, then simulate, build
and run your own board. Power analysis is separate.

## Tested setup

| Item | Configuration used for the recorded results |
| --- | --- |
| Board | Digilent Arty Z7-10, PCB Rev. D; `xc7z010clg400-1`. Not the Z7-20. |
| Host | Ubuntu 22.04.5 LTS, x86-64; Bash; Python 3.10.12. |
| FPGA tools | Vivado/XSim 2018.1, build 2188600, under `/opt/Xilinx/Vivado/2018.1`. |
| Device/IP support | Zynq-7000 target above, Clocking Wizard 6.0, VIO 3.0 and ILA 6.2. |
| Connection | Powered board, USB data cable on the programming connection and working cable drivers/USB permissions. |

Install the tools separately; this repository does not bundle Vivado or
vendor IP. Other host/tool versions have not been validated here. The JTAG
launcher requires `unshare`, `ip`, enabled unprivileged user namespaces and
host `libudev.so.1`/`libselinux.so.1`. It applies a process-local library
workaround for this older Vivado release; see [hardware access](../README.md#115-access-the-physical-board-through-jtag).
Do not run Vivado as root or disable security controls to bypass a failure.
The command-line flow also uses GNU utilities such as `timeout`, `mktemp`
and `sha256sum`; optional power runners require `rg` (ripgrep). Python checks
use the standard library. A desktop session is needed only for GUI views.

## 1. Check the saved results first — no FPGA or Vivado needed

Start in the root of your checkout. These commands and the following steps
use one Bash terminal; stop at any failure.

```bash
export REUSE_REPO="$(pwd -P)"
test -f "$REUSE_REPO/rtl/temporal_reuse.vhd" || exit 1
python3 scripts/check_capture.py --radix HEX \
    --run A 3 results/hardware/A_w3.csv \
    --run B 3 results/hardware/B_w3.csv \
    --run A -2 results/hardware/A_wminus2.csv \
    --run B -2 results/hardware/B_wminus2.csv || exit 1
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tb -p 'test_*.py' || exit 1
```

Require `FOUR_RUN_CAPTURE_CHECK_PASS` and passing unit tests. This rechecks
saved hardware evidence; it does not run the FPGA or establish a fresh result.
For the source-file checks, run `sha256sum -c results/source.sha256` and
`sha256sum -c results/energy/source.sha256` from the repository root.

## 2. Set up Vivado and simulate — no board needed

Adjust the installation root if necessary. Run from a fresh directory outside
the checkout; repeat setup in a new terminal. Keep useful outputs privately
in durable storage because `/tmp` may be cleared on reboot.

```bash
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
test -r "$REUSE_VIVADO_ROOT/settings64.sh" || exit 1
source "$REUSE_VIVADO_ROOT/settings64.sh" || exit 1
export REUSE_RUN="$(mktemp -d /tmp/fpga-temporal-reuse.XXXXXX)"
cd "$REUSE_RUN" || exit 1
"$REUSE_VIVADO_ROOT/bin/vivado" -version || exit 1
timeout --signal=TERM --kill-after=10s 1200s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log "$REUSE_RUN/simulation_driver.log" -journal "$REUSE_RUN/simulation_driver.jou" \
    -source "$REUSE_REPO/scripts/run_sim.tcl" \
    -tclargs "$REUSE_REPO" "$REUSE_RUN/sim" || exit 1
```

Require `sim/simulation_pass.txt` with both `TEMPORAL_REUSE_ALL_TESTS_PASSED`
and `BOARD_CONTROL_SIMULATION_PASS`. Waveforms are in `sim/*.wdb` and
`sim/*.vcd`. A timeout or an open waveform alone is not a pass.

## 3. Build the full board design — still no board needed

```bash
timeout --signal=TERM --kill-after=10s 1800s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log "$REUSE_RUN/build.log" -journal "$REUSE_RUN/build.jou" \
    -source "$REUSE_REPO/scripts/build_board.tcl" \
    -tclargs "$REUSE_REPO" "$REUSE_RUN/build" || exit 1
```

Require `BOARD_BUILD_PASS`. Review `build/implementation_checks.txt`, timing
and DRC reports. The build generates `temporal_reuse.bit`, matching
`temporal_reuse.ltx` and `routed.dcp` under `build/`; it does not program a board.
The runner creates the clock/debug IP, so no manual block design is needed.
Time limits bound the commands; they are not promised run durations.

## 4. Discover, program and capture the physical FPGA

Finish any other session using this board first. Confirm the board revision
and part. Discover targets in a separate fresh directory:

```bash
lsusb -d 0403:6010
export REUSE_DISCOVERY="$(mktemp -d "$REUSE_RUN/discovery.XXXXXX")"
cd "$REUSE_DISCOVERY" || exit 1
bash "$REUSE_REPO/scripts/hardware_session.sh" \
    "$REUSE_REPO/scripts/discover_board.tcl" || exit 1
```

The USB ID identifies the interface type, not a unique FPGA. In the local
discovery output, find the intended `TARGET:` and confirm its devices include
`xc7z010_1` (the tested board also exposes `arm_dap_0`). Replace the placeholder
below with that exact target; never select an arbitrary first device.

**The next command programs volatile FPGA configuration and runs A and B.**
It does not write flash. Both modes use the same bitstream.

```bash
export REUSE_TARGET='<exact target path from your discovery output>'
export REUSE_HARDWARE="$(mktemp -d "$REUSE_RUN/hardware.XXXXXX")"
cd "$REUSE_HARDWARE" || exit 1
bash "$REUSE_REPO/scripts/hardware_session.sh" \
    "$REUSE_REPO/scripts/run_hardware.tcl" "$REUSE_TARGET" \
    "$REUSE_RUN/build/temporal_reuse.bit" \
    "$REUSE_RUN/build/temporal_reuse.ltx" "$REUSE_HARDWARE/captures" || exit 1
cd "$REUSE_HARDWARE/captures" || exit 1
python3 "$REUSE_REPO/scripts/check_capture.py" --radix HEX \
    --run A 3 A_w3.csv --run B 3 B_w3.csv \
    --run A -2 A_wminus2.csv --run B -2 B_wminus2.csv || exit 1
```

`HARDWARE_CAPTURE_COMPLETE` confirms exports were saved. Require the separate
`FOUR_RUN_CAPTURE_CHECK_PASS` to establish the trace checks passed. Both modes
use inputs `[1, 2, -3, 4]`:

| Runtime weight | Products in both modes | Reads/loads A vs. B | Core periods |
| --- | --- | --- | --- |
| `3` | `[3, 6, -9, 12]` | `4` vs. `1` | `12` |
| `-2` | `[-2, -4, 6, -8]` | `4` vs. `1` | `12` |

Keep the fresh captures and programming hashes. Do not commit raw logs,
personal absolute paths, hostnames, full JTAG target IDs or cable serials.
If a step fails, retain its logs privately and use the
[troubleshooting table](../README.md#116-troubleshooting-and-evidence-hygiene).
Do not reuse output directories or treat partial results as a completed run.

## Where to go next

- Understand the circuit: [README Sections 1, 4 and 6](../README.md#overview).
- Find source, scripts and evidence: [repository map](../README.md#repository-map).
- Change weights and inspect fresh GUI captures: [live demo](live-demo.md).
- Open floorplan, schematic or saved waveforms: [Vivado views](vivado-views.md).
- Reproduce power estimates and autonomous trials: [energy experiment](energy-experiment.md).

The baseline above proves correct products with fewer source-memory accesses.
It does not measure joules. Energy estimates and their limitations are
recorded separately in the [energy results](../results/energy/README.md).
