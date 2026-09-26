# Temporal reuse: energy experiment

The objective is to determine whether register reuse reduces energy per
correct product on this FPGA. The existing physical demonstration establishes
operand reuse and fewer BRAM reads. An energy conclusion requires either an
activity-annotated estimate or a voltage/current measurement, each with its
own stated boundary.

This document records the hypothesis, experimental controls and run commands.
Results belong in saved run records; a planned check is not a passing result.
The [26 September results](../results/energy/README.md) contain the completed
core estimates, a qualified complete-design estimate and ten passing physical
repeated-run trials. Electrical board energy was not measured.

## Established physical behavior

The [interactive hardware captures](../results/interactive/README.md) used
one programmed Arty Z7-10 Rev. D circuit with runtime inputs
`x = [1, 2, -3, 4]`:

| Runtime weight | Products in both modes | A reads / loads | B reads / loads | Core processing periods |
| --- | --- | --- | --- | --- |
| 7 | `[7, 14, -21, 28]` | 4 / 4 | 1 / 1 | 12 |
| 9 | `[9, 18, -27, 36]` | 4 / 4 | 1 / 1 | 12 |

A reads and reloads before each multiplication. B performs a fresh read and
load at the beginning of every four-product batch, then retains the weight.
Both modes use one scalar processing element, the same placement and the
same schedule. At the configured 100 MHz clock, the core processing interval
is nominally 120 ns; oscillator frequency was not independently measured.

The [mapped implementation checks](../results/implementation_checks.txt)
establish that the observed read signal reaches the RAMB18E1 `ENBWREN` pin.
The weight-load signal reaches DSP48E1 `CEB2`, with `BREG=1`: the logical
weight register is implemented in the DSP input register. The hardware trace
does not directly probe the retained weight's internal value.

The decisive observation is that B continues producing the correct,
runtime-dependent products after the source read and weight-load pulses
stop. One multiplier uses the retained operand at successive times. The
verified connections, enable pulses and products together establish temporal
reuse; an unchanged weight value on a wire alone would not establish it.

This evidence supports 75% fewer accepted source reads for identical work.
It does not establish a 75% energy reduction or any measured energy reduction.
The original automatically generated power report had no matched A/B SAIF
annotation and is not comparative energy evidence.

## Connection to EPDNN

Section 5.4.1, *Temporal Reuse*, of *Efficient Processing of Deep Neural
Networks* describes retaining data in smaller intermediate storage for
repeated use by the same consumer. Read printed pages 79–81, corresponding
to PDF viewer pages 95–97 in the referenced edition, especially Figure 5.2d.
Footnote 6 on printed page 79 makes the energy condition explicit: the
relative access costs must make moving data into the smaller storage
worthwhile. The saved reads must amortize the transfer and retention costs.

Here the source is on-chip BRAM, the intermediate storage is one logical
16-bit operand register and the consumer is one multiplier. There is no
external DDR transfer, neural-network execution or spatial reuse in this
experiment. The book supplies the architectural reasoning; it supplies no
energy value for this particular implementation.

Both A and B already contain the same register. Their comparison measures
the consequence of changing the access policy within one circuit. It does
not measure the area or energy overhead of adding a register to a circuit
that previously lacked one. Nor does logical locality prove a shorter
physical wire.

The working hypothesis is:

```text
energy per correct product in B < energy per correct product in A
```

Avoiding three BRAM reads and three weight-load events per batch provides
the mechanism to test. Clock distribution, multiplier activity, control,
debug circuitry and static power still contribute. Repeatedly loading an
unchanged value can have little visible data switching, while internal RAM
activity is not recoverable from output transitions alone. Access counts
therefore do not determine joules per access or total energy.

## Define the comparison before running it

Use one runtime-selectable implementation for each A/B comparison. Freeze
the source revision, tool version, routed checkpoint, clock, operands,
batch count, reset/loading sequence and observation window. Use equal gaps
between batches and identical instrumentation settings. A and B must finish
the same useful work without errors.

Choose and label the observation boundary:

| Boundary | Included work | Interpretation |
| --- | --- | --- |
| Core processing | The specified computation interval. | A core estimate or measurement only if the power observation covers exactly that interval. |
| Autonomous repeated window | `K` batches plus their controller/start gaps. | Energy of the complete repeated window divided by completed work. |
| Complete transaction | Reset, source loading, repeated computation and any included idle time. | End-to-end cost at the declared boundary. |

Either exclude source writes from both A and B processing windows or include
the same writes in both complete-transaction windows. Always include the
initial BRAM read in every B batch. Reusing a weight across batches would
change the experiment.

For a measured window from `t0` to `t1`:

