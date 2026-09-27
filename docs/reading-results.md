# Read and interpret a reproduced run

Use the [Quick Start](quick-start.md) to run the experiment. This guide explains
what to inspect afterward. The [operator-run record](../results/launcher-checks.md#operator-run-reproduction)
documents a completed repeat of that path, including an isolated-core power
estimate. It is a result record, not a promise that every future run passes.

## 1. Keep each run's output location

The launchers print paths; they do not set variables in your calling shell.
Each invocation creates a fresh directory. Do not confuse the following:

| Printed value | Produced by | Evidence to read there |
| --- | --- | --- |
| Simulation `RUN_DIR` | `simulate.sh` | `sim/simulation_pass.txt`, detailed logs and WDB/VCD waveforms. |
| `BUILD_DIR` | Successful `build.sh` | `implementation_checks.txt`, timing/DRC reports, `.bit`, `.ltx` and `routed.dcp`. |
| Hardware-run `RUN_DIR` | `hardware.sh run` | `capture_checks.txt`, `hardware_client.log` and `captures/`. |
| `CAPTURES_DIR` | Successful `hardware.sh run` | The same hardware run's `captures/` directory: CSV, ILA, VCD and `programming.txt`. |
| `POWER_RUN_DIR` | Optional `run_power.sh` | `summary.md`, `summary.json` and per-case activity/power reports. |

Discovery's `RUN_DIR` holds discovery logs only. It does not contain the
bitstream or completed A/B test results. The repository's `results/` contains
historical evidence; it is not overwritten by a new run.

In a terminal, replace these placeholders with the values from your own run:

```bash
REUSE_RESULT_SIM='<RUN_DIR printed by simulate.sh>'
REUSE_RESULT_BUILD='<BUILD_DIR printed by build.sh>'
REUSE_RESULT_HW='<RUN_DIR printed by hardware.sh run>'

cat "$REUSE_RESULT_SIM/sim/simulation_pass.txt"
cat "$REUSE_RESULT_BUILD/implementation_checks.txt"
cat "$REUSE_RESULT_HW/capture_checks.txt"
```

These commands read existing results; they do not run or program the FPGA.
For a job still running, use the Quick Start's
[build log](quick-start.md#follow-the-build-logs) or
[hardware log](quick-start.md#follow-the-hardware-log) instructions instead.
Stopping `tail` in a second terminal does not stop the original job.

## 2. Decide which stage passed

| Stage | Required evidence | What it establishes |
| --- | --- | --- |
| Saved-data check | `SAVED_EVIDENCE_PASS` in the terminal. | Existing recorded files and validator tests passed; no fresh FPGA run occurred. |
| Simulation | `SIMULATE_PASS`; both `TEMPORAL_REUSE_ALL_TESTS_PASSED` and `BOARD_CONTROL_SIMULATION_PASS` in `sim/simulation_pass.txt`. | The core and board-control testbenches passed. |
| Implementation | `BUILD_PASS`; `IMPLEMENTATION_CHECKS_PASS` in the build's check file, with reports and programming artifacts present. | Physical mapping and timing checks passed and a bitstream was generated; no board was programmed by this step. |
| Physical execution | `HARDWARE_PASS`; four `PASS` lines and `FOUR_RUN_CAPTURE_CHECK_PASS` in `capture_checks.txt`. | Fresh hardware captures passed the product, input, enable and cycle checks. |

Use the actual launcher outcome and the corresponding evidence, not an
isolated success message from an earlier stage. `HARDWARE_CAPTURE_COMPLETE`
means acquisition/export finished; the Python capture checks must still pass.
Similarly, an IP synthesis process exiting successfully is not the end of
the complete board build. A missing file or failed check is not a pass.

## 3. Interpret the physical A/B result

For inputs `[1, 2, -3, 4]`, the required baseline result is:

| Weight | Products in both modes | A reads / loads | B reads / loads | Processing periods in each mode |
| --- | --- | --- | --- | --- |
| 3 | `[3, 6, -9, 12]` | 4 / 4 | 1 / 1 | 12 |
| -2 | `[-2, -4, 6, -8]` | 4 / 4 | 1 / 1 | 12 |

B keeps producing correct products after its only source read and weight load.
The implementation check ties these observed enables to BRAM `ENBWREN` and
DSP `CEB2`, with `BREG=1`. Together, the mapping and runtime-dependent products
establish retention of the operand and avoidance of three source reads per
batch. The stored weight itself is not directly captured by the ILA.

`observed_done_edge=13` is relative to accepted start in the ILA recording.
Registered outputs are observed one sampling edge after the core updates them:
valid products appear at relative samples 4, 7, 10 and 13, corresponding to
the core's multiplication edges 3, 6, 9 and 12. Processing takes 12 periods,
nominally 120 ns at the configured 100 MHz. This is not a speedup: A and B
deliberately use the same schedule. Fewer reads alone do not measure energy.

## 4. Inspect the recordings and circuit in Vivado

The hardware `captures/` directory contains `A_w3`, `B_w3`, `A_wminus2` and
`B_wminus2`, each with these formats:

| Format | Use |
| --- | --- |
| `.ila` | Reopen the actual hardware recording in Vivado without the board. |
| `.csv` | Inspect raw samples or use the capture checker. Signal values are HEX; sample indices are decimal. |
| `.vcd` | Inspect exported hardware signal changes in a compatible waveform viewer. This is distinct from a simulation-generated VCD. |

Follow [Vivado views](vivado-views.md): set `REUSE_BUILD` to your `BUILD_DIR`
and `REUSE_CAPTURE_DIR` to your `CAPTURES_DIR`. Its baseline waveform example
opens these four files; the older interactive session uses different
`capture_*.ila` filenames. The routed `routed.dcp` opens the Device/Netlist
and BRAM/multiplier schematic without connecting to the board.

In a recording, find accepted `core_start`, compare `source_read_enable` and
`weight_register_load`, then read `product` only where `product_valid=1`.
Select signed decimal for `core_x` and `product` in the waveform radix menu.
Stale output values outside valid samples are not additional results.

Offline viewing does not execute the circuit. The [live demo](live-demo.md)
is different: its GUI launcher resets the experiment, loads weight 7 and runs
A/B on startup, even without `--program`. Finish any batch hardware session
before starting that live workflow.

## 5. Read the optional power estimate separately

After `run_power.sh` reports `POWER_RUN_PASS`, read its own output directory:

```bash
REUSE_RESULT_POWER='<POWER_RUN_DIR printed by run_power.sh>'
cat "$REUSE_RESULT_POWER/summary.md"
```

`summary.json` contains the numerical values, workload counts, activity,
environment assumptions and artifact hashes. The standard run compares A/B
at weights 7 and 9, with 1,024 batches and 4,096 products per case. Each matched
window is 143,360 ns: 14 clocks per batch, including gaps. It is not the
single-batch hardware experiment's 120 ns processing-only interval.

Check power and energy boundaries before comparing numbers. Core dynamic
energy excludes static power; isolated-design total includes the modeled
device static contribution but not the complete board. SAIF activity and
primitive power models produce estimates, not voltage/current measurements.
The detailed assumptions are in the summary and [energy guide](energy-experiment.md).

The normal board build also generates a vectorless power report. That report
is not a matched A/B experiment, even if Vivado says power optimization ran.
Do not substitute it for the separate activity-annotated estimate.

## 6. Read warnings in context and preserve evidence

Synthesis may report that `w_reg_reg` or `x_reg_reg` was removed, then report
that it was absorbed into the DSP. Check the final mapped register configuration
and enables rather than interpreting the warning as loss of temporal reuse.
Early routing summaries can contain negative hold slack that later routing
fixes; use the final `timing.rpt` and implementation checks for acceptance.
Review the documented [DRC warning dispositions](../results/README.md#implemented-circuit-and-timing)
instead of assuming all warnings are harmless or suppressing them.

Keep the original run directories in durable private storage before `/tmp`
is cleared. Preserve `.ila` files as well as CSVs for offline Vivado viewing,
the matching `.bit`/`.ltx`, `routed.dcp`, reports and programming hashes. Power
reproduction also needs the SAIF files and annotation reports, not just a
percentage copied from the summary.

Publish only reviewed summaries and evidence. Raw logs, journals, GUI files
and screenshots can contain personal paths, hostnames, cable identifiers or
license details. A saved summary documents the outcome but does not replace
the underlying captures and build artifacts.
