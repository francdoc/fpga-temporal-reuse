# Quick Start

Run the same four-input computation on one physical circuit: A reads the
weight four times; B reads it once and retains it. Both produce the same
products in 12 clock periods. Start with saved data, then simulate, build
and run your own board. Power analysis is separate.

The [Bash script reference](../scripts/README.md) explains every `.sh` file,
its inputs, board effects and success criteria.

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

## Before running the commands

Run these Bash commands in a terminal, not the Vivado Tcl Console. Vivado
must be installed for simulation, build and hardware steps, but **you do not
need to open it**. Those launchers start the required tools automatically in
batch mode, without GUI windows. They save logs/results and exit.

Before hardware commands, disconnect other Vivado Hardware Manager sessions
while leaving the board powered and connected by USB. Simulation and build
do not need the board. Interactive GUI use is a separate workflow, described
in the [live demo](live-demo.md) and [Vivado views](vivado-views.md) guides.

## 1. Check the saved results first — no FPGA or Vivado needed

Run commands from the checkout root. Stop at any failure.

```bash
bash scripts/verify_saved.sh
```

Require `SAVED_EVIDENCE_PASS`. This checks both source hash manifests, eight
saved captures and the validator unit tests. It does not run the FPGA or
establish a fresh physical result.

## 2. Set up Vivado and simulate — no board needed

The checker reports missing prerequisites without installing packages or
changing drivers. The simulation launcher sets up Vivado automatically.

```bash
bash scripts/check_setup.sh
bash scripts/simulate.sh
```

Require `SIMULATE_PASS`. It requires the original core and board-control
pass markers. The printed `RUN_DIR` contains the logs and `sim/` waveforms.
Prerequisite checks alone do not prove tool startup, device/IP support or
licensing; simulation and the full build exercise those paths.

## 3. Build the full board design — still no board needed

```bash
bash scripts/build.sh
```

Require `BUILD_PASS`. Copy the printed `BUILD_DIR` for the next step. It
contains the bitstream, matching probes, routed checkpoint and reports.
Review its `implementation_checks.txt`, timing and DRC reports. The existing
builder generates clock/debug IP and validates mapping/timing. No board is
programmed by this command.

At the end of a successful `build.sh` run, the terminal prints these lines
(example path only; each run gets a different directory):

```text
BUILD_PASS
BUILD_DIR=/tmp/fpga-temporal-reuse-build.ABC123/build
No board was programmed.
```

Copy only the path after `BUILD_DIR=`, including the final `/build`. The
script created that directory and placed `temporal_reuse.bit` and
`temporal_reuse.ltx` there. `BUILD_DIR` is a printed label, not a shell
variable automatically set in your terminal. If you missed it, scroll back
to the end of the build output.

### Follow the build logs

The build can take several minutes. Its terminal may be quiet because tool
output is saved to logs rather than streamed there. Leave that terminal
running and open a **second terminal**. Copy the directory path from this
run's printed `RUN_DIR` (without the `RUN_DIR=` prefix):

```bash
REUSE_LOG_DIR='<RUN_DIR printed by build.sh>'
tail -f "$REUSE_LOG_DIR/build.log"
```

The main log can pause while Vivado works on a substep. It prints the detailed
`runme.log` paths under “Run output will be captured here”. For example, to
follow ILA synthesis, stop the current log viewer with Ctrl+C and run:

```bash
tail -f "$REUSE_LOG_DIR/build/project/temporal_reuse.runs/reuse_ila_synth_1/runme.log"
```

In that same `temporal_reuse.runs` directory, `synth_1/runme.log` records
top-level synthesis and `impl_1/runme.log` records implementation. Follow the
file for the current stage; later-stage logs do not exist until that stage
starts. `console.log` in `REUSE_LOG_DIR` also captures tool stdout/stderr.

**Ctrl+C in the second terminal stops only `tail`, not the build.** Do not
press it in the original build terminal unless you intend to interrupt the
build. The log viewer does not exit automatically when the build finishes.
Use `BUILD_PASS` or the failure reported in the original terminal to determine
the outcome; quiet output alone proves neither completion nor a stall.

## 4. Discover, program and capture the physical FPGA

Disconnect competing Hardware Manager sessions first. Confirm the board
revision and part, then check host prerequisites and discover the target:

```bash
bash scripts/check_setup.sh --hardware
bash scripts/hardware.sh discover
```

The USB ID identifies the interface type, not a unique FPGA. In the printed
discovery output, find the intended `TARGET:` and confirm its devices include
`xc7z010_1` (the tested board also exposes `arm_dap_0`). Never select an
arbitrary first device. Relevant output looks like this (fictional directory
and cable ID):

```text
RUN_DIR=/tmp/fpga-temporal-reuse-hardware-discover.DEF456
TARGET: localhost:3121/xilinx_tcf/Digilent/EXAMPLE_CABLE
DEVICES: arm_dap_0 xc7z010_1
```

The programming command needs two arguments from different steps:

| Value | Where it comes from | How to use it |
| --- | --- | --- |
| Build directory | `build.sh` prints `BUILD_DIR=...` after success. | First argument: copy the path after `=`. |
| Board target | `hardware.sh discover` prints `TARGET: ...`. | Second argument: copy the complete target after `TARGET: `. |
| Discovery log directory | `hardware.sh discover` prints `RUN_DIR=...`. | Logs only; **do not use this as the build directory**. |

**The next command programs volatile FPGA configuration and runs A and B.**
It does not write flash. Both modes use the same bitstream.

Replace both angle-bracket placeholders with your own printed values. Keep
the quotes, but not the angle brackets or label text. Neither argument may
be empty (`''`).

```bash
bash scripts/hardware.sh run '<BUILD_DIR printed by build.sh>' '<exact TARGET from discovery>'
```

For the fictional output above, the filled-in command would be the following.
**Do not run these example values unchanged; use your actual path and target.**

```bash
bash scripts/hardware.sh run \
  '/tmp/fpga-temporal-reuse-build.ABC123/build' \
  'localhost:3121/xilinx_tcf/Digilent/EXAMPLE_CABLE'
```

### Follow the hardware log

`hardware.sh run` prints `Programming the explicitly selected board; log:`
followed by the full path to `hardware_client.log`. Leave that terminal
running and open a **second terminal**. Replace the placeholder below with
that complete path, including the filename; keep the quotes:

```bash
tail -f '<hardware_client.log path printed after log:>'
```

Use the current hardware run's log, not a previous discovery or build log.
**Ctrl+C in this second terminal stops only the log viewer, not the hardware
test.** Do not interrupt the original terminal or launch another hardware
test while it is running. The original terminal reports `HARDWARE_PASS` if
all checks succeed, or a failure otherwise. `tail -f` stays open after the
test finishes; stop the viewer separately.

Require `HARDWARE_PASS`. The launcher runs the original four-capture procedure
and requires `FOUR_RUN_CAPTURE_CHECK_PASS`, not merely successful programming.
The printed `CAPTURES_DIR` contains fresh evidence. Both modes use `[1, 2, -3, 4]`:

| Runtime weight | Products in both modes | Reads/loads A vs. B | Core periods |
| --- | --- | --- | --- |
| `3` | `[3, 6, -9, 12]` | `4` vs. `1` | `12` |
| `-2` | `[-2, -4, 6, -8]` | `4` vs. `1` | `12` |

Keep the fresh captures and programming hashes. Do not commit raw logs,
personal absolute paths, hostnames, full JTAG target IDs or cable serials.
If a step fails, retain its logs privately and use the
[troubleshooting table](../README.md#116-troubleshooting-and-evidence-hygiene).
Do not reuse output directories or treat partial results as a completed run.

## Read your results

Start with the hardware run's `capture_checks.txt`, then inspect the simulation
and implementation check files. [Read and interpret a reproduced run](reading-results.md)
maps each printed directory to its evidence, explains the A/B counts and ILA
timing and shows how to open recordings in Vivado. It also covers the optional
power summary and its limits. The [operator-run record](../results/launcher-checks.md#operator-run-reproduction)
records a completed repeat of this command sequence without personal paths or
device identifiers.

## Paths and missing prerequisites

Simulation, build and hardware commands create a fresh external directory and
print its location. They retain failed runs and propagate nonzero exits.
Defaults are Vivado `/opt/Xilinx/Vivado/2018.1` and output under `/tmp`.
Override `REUSE_VIVADO_ROOT` for another installation or `REUSE_RUN_PARENT`
for an existing writable directory outside the checkout. `/tmp` is temporary;
keep useful evidence in durable private storage.

On a fresh Ubuntu host, standard dependencies can be installed explicitly:

```bash
sudo apt install python3 coreutils grep util-linux iproute2 usbutils libudev1 libselinux1
```

This is a system-changing command for the operator to review, not something
the launchers execute. Install Vivado 2018.1 separately with Zynq-7000 device
support. Cable drivers and permissions are covered in
[README Section 11.5](../README.md#115-access-the-physical-board-through-jtag).
If namespace checks fail, ask the system administrator rather than disabling
security restrictions. `check_setup.sh --help` documents the checker scope.

For the underlying commands and pass-marker details, see
[README Section 11](../README.md#11-software-access-and-execution-guide).
Optional power/repeater runners remain separate and unchanged.

## Where to go next

- Understand the circuit: [README Sections 1, 4 and 6](../README.md#overview).
- Follow the source in order: [Reading the code](reading-code.md).
- Find source, scripts and evidence: [repository map](../README.md#repository-map).
- Change weights and inspect fresh GUI captures: [live demo](live-demo.md).
- Open floorplan, schematic or saved waveforms: [Vivado views](vivado-views.md).
- Reproduce power estimates and autonomous trials: [energy experiment](energy-experiment.md).

The baseline above proves correct products with fewer source-memory accesses.
It does not measure joules. Energy estimates and their limitations are
recorded separately in the [energy results](../results/energy/README.md).