```text
E_window [J] = integral from t0 to t1 of V(t) * I(t) dt
E_batch [J] = E_window / K
E_product [J] = E_window / (4 * K)
Delta_E_product [J] = (E_window_A - E_window_B) / (4 * K)
```

A positive `Delta_E_product` means lower energy in B. For a tool estimate,
use `E_window = P_average * T_window`, where the activity and power average
refer to that exact window. An average that includes controller gaps cannot
be multiplied by the core's 120 ns processing time. Report actual completed
batch and product counts alongside every normalized result.

## Software estimate first

The first energy stage is an isolated-core estimate using one routed
out-of-context checkpoint for both modes. A core estimate excludes board
regulators, peripherals and the debug wrapper; label it accordingly. It is
also separate from a new full-board implementation or electrical measurement.

The analysis flow must:

1. Simulate equivalent complete workloads for A and B using runtime weights
   7 and 9. Verify products, processing cycles and actual read/load events
   before generating a comparison.
2. Capture separate SAIF activity over equal windows with equal batch counts
   and gaps. Keep reset and source loading outside both windows unless they
   are intentionally part of both.
3. Use mapped activity where supported. Annotate the same routed checkpoint
   separately for A and B with identical voltage, temperature and clock
   assumptions.
4. Verify hierarchy matching and annotation coverage, particularly the
   physical BRAM read-enable and DSP weight-load nets. Record any missing or
   estimated activity; an imported SAIF file alone is insufficient.
5. Report total estimated power, dynamic and static contributions and the
   BRAM contribution. Retain the rest of the circuit in the comparison,
   including control activity. Convert power to energy using the captured
   window duration.

Behavioral VHDL traces can omit or fail to match mapped internal signals.
Mapped functional simulation can improve correspondence but does not include
all routing-delay effects of timing simulation. The run record must state
which simulation was used and its limitations. Correct annotation of the
source enable is necessary even when most other nets appear covered.

The board top exposes its runtime controls through an internal
VIO instance; its external port is the source clock. A complete post-route
board simulation therefore needs a deliberate harness for those controls
and the generated clock/debug IP. Core testbench stimulus cannot simply be
attached to nonexistent board input ports. The isolated-core flow does not
include that harness; the separate full-PL flow below does.

The software entry point is `scripts/run_power.sh`. It builds one isolated
core checkpoint, compiles its mapped functional netlist and runs independent
A/B simulations at weights 7 and 9. The default workload is 1,024 batches at
14 clocks per batch: 4,096 products in 143,360 ns per case. The extra idle
slot matches the repeated board workload's cadence. This does not include
the board repeater's own control or counter energy.

Run from the repository root in Bash:

```bash
export REUSE_REPO="$(pwd -P)"
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
export REUSE_POWER_BATCHES=1024
# Optional: use an existing durable external directory instead of /tmp.
# export REUSE_POWER_PARENT=/path/to/private/run-parent
bash "$REUSE_REPO/scripts/run_power.sh"
```

The runner prints `POWER_RUN_DIR` for its fresh output directory. It stops
on failed assertions or a missing pass marker. Keep the routed checkpoint,
four SAIF files, simulation logs, annotation reports and power reports.
Each report starts a separate Vivado process so activity cannot carry over
from the preceding mode. A `POWER_RUN_PASS` requires all four cases.
The runner produces `summary.json` and a readable `summary.md` with the
matched counts, component powers, energy per product, hashes and limitations.

Mapped functional simulation includes primitive behavior but not routed
delay glitches. The estimate uses a separately placed isolated core, not
the original board checkpoint. Neither a full-board power estimate nor a
rail measurement follows from these numbers. The number of displayed
digits is reporting precision, not model accuracy.

## Autonomous repeated workload for physical measurement

A host Tcl loop issuing isolated 120 ns computations spends most of its time
in JTAG commands and idle gaps. To create a useful measurement interval,
the FPGA needs to execute `K` batches after one start command. The host sets
the operands and mode before the window, then reads the completed results
afterward.

The added controller must preserve one scalar PE, four products per batch
and one shared runtime-selectable bitstream. Each B batch still fetches its
weight once. It must not retain a weight across batch boundaries merely to
increase the apparent read reduction.

The repeater interface is:

