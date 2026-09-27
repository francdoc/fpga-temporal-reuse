# Bash launcher retest

Tested on 26 September 2026 against baseline revision `30ecdc0` plus the
uncommitted launchers documented in the [script reference](../scripts/README.md).
The host was Ubuntu 22.04.5 LTS x86-64 with Python 3.10.12 and Vivado/XSim
2018.1, build 2188600. Physical tests used an Arty Z7-10 Rev. D.

No RTL, constraints or existing Tcl/Python runner changed. Both existing
source-hash manifests passed. These tests exercise the new command interface,
not a different circuit.

## Completed checks

| Command | Observed result |
| --- | --- |
| `bash scripts/verify_saved.sh` | `SAVED_EVIDENCE_PASS`: hashes, eight saved hardware captures and five validator unit tests passed. |
| `bash scripts/check_setup.sh` | `CHECK_SETUP_PASS`. |
| `bash scripts/check_setup.sh --hardware` | `CHECK_SETUP_PASS` with the board connected. |
| `bash scripts/simulate.sh` | `SIMULATE_PASS`: 18 core cases and the board-control testbench passed; VCD/WDB waveforms generated. |
| `bash scripts/build.sh` | `BUILD_PASS`: fresh synthesis, placement, routing, mapping/timing checks and bitstream generation completed. |
| `bash scripts/hardware.sh discover` | `DISCOVERY_COMPLETE`: intended target exposed `arm_dap_0` and `xc7z010_1`. |
| `bash scripts/hardware.sh run BUILD_DIR EXACT_TARGET` | `HARDWARE_PASS`: programmed the newly built bitstream and validated four fresh captures. |

The build reported a 10 ns experiment clock, setup slack of 3.982 ns and
hold slack of 0.053 ns. All reported `check_timing` counts were zero and
there were no pulse-width violations. DRC had no errors; the existing
DPOP-1, RTSTAT-10 and ZPS7-1 warnings remained.

Mapping checks confirmed that the captured read-enable net reaches the
source RAM's `ENBWREN` and the captured weight-load net reaches the DSP's
`CEB2`, with `BREG=1`.

## Fresh physical results

All runs used inputs `[1, 2, -3, 4]` and the same newly programmed bitstream.

| Mode | Runtime weight | Observed products | Source reads | Weight loads | Processing periods |
| --- | --- | --- | --- | --- | --- |
| A | 3 | `[3, 6, -9, 12]` | 4 | 4 | 12 |
| B | 3 | `[3, 6, -9, 12]` | 1 | 1 | 12 |
| A | -2 | `[-2, -4, 6, -8]` | 4 | 4 | 12 |
| B | -2 | `[-2, -4, 6, -8]` | 1 | 1 | 12 |

The capture checker reported `FOUR_RUN_CAPTURE_CHECK_PASS`. Its observed
completion sample was edge 13 because of synchronous ILA observation; the
core's processing interval remained 12 periods.

## Failure handling and scope

Bash syntax and help checks passed. Negative tests rejected invalid arguments,
a missing Vivado installation, an output parent inside the checkout,
placeholder/wildcard targets and missing programming artifacts. A stub tool
that returned zero without producing evidence was rejected by both the
simulation and build launchers.

Discovery with the USB board disconnected failed nonzero and retained logs.
After reconnection, discovery and physical execution passed. No drivers were
installed and no unrelated process was stopped.

Raw logs, reports and fresh captures remain in external run directories,
identified by each launcher's printed `RUN_DIR`. They are not included here
because they contain host paths and JTAG identifiers. Preserve them privately
before temporary storage is cleared.

The existing optional power-analysis and interactive-GUI runners were not
rerun in this launcher regression. Their code is unchanged. These results
establish successful baseline reproduction through the new launchers, not a
new energy measurement or validation on a clean second machine.

## Operator-run reproduction

Later on 26 September 2026, the operator manually followed the Bash workflow
on the same workstation and board, with a fresh simulation directory, fresh
board build and new physical captures. This is a repeat on the tested setup,
not an independent reproduction on a clean machine. The source baseline was
still `30ecdc0` plus the uncommitted launchers and documentation changes.

