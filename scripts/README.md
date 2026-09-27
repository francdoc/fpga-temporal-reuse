# Bash script reference

Start with the [Quick Start](../docs/quick-start.md). Run the commands below
from the repository root using Bash. None installs packages or changes drivers.

## Baseline experiment

You do not need Vivado open. `simulate.sh`, `build.sh` and `hardware.sh` start
the installed tools automatically in batch mode, without GUI windows, then
save logs/results and exit. Before hardware commands, disconnect competing
Hardware Manager sessions but keep the board powered and connected by USB.
The optional `hardware_gui.sh` below is a separate interactive GUI workflow.

| Command | What it does | Board access | Success |
| --- | --- | --- | --- |
| `bash scripts/check_setup.sh` | Checks host commands, Python modules and Vivado installation files. `--hardware` also checks USB permissions, libraries and namespace support. | USB enumeration only with `--hardware`; no JTAG session. | `CHECK_SETUP_PASS`; read any warnings. Runtime tool/device support is checked by later steps. |
| `bash scripts/verify_saved.sh` | Verifies source/capture hashes, eight saved hardware captures and the Python validator tests. | None. It does not produce new hardware evidence. | `SAVED_EVIDENCE_PASS`. |
| `bash scripts/simulate.sh` | Compiles and simulates the core and board-control testbenches through `run_sim.tcl`. Retains assertion logs and WDB/VCD waveforms. | None. | `SIMULATE_PASS`, requiring both original testbench markers. |
| `bash scripts/build.sh` | Generates clock/debug IP, synthesizes, places, routes and writes the full board bitstream. Checks timing, DRC and mapped BRAM/DSP enables. | None; building does not program a board. | `BUILD_PASS`; prints `BUILD_DIR` containing `.bit`, `.ltx`, `.dcp` and reports. |
| `bash scripts/hardware.sh discover` | Lists JTAG targets and their devices through the existing isolated hardware-session launcher. | Opens/closes targets without programming. | `DISCOVERY_COMPLETE`; the operator must identify the intended `xc7z010_1`. |
| `bash scripts/hardware.sh run BUILD_DIR EXACT_TARGET` | Programs the selected board once, captures A/B with weights 3 and -2, then checks products, cycles and actual read/load pulses. | **Programs volatile configuration and runs the circuit.** No flash writes. | `HARDWARE_PASS`, requiring `FOUR_RUN_CAPTURE_CHECK_PASS`; prints `CAPTURES_DIR`. |

`BUILD_DIR` and `EXACT_TARGET` in the command above are argument labels, not
literal values. For the first argument, copy the path after `BUILD_DIR=`
printed at the end of a successful `build.sh` run. For the second, copy the
complete value after `TARGET: ` from discovery. Quote both arguments; neither
may be empty. Discovery's `RUN_DIR` contains its logs, not the build files.
See the [Quick Start example](../docs/quick-start.md#4-discover-program-and-capture-the-physical-fpga)
for output samples and a filled-in command with fictional values.
There is no automatic first-device selection. Close competing Hardware Manager
connections before discovery or programming. These commands accept `--help`.

Simulation, build and hardware launchers set up Vivado and create fresh output
directories outside the checkout. Each prints `RUN_DIR`; logs remain there
after success or failure. A failed tool, missing required marker or failed
capture check gives a nonzero exit status. A zero tool exit alone is not enough.

To watch a running build without interrupting it, follow `build.log` or the
active substep's `runme.log` in a second terminal. The Quick Start provides
[copyable log-following commands](../docs/quick-start.md#follow-the-build-logs)
and explains when to switch logs and where Ctrl+C is safe.
For physical tests, follow the `hardware_client.log` path printed by
`hardware.sh run`; see [Follow the hardware log](../docs/quick-start.md#follow-the-hardware-log).

`REUSE_VIVADO_ROOT` selects the installation (default
`/opt/Xilinx/Vivado/2018.1`). `REUSE_RUN_PARENT` selects an existing writable
output parent outside the checkout (default `TMPDIR`, otherwise `/tmp`).
Preserve important outputs in durable private storage.

## Existing optional runners

These entry points are unchanged. They are separate from the baseline steps.

| Script | Purpose and inputs | Board access / output |
| --- | --- | --- |
| [run_power.sh](run_power.sh) | Builds the isolated core, simulates matched A/B workloads and produces SAIF-annotated Vivado power estimates. No positional arguments. | No board. Requires `rg`; writes `summary.md`/`summary.json` and ends with `POWER_RUN_PASS`. Estimates are not electrical measurements. |
| [run_board_power.sh](run_board_power.sh) | Takes the **energy-board variant's routed checkpoint** as its one argument and estimates the complete implemented PL design. | No board. Ends with `BOARD_POWER_RUN_PASS`; follow the [energy guide](../docs/energy-experiment.md) for the matching build and workload. |
| [hardware_gui.sh](hardware_gui.sh) | Takes `TARGET BITSTREAM PROBES OUTPUT_DIR [--program]` and opens interactive VIO/ILA controls. Needs a graphical session and a new output directory. | Attaches by default, then resets, loads weight 7 and runs A/B. `--program` additionally programs the bitstream. Leaves the GUI connected; see the [live demo](../docs/live-demo.md). |
| [hardware_session.sh](hardware_session.sh) | Lower-level helper taking `SCRIPT.tcl [TCL_ARGUMENTS...]`. Starts the JTAG server and batch Vivado client together in a private network namespace. Run from a fresh external directory. | Hardware effects depend on the supplied Tcl script. Retains client/server logs, bounds the session and stops its own server afterward. Baseline users normally call `hardware.sh` instead. |

Power runners use `REUSE_POWER_PARENT` rather than `REUSE_RUN_PARENT`; their
batch-count and checkpoint-reuse options are documented in the energy guide.
The hardware launchers use `REUSE_HW_PRELOAD` for the process-local library
workaround described in [README Section 11.5](../README.md#115-access-the-physical-board-through-jtag).

## Internal helper

[runner_common.sh](runner_common.sh) is sourced by the new launchers. It only
locates the checkout, loads the selected Vivado environment and creates a
fresh external run directory with failure-log reporting. It is not a user
command or a second implementation of the experiment.

The Tcl/Python runners still own the circuit-specific checks. No Bash wrapper
changes the arithmetic, clock schedule, reuse policy or expected results.

See the [launcher retest record](../results/launcher-checks.md) for the fresh
simulation, full build, physical A/B results and failure-path checks.