| Field | Contract |
| --- | --- |
| Batch count | Unsigned 24-bit `K`, from 1 through 16,777,215. |
| Core schedule | 12 processing cycles per batch in both modes. |
| Repeated window | `14 * K` cycles, including two controller/start cycles per batch. |
| Clock | 100 MHz; nominal window duration `14 * K * 10 ns`. |
| Completion observations | 32-bit batch, product, read, load and cycle counts. |
| Arithmetic check | Signed 64-bit sum of all products plus the last product. |
| Expected standard-input checksum | `4 * w * K`, since `1 + 2 - 3 + 4 = 4`. |
| Expected last product | `4 * w`. |
| Expected A totals | `K` batches, `4*K` products, `4*K` reads and `4*K` loads. |
| Expected B totals | `K` batches, `4*K` products, `K` reads and `K` loads. |

For example, `K = 1,000,000` gives a nominal 140 ms repeated window.
The maximum 24-bit count gives about 2.35 s. Longer
windows improve averaging opportunities; they do not enlarge the underlying
average-power difference. Consecutive windows require their gaps to be
included or excluded consistently.

The implementation is in `rtl/batch_repeater.vhd` and
`rtl/energy_board_top.vhd`, with `scripts/run_repeater_sim.tcl` and
`scripts/build_energy_board.tcl`. The intended programming artifacts are
`energy_board.bit` and its matching `.ltx`; the hardware entry point is
`scripts/run_energy_hardware.tcl` through the existing private
`scripts/hardware_session.sh` launcher.

Drive both start and write requests low before releasing reset. Reset clears
their edge history, so a request held high across reset release can be
accepted as a new command. During normal operation, requests held high after
completion or first asserted while busy must return low before a later
command can be accepted.

Building this image is a separate step from the historical single-batch
demonstration. Program it once for both modes, then confirm counts,
checksums, clock and timing before using it for energy observations.

### Simulate and build the board variant

Start in the repository root in Bash. Both commands below use new output
directories and preserve the original demo build:

```bash
export REUSE_REPO="$(pwd -P)"
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
source "$REUSE_VIVADO_ROOT/settings64.sh" || exit 1
export REUSE_ENERGY_RUN="$(mktemp -d /tmp/fpga-reuse-energy.XXXXXX)"
cd "$REUSE_ENERGY_RUN" || exit 1

timeout --signal=TERM --kill-after=10s 300s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log repeater_sim.log -journal repeater_sim.jou \
    -source "$REUSE_REPO/scripts/run_repeater_sim.tcl" \
    -tclargs "$REUSE_REPO" "$REUSE_ENERGY_RUN/sim" || exit 1

timeout --signal=TERM --kill-after=10s 1800s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log energy_build.log -journal energy_build.jou \
    -source "$REUSE_REPO/scripts/build_energy_board.tcl" \
    -tclargs "$REUSE_REPO" "$REUSE_ENERGY_RUN/build" || exit 1
```

The simulation checks each product as well as counters, cadence, signed
extremes, ignored busy commands and reset recovery. In XSim 2018.1, wildcard
waveform logging for this testbench caused a first-edge runtime exception.
The runner logs an explicit list of signals instead, including the 64-bit
checksum. The exact tool defect has not been isolated; it was not resolved
by changing elaboration optimization alone. Keep the explicit trace list
when reproducing this version's run.

Require `REPEATER_SIMULATION_PASS` and `ENERGY_BOARD_BUILD_PASS`, not merely
zero exit codes. The board build checks one source RAMB18E1 and one DSP48E1,
the physical enable connections, 100 MHz clock and timing/DRC results.

### Estimate the complete implemented PL design

The separate full-PL flow uses the routed energy-board checkpoint produced
above, without changing its placement or routing. It does not connect to or
program the board:

```bash
export REUSE_BOARD_POWER_BATCHES=256
bash "$REUSE_REPO/scripts/run_board_power.sh" \
    "$REUSE_ENERGY_RUN/build/routed.dcp"
```

The runner creates a fresh external directory and prints
`BOARD_POWER_RUN_DIR`. It exports the mapped functional netlist, simulates
A and B independently, imports their separate SAIF files into the same
checkpoint and produces `summary.json` and `summary.md`. Require
`BOARD_POWER_RUN_PASS`; preserve failed-run logs if any check stops the flow.

This harness supplies the eleven `cfg_*` controls normally driven by VIO.
It initializes the simulator's JTAG boundary during setup, then holds JTAG
idle during the observation window. It does not force the core's stored
weight, arithmetic results, state or memory enables. The MMCM, core,
repeater, counters and debug circuitry remain in the mapped simulation.
Assertions check every product, actual BRAM/DSP enables and completion
readbacks before accepting the activity files.

The default workload is weight 7, inputs `[1, 2, -3, 4]` and 256 batches:
1,024 products in 35,840 ns. Reset, weight writes and clock-lock settling
are outside both windows. This is a short matched workload, not a simulation
of the entire 10-million-batch physical trial. Counter widths are unchanged,
but higher counter bits may remain inactive in the shorter run.