The command order was `verify_saved.sh`, `check_setup.sh`, `simulate.sh`,
`build.sh`, `check_setup.sh --hardware`, `hardware.sh discover`,
`hardware.sh run BUILD_DIR EXACT_TARGET` and finally `run_power.sh`.
The programming arguments were taken from the successful build's `BUILD_DIR`
and discovery's exact `TARGET`, not the discovery log directory. The
[Quick Start](../docs/quick-start.md) provides the executable instructions;
[Reading results](../docs/reading-results.md) maps their output to the evidence.

The operator's terminal reported `SAVED_EVIDENCE_PASS`, `CHECK_SETUP_PASS`,
`SIMULATE_PASS`, `BUILD_PASS`, `DISCOVERY_COMPLETE`, `HARDWARE_PASS` and
`POWER_RUN_PASS`. Saved files were also inspected:

- Simulation: both testbench markers in `sim/simulation_pass.txt`, with
  18 passing core cases in the detailed log.
- Build: `BOARD_BUILD_PASS`, bitstream/probe/checkpoint files and
  `IMPLEMENTATION_CHECKS_PASS`. Final setup/hold slack was again
  +3.982/+0.053 ns; the three DRC warning categories above remained.
- Hardware: four fresh captures matched every product, read/load count and
  processing interval in the table above. `capture_checks.txt` ended with
  `FOUR_RUN_CAPTURE_CHECK_PASS`. Each capture has CSV, ILA and VCD exports.
  One programming operation served both modes and both runtime weights.
- Power: all four mapped simulations and their power reports passed, with
  matching A/B workloads and 130 of 130 design nets matched in every report.

The fresh programming manifest and actual build files agreed on the bitstream
and probe SHA-256 identities below. The capture-check summary was hashed
separately when preparing this record. Hashes identify this run's artifacts;
a new build need not produce byte-identical programming files.

```text
temporal_reuse.bit  217f837eed69201e59a49ab8667758538411ea5508e45b8f7a10746c87dff2b1
temporal_reuse.ltx  dd47effdf0e04bbffea81cf8fc3eb29fb160867df747b913252f4a505ce79c71
capture_checks.txt 516850b7d8ad881db1398a32115807b97ad8b68b190e33a807c199776461bf5b
```

### Reproduced isolated-core estimate

This optional run used its own routed core checkpoint, not the board's
`routed.dcp`. Each case computed 4,096 products from 1,024 batches over
143,360 ns at 100 MHz. The 14-clock batch interval includes controller gaps;
the initial 300 ns reset/write setup was excluded. Each B batch still
included its first source fetch. Physical memory/register events below are
primitive-pin events in mapped simulation, not electrical measurements.

| Weight | Mode | BRAM reads / DSP weight loads | BRAM dynamic (mW) | Core dynamic (mW) | Core dynamic energy/product (pJ) |
| --- | --- | --- | ---: | ---: | ---: |
| 7 | A | 4,096 / 4,096 | 0.250387 | 1.068883 | 37.4109 |
| 7 | B | 1,024 / 1,024 | 0.062597 | 0.869523 | 30.4333 |
| 9 | A | 4,096 / 4,096 | 0.250386 | 1.068875 | 37.4106 |
| 9 | B | 1,024 / 1,024 | 0.062597 | 0.869516 | 30.4331 |

This reproduces approximately 18.65% lower **modeled core dynamic energy per
product** in B. It does not establish that percentage for total device or
board energy. The generated summary also reports isolated-design static and
total power separately. Numerical estimates match the earlier
[isolated-core results](energy/README.md); generated artifact hashes differ.
The new power checkpoint SHA-256 is
`5316bc6016b8477171dbdffc68ddd90e4682c9c3fd13fd60283ca0c5db58ff5a`.

The estimate uses Vivado 2018.1, typical process, fixed 25 C junction
temperature, VCCINT/VCCBRAM at 1.0 V and VCCAUX at 1.8 V. Mapped functional
activity omits routing-delay glitches and primitive energy remains a vendor
model. Clock activity is supplied by the 10 ns constraint, not clock-net SAIF
annotation. The isolated core excludes board/debug/repeater/clock-generator
overhead. Its unconstrained external ports do not establish board-level
timing. Displayed numerical precision is not measurement accuracy.

No electrical energy was measured. This operator run did not repeat the
separate full-design power estimate, autonomous hardware trials or GUI demo.
Those earlier results remain separate. Raw logs, captures, SAIF files and
reports are retained externally; this record omits their local paths and all
host/cable identifiers. Preserve the underlying artifacts privately before
temporary storage is cleared.