Report the source RAMB18 primitive separately from the ILA's RAMB36 blocks,
the `repeater/core` hierarchy separately from its wrapper and full-design
dynamic power separately from device-static power. Hierarchy and primitive
rows overlap; do not add them together. A complete PL estimate includes
instrumentation overhead but still excludes external regulators and board
peripherals. No ARM/PS7 workload is instantiated.

The hierarchy rows are Vivado's attribution within this particular routed
design. Synthesis moves some wrapper/checksum logic into `repeater/core`.
Core outputs also drive counter and debug inputs; their fanout and routing
costs differ from the isolated-core build. That hierarchy row is therefore
not the power of the original scalar RTL alone, nor should it equal the
separate OOC estimate. Subtracting it from the repeater hierarchy does not
isolate all instrumentation overhead. The exact source RAM primitive and
the complete implemented design remain unambiguous resource boundaries.

Check activity coverage, unknown signals, the physical source-read and
weight-load pins and the reported clock activity. Native SAIF logging uses
the mapped hierarchy scopes rather than recursively enumerating vendor
primitive implementation internals. Vivado 2018.1 ignores clock-net SAIF
activity and rejects a zero-activity override on JTAG TCK. With the original
constraints retained, it models TCK at about 30.30 MHz even though the
simulation holds it idle. Report that mismatch explicitly: this is not a
fully activity-matched estimate of quiet-JTAG operation. The main experiment
clock remains correctly constrained at 100 MHz in both modes.

This is mapped functional activity without SDF delay glitches, not an
electrical measurement. A full-design reduction can include changes in
the read/load counters and debug inputs as well as the arithmetic core.

### Run autonomous batches on the physical board

This step **programs the FPGA** with the energy variant. It is a functional
check, not an electrical energy measurement. Do not launch a second server
while the same cable is owned by an existing GUI session.

With no competing connected session, set `REUSE_TARGET` to the exact verified
JTAG target and run in a fresh external directory:

```bash
export REUSE_TARGET='<exact verified JTAG target>'
export REUSE_ENERGY_HW="$(mktemp -d /tmp/fpga-reuse-energy-hw.XXXXXX)"
cd "$REUSE_ENERGY_HW" || exit 1
bash "$REUSE_REPO/scripts/hardware_session.sh" \
    "$REUSE_REPO/scripts/run_energy_hardware.tcl" \
    "$REUSE_TARGET" "$REUSE_ENERGY_RUN/build/energy_board.bit" \
    "$REUSE_ENERGY_RUN/build/energy_board.ltx" "$REUSE_ENERGY_HW/results"
```

For an already connected GUI, use its Tcl Console instead. Replace the
private paths; do not use this code in Bash:

```tcl
set reuse_repo {/path/to/repository}
set reuse_energy_build {/path/to/tested/energy-build}
set reuse_energy_results {/path/to/new/hardware-results}
set reuse_energy_library_only 1
source [file join $reuse_repo scripts run_energy_hardware.tcl]
reuse_energy_run [current_hw_device] \
    [file join $reuse_energy_build energy_board.bit] \
    [file join $reuse_energy_build energy_board.ltx] $reuse_energy_results
```

The selected device must already be the verified target. This library path
uses the existing connection and leaves it open. The old `reuse_demo` and
`reuse_capture` helpers belong to the original image; do not use them while
the energy image is programmed. Return to the original `.bit` and matching
`.ltx` before using those helpers again.

The hardware test executes short A/B runs at weights 7, 9 and -2, followed
by A-B-B-A at weight 7 with `K=10,000,000`. Each long run produces 40 million
products in 140 million clock periods, nominally 1.4 s. It reads counters
after completion and leaves ILA acquisition unarmed. Checksums and the last
product supplement the simulation's per-product checks; checksums alone
cannot prove the full output sequence.

Before every trial, reset clears the sticky completion flag and counters,
with both requests low. The script checks those zeros before issuing a new
start. Source BRAM contents survive reset. This prevents the second B trial
from passing with stale readbacks if a start request were missed. Reset and
configuration are outside the counted computation window in both modes.

Require `ENERGY_HARDWARE_PASS`. The output directory contains `hardware.csv`
and a readable `hardware.md` with actual readbacks and programming-artifact
hashes. It explicitly labels voltage, current and electrical energy as not
measured. Host waits are not substituted for hardware window duration.

## Electrical measurement

No voltage/current measurement equipment is available for this run. Measured
board energy therefore remains unavailable; it is not inferred from the
Vivado estimate. A voltage/current instrument or calibrated shunt with
suitable acquisition is required. An ILA or logic analyzer records digital
behavior and cannot measure energy. A suitable measurement point must also
be established before a future electrical test.

Measurement alignment is also pending. The energy board top currently has
only a `sys_clk` external port; it provides no external `run_active` marker.
The cycle counter establishes the window's duration, but it does not identify
that window's start time in an analog acquisition. The current hardware
therefore does not establish synchronized meter integration. With the actual
equipment available, define an instrument synchronization protocol or add a
GPIO marker using a verified safe pin and electrical interface. Treat that
as a separate integration step before reporting a measured window energy.

Select the boundary from the actual Arty Z7-10 Rev. D schematic and power
configuration before connecting instrumentation. Board-input measurement
includes regulators and powered board peripherals. A rail measurement has
a narrower boundary, but the rail may still supply several FPGA resources.
Neither establishes per-BRAM energy by itself. Do not guess connector pins,
test points or allowable shunt wiring; verify polarity, ratings, grounding
and all active supply paths. A parallel USB or other supply path can bypass
the intended measurement boundary.

The measurement procedure is:

1. Record instrument model, range, sample rate, calibration information,
   supply boundary, voltage, board revision and power connections. Establish
   how the sampled window aligns with the FPGA's repeated window; do not
   infer it from host command elapsed time.
2. Use the same bitstream, input sequence, weight, `K`, clock and debug
   configuration in each pair. Allow consistent thermal settling and keep
   peripherals in the same state.
3. Verify functional counters before measurement. During the timed window,
   leave ILA acquisition and host JTAG polling quiet. Read status afterward.
   Debug cores and counters still consume energy even when the host is
   quiet; that overhead remains part of the instrumented design.
4. Acquire repeated A-B-B-A groups, or another recorded balanced order, to
   reduce sensitivity to slow drift. Retain individual observations rather
   than only the averages. Balanced ordering does not eliminate thermal or
   supply drift.
5. Integrate the observed voltage/current over equal windows. Report raw
   total energy, energy per batch and energy per correct product. If an idle
   baseline is subtracted, publish that result separately with its window
   and uncertainty; retain the unsubtracted result.
6. Report repeat count, spread, instrument resolution and relevant
   uncertainty. Compare the A/B difference with repeatability and the
   measurement floor before assigning a sign to the effect.

The read and load counters have mode-dependent activity: each increments
`4*K` times in A and `K` times in B. Their energy contribution does not
automatically cancel because both modes contain identical counter hardware.
The physical A/B result therefore includes this instrumentation activity.
The isolated-core estimate excludes the repeater and its counters, so its
boundary differs from the instrumented board measurement.

If the difference is below the setup's resolution or noise, report
**not resolved by this setup**. A negative or inconclusive energy result is
valid and does not undo the functional reuse result. Increasing PE count to
force a larger signal would change the scope of this scalar experiment.

## Evidence to retain

Each energy run needs its source and artifact hashes, tool version, exact
commands, input sequence, clock, observation boundaries, duration and
completed-work counts. Keep activity files and annotation reports for an
estimate; keep raw voltage/current data and the instrument setup for a
physical measurement. Publish a compact comparison with separate labels for
estimated core energy and measured energy at the named supply boundary.

Generated projects, simulator databases and full tool logs belong outside
tracked source. Publish only the evidence needed to review the result after
removing personal paths, hostnames and hardware identifiers. Never relabel
an estimate as a measurement or derive an energy percentage from read counts.

## References

- [EPDNN book and DOI](https://doi.org/10.1007/978-3-031-01766-7),
  Section 5.4.1, printed pages 79–81, including footnote 6 on page 79.
- [README Section 9: energy evaluation](../README.md#9-energy-evaluation)
  and [Section 12: references](../README.md#12-references-and-reading-path).
- [AMD: specifying switching activity](https://docs.amd.com/r/2021.1-English/ug907-vivado-power-analysis-optimization/Specifying-Switching-Activity-for-the-Analysis?contentId=mF5vvZ83ATAd487sq4TnqQ).
- [AMD: power analysis using Vivado Simulator](https://docs.amd.com/r/2023.1-English/ug900-vivado-logic-simulation/Power-Analysis-Using-Vivado-Simulator).
- [AMD: block RAM enable optimization](https://docs.amd.com/r/2022.2-English/ug904-vivado-implementation/Block-RAM-Enable-Optimization).
- [Digilent: Arty Z7 Rev. D schematic](https://files.digilent.com/resources/programmable-logic/arty-z7/arty-z7-d0-sch.PDF).

The external links above are the references already recorded in the project.
Use the documentation corresponding to the installed tool version for
command syntax.
