# Temporal Reuse on FPGA: Repeated BRAM Reads vs. Register Reuse

A controlled A/B experiment on the Arty Z7-10 exploring how retaining a
weight in a register affects memory accesses, switching activity and
estimated energy.

**Status: V1 implemented and verified on the physical FPGA.** Updated on
26 September 2026. Simulation, full-board implementation, timing and all
four physical A/B runs pass on the Arty Z7-10 Rev. D. Both modes produce
identical correct products in 12 clock periods, with four source reads in
A and one in B. The subsequent isolated-core Vivado estimate predicts about
18.65% lower dynamic energy per product in B. This is not a measured board
saving. The autonomous variant also passes physical repeated-run checks;
electrical energy remains unmeasured because no instrument is available.

The separate, instrumented full-design estimate predicts about 0.247% lower
modeled device-total energy in B. Its activity-coverage and JTAG clock-model
limitations are recorded in the [energy results](results/energy/README.md).
[Results and raw hardware captures](results/README.md) record the evidence.
The [interactive VIO/ILA demo](docs/live-demo.md) also has
[verified weight-7 and weight-9 results](results/interactive/README.md).
[Vivado view commands](docs/vivado-views.md) reopen the floorplan, schematic,
VIO/ILA panels and saved hardware waveforms.
The [energy experiment](docs/energy-experiment.md) adds matched core-power
estimation and a separate autonomous repeated-run board variant.
[Energy results](results/energy/README.md) separate the estimates, physical
counter checks and remaining measurement limitations.

## Overview

The experiment applies Section 5.4.1, *Temporal Reuse*, from
*Efficient Processing of Deep Neural Networks*: retain an operand in local
storage to avoid repeated source-memory accesses. For four multiplications
using the same weight:

```text
A: fetch w -> multiply
   fetch w -> multiply
   fetch w -> multiply
   fetch w -> multiply

B: fetch w -> keep it -> multiply -> multiply -> multiply -> multiply
```

Both modes must produce the same products. A and B run sequentially on one
programmed circuit, so the comparison changes the access policy while
keeping the datapath and placement fixed.

This README covers the circuit, verification and physical deployment:

| Topic | Contents |
| --- | --- |
| Principle | Operand retention and reduced source-memory traffic. |
| Circuit | Memory, registers, multiplier, interfaces and clock schedule. |
| Verification | Arithmetic equivalence and actual memory-read counts. |
| Deployment | Board constraints, Vivado build, programming and signal capture. |

The implementation choices serve the following purposes:

- **READ -> LOAD -> MUL:** the selected synchronous memory returns data
  after a clock edge. The circuit must specify when the register receives
  it and when multiplication uses it.
- **Runtime-loaded operands:** prevent synthesis from replacing the intended
  datapath with constant-specific logic.
- **Actual read-enable observation:** an unchanged output value does not
  reveal whether BRAM was read repeatedly.
- **Same bitstream:** keeping placement and circuitry fixed isolates the
  change in reuse policy.
- **JTAG, VIO and ILA:** provide board control and internal signal capture.
  The debug cores are instrumentation within the FPGA design.

The 1024-entry BRAM, 16-bit operands, four-input batch, three-cycle schedule
and 100 MHz target are project choices, not requirements from the book.
Reduced read counts are a functional acceptance criterion; reduced energy
requires separate evaluation.

[Section 1](#1-objective-and-acceptance-criteria),
[Section 4](#4-one-circuit-two-access-policies) and
[Section 6](#6-exact-clock-schedule) describe the objective, datapath and
timing. Sections 8-11 cover implementation and measurement procedures.

## 1. Objective and acceptance criteria

Demonstrate temporal reuse with one scalar multiplier. Both modes compute:

```text
y[i] = x[i] * w
```

- **A — repeated fetch:** read the source BRAM before every multiplication.
- **B — register reuse:** read the source BRAM once per batch, retain the
  weight in a register and reuse it for the remaining multiplications.

Acceptance requires execution on the physical Arty Z7-10: program one
bitstream, load a weight at runtime and capture four correct products in
both modes, with four source reads in A and one in B. Repeat with a different
weight without rebuilding or reprogramming the design.

Required stages are simulation, synthesis, placement, routing, timing checks,
bitstream generation and physical A/B execution. Each component and clock
transition should be understandable without a neural-network background.

The engineering question is whether avoiding source reads changes memory
activity and energy for the same useful work. Reduced reads are a required
functional result. Reduced total energy is a hypothesis to evaluate later.

The execution order is simulation, board implementation, physical execution
and optional energy analysis. Power instrumentation is not required for
functional acceptance.

## 2. Terminology

| Term | Meaning here |
| --- | --- |
| Processing element, or PE | The single scalar multiplier that computes `x * w`. |
| Weight | A signed number supplied at runtime. No learning is required in this experiment. |
| Source memory | An on-chip BRAM holding runtime-writable values. It is not external DDR. |
| Local storage | One 16-bit weight register feeding the multiplier. |
| Temporal reuse | The same consumer uses the same value at different times. |
| Spatial reuse | Several consumers use the same value. This project has only one PE. |
| Physical placement | The sites and routes used to implement the circuit on the FPGA. |

Both A and B need the same weight repeatedly. B exploits that reuse opportunity
at the BRAM-to-register boundary by avoiding redundant source reads.

While the device is operating, the register retains its value until a clocked
load or reset replaces it. It holds one weight per batch. Every batch starts
with a fresh source read.

This is a generic arithmetic exercise motivated by AI-accelerator design.
Weight transfers occur in inference and training; the experiment implements
neither a neural network nor a training algorithm.

## 3. V1 configuration

| Item | Required V1 choice |
| --- | --- |
| Device target | Arty Z7-10, Vivado part `xc7z010clg400-1`. |
| RTL | Small VHDL modules using `IEEE.numeric_std` signed arithmetic. |
| Arithmetic | Signed 16-bit `x`, signed 16-bit `w`, exact signed 32-bit product. |
| PE count | One scalar multiplier, shared by A and B. |
| Source memory | Runtime-addressable `1024 x 16` synchronous memory, intended to map to one `RAMB18E1`. |
| Local weight storage | One logical 16-bit operand register, present in both modes. |
| Modes | Runtime input: `0 = repeated_fetch`, `1 = register_reuse`. |
| Batch length | Positive elaboration generic `N`, default `4`. Supplementary test: `N = 1`. |
| Schedule | Three clock cycles per input in both modes. |
| Simulation clock | Period 10 ns, corresponding to a 100 MHz implementation target. |
| Flow control | Input supplied when requested; output always consumed. No backpressure. |
| Reset | Synchronous, active high. Reset control and datapath state, not the BRAM array. |
| Deployment | Required: one programmed Arty Z7-10 running both modes in the same bitstream. |
| Board control and observation | JTAG VIO controls and an ILA trace, with a small input sequencer. No processor firmware. |
| Measurements | Correct products, processing cycles and actual read/load pulses in simulation and on the board. Energy analysis is a separate optional milestone. |

The first version excludes spatial reuse, multiple PEs, placement sweeps,
neural-network layers, a CUDA implementation, application integration,
complex arithmetic, fixed-point rounding, caches with replacement policies,
AXI, DMA, DDR, Ethernet, an RTOS and a graphical application. These features
are outside V1.

## 4. One circuit, two access policies

```text
CASE A: read and reload before each multiplication

source BRAM -- read each input --> weight register --> multiplier --> y
                                  reload each time        ^
                                                          |
                                                 input register <-- x


CASE B: read and load once, then retain

source BRAM -- read first input --> weight register --> multiplier --> y
                                   hold across inputs      ^
                                                           |
                                                  input register <-- x
```

The physical blocks are identical. A mode bit controls the source-memory
read enable and the weight-register load enable. Mode B deliberately keeps
the same processing slots as A even when it skips an access.

Synthesize and route one design with a runtime-selectable mode. Both runs
use that implementation. Separate constant-mode builds would not control
for differences in placement or resource allocation.

This choice isolates the access policy. A physical-distance experiment would
keep the access policy fixed and vary placement/routing instead. That is a
different valid question, outside V1. Adding a register alone does not reduce
reads; the circuit must retain its contents and suppress the redundant reads.

BRAM and DSP sites are built into the FPGA. VHDL describes their use and the
surrounding control. Vivado chooses mapping and routing. A logically local
register is not proof of a particular physical wire length.

## 5. Core interface and weight lifetime

The core uses the following signals without a control bus:

| Signal | Direction | Contract |
| --- | --- | --- |
| `clk`, `rst` | In | One clock and synchronous reset. |
| `start` | In | One-cycle request, accepted only while idle with `weight_write = 0` and `rst = 0`. |
| `mode` | In, 1 bit | Latch on accepted `start`; unchanged internally for the batch. |
| `weight_addr` | In, 10 bits | Address to write while idle or to latch as the selected read address at `start`. |
| `weight_write` | In | Write request, accepted only while idle with `start = 0` and `rst = 0`. |
| `weight_data` | In, signed 16 bits | Runtime value written to the selected source address. |
| `x` | In, signed 16 bits | Stable before each requested input-capture edge. |
| `sample_request` | Out | High during the READ state; the next rising edge captures `x`. |
| `y` | Out, signed 32 bits | Registered product; meaningful when `product_valid = 1`. |
| `product_valid` | Out | One-cycle pulse after each MUL edge. |
| `busy` | Out | High from accepted `start` until the last MUL edge. |
| `done` | Out | One-cycle pulse with the last valid product. |
| `source_read_enable` | Out, observation only | Expose the actual enable driving the source RAM read, so the testbench can count it. |
| `weight_register_load` | Out, observation only | Expose the actual enable loading `w_reg`, so the testbench can count it. |

The two observation outputs expose the same internal wires used by the
datapath. They must not be independent reconstructions of the expected
schedule. They add no counters or control protocol. During synthesis review,
also confirm the logical source enable reaches the physical RAM enable.

The testbench and required board wrapper must obey this protocol:

1. Reset the controller. Write the chosen BRAM location through
   `weight_write`, `weight_addr` and `weight_data`.
2. Deassert `weight_write`. Present the selected address and mode, then pulse
   `start`. Simultaneous write/start is illegal stimulus.
3. Supply each input before its requested capture edge. There is no
   `input_valid` signal or output stall mechanism in V1.
4. Leave the source memory unchanged while busy. Busy writes and starts are
   not accepted; the testbench should flag them as protocol violations.
5. Consume all products. Once idle, a different weight or address may be
   loaded for the next batch.

Latch the read address and mode at start. Later changes to their external
inputs cannot alter the active batch. `N` is an elaboration generic, so no
runtime batch-length register is needed.

Every batch begins at input index zero and performs a fresh source read in
both modes. The predicate `mode = repeated_fetch OR input_index = 0` is
sufficient to select reads and loads; no multi-entry cache or cross-batch
validity policy is needed. The old register value must not reach a product
before the first READ/LOAD sequence completes.

Apply that predicate only in the relevant state. In Boolean specification
notation:

```text
need_weight = (mode_latched = 0) OR (input_index = 0)
source_read_enable = (rst = 0) AND (state = READ) AND need_weight
weight_register_load = (rst = 0) AND (state = LOAD) AND need_weight
```

Reset suppresses read, write, input-capture and multiplication events. It
returns the controller to idle on the reset edge; no request is accepted on
that edge.

The selected source location must have been written before use. Do not reset
all 1024 entries merely to avoid undefined unused locations; such reset
behavior can prevent BRAM inference. Reset clears pending output-valid and
done signals and aborts any active batch. A new start restarts at index zero.

## 6. Exact clock schedule

Use a controller with `IDLE`, `READ`, `LOAD` and `MUL` states. Edge 0 is the
rising edge accepting `start`. The first processing edge is edge 1.

| Processing edge | Common action | A | B |
| --- | --- | --- | --- |
| READ | Capture `x` into `x_reg`. | Enable source read. | Enable source read only for input zero. |
| LOAD | Advance to multiplication. | Load `w_reg` from `mem_q`. | Load `w_reg` only for input zero. |
| MUL | Register `x_reg * w_reg`; pulse `product_valid`. | Same arithmetic. | Same arithmetic. |

The synchronous memory updates `mem_q` **after** its READ edge. The separate
LOAD edge captures that returned value. The MUL edge then uses the already
loaded operands. Do not consume a newly requested BRAM value on the same
edge that requests it.

In B, later READ and LOAD states still occur. Input capture continues but
the BRAM read and weight load are disabled. The final MUL also asserts
`done` and returns the controller to idle. Otherwise, advance the input index
and return to READ. Default `product_valid` and `done` low on other edges.

For `N = 4`, runtime `w = 3` and `x = [1, 2, -3, 4]`:

| Event | A: repeated fetch | B: register reuse |
| --- | --- | --- |
| Input-capture edges | 1, 4, 7, 10 | 1, 4, 7, 10 |
| Source-read edges | 1, 4, 7, 10 | 1 |
| Weight-register load edges | 2, 5, 8, 11 | 2 |
| Product-valid edges | 3, 6, 9, 12 | 3, 6, 9, 12 |
| Products, in order | 3, 6, -9, 12 | 3, 6, -9, 12 |
| Source reads | 4 | 1 |
| Weight loads | 4 | 1 |
| Valid multiplication results | 4 | 4 |
| Processing interval | 12 clock periods | 12 clock periods |

Enable events are counted at the active edge using the enables valid before
that edge. Registered products and pulses are inspected after signal updates
settle. Drive testbench inputs before the capture edge, for example on the
preceding falling edge, to avoid simulator scheduling races.

At the specified 10 ns clock, the interval from accepted start to the last
product is 120 ns. It excludes source writes and reset. This is specified
simulation timing, not achieved hardware timing or a speedup measurement.

## 7. Simulation checks and waveforms

Keep counters and the golden-result calculation in the testbench initially.
Count the two observation outputs at their active edges. Extra hardware
counters are not required. Check internal `w_reg` retention with a
simulation-only assertion in the core and inspect it in XSim; no tool-specific
hierarchical access is required by the testbench.

Required checks:

- Exact signed products, correct order and exactly `N` valid outputs.
- Same input-capture, multiplication and output schedule in A and B.
- Exactly `N` accepted source reads and weight loads in A; exactly one of
  each in B. Count actual enables, not changes in the weight's numeric value.
- In B, `w_reg` is unchanged between its first load and the final product.
- First valid product appears only after a source read and weight load.
- Completion occurs after exactly `3 * N` clock periods from accepted start.
- No unknown bits in valid outputs. One `done` pulse accompanies the last
  product; there are no extra products afterward.

Run these cases with identical conditions for each A/B pair:

| Test | Stimulus | Expected result |
| --- | --- | --- |
| Baseline | `N=4`, `w=3`, `x=[1,2,-3,4]` | `[3,6,-9,12]`; reads `4/1`. |
| Weight replacement | Write `w=-2` to the same address and start a new batch. | `[-2,-4,6,-8]`; reads `4/1`; no stale `3`. |
| Address selection | Write a different value at a second runtime address and select it for the next batch. | Products use the selected entry; repeat the `N/1` count check. |
| No reuse opportunity | Elaborate `N=1`, `w=3`, `x=[-3]`. | `[-9]`; both modes read and load once. |
| Reset/restart | Reset during a batch, then start a fresh complete batch. | Pending output is discarded; the new batch reloads the weight. |

Treat the `N=1` instance as a separate functional test. Power comparisons
use the same `N=4` mapped design for both modes.

Display these signals in the waveform:

```text
clk, rst, start, mode_latched, state, input_index
weight_write, source_address, source_read_enable, mem_q
weight_register_load, w_reg, sample_request, x_reg
product_valid, y, busy, done
testbench source_read_count, weight_load_count, product_count
```

In B, correct products must continue after the source read-enable pulses
stop. In A, repeated reads of the same address can leave address and data
wires unchanged. Identical visible weight values do not establish identical
memory activity or energy.

Save the assertions log and VCD/WDB waveform. A small screenshot showing
both runs is useful, but the trace and checks remain the reproducible evidence.

## 8. Implementation plan

Steps 1-5 are required for V1. Steps 6-7 are optional energy investigations.
Physical execution in step 5 is required for completion.

| Step | Work and dependency | Deliverable | Acceptance condition |
| --- | --- | --- | --- |
| 1 | Implement the source memory, scalar datapath and four-state controller specified above. | Small RTL plus self-checking testbench. | All Section 7 functional checks pass. |
| 2 | Adapt XSim compilation and waveform capture for these files. Depends on step 1. | One simulation command, logs and waveform with the selected signals. | Four identical products and `4 versus 1` source reads are visible and asserted. |
| 3 | Verify the board, tool/device support and clock/pin constraints. Add the minimal JTAG-controlled wrapper from Section 10 and simulate its command/input sequencing. Depends on step 2. | Board top, constraints, runtime input controls and debug probes. | Actual Z7-10 target confirmed; inputs and weights remain runtime-variable; write/start actions obey the core protocol; the four inputs reach the core in order. |
| 4 | Synthesize, place and route the complete board top, then generate its bitstream and matching debug-probe file. Depends on step 3. | Routed checkpoint, utilization, timing, design-rule reports and programming artifacts. | Experiment BRAM and one scalar arithmetic path retained; runtime modes and actual RAM-enable gating preserved; intended clock constrained and timing met; no unresolved implementation/bitstream-blocking errors. |
| 5 | Program the physical Arty Z7-10 and execute the Section 10 A/B checks. Depends on step 4. | Programming record and exported hardware captures for both weights in both modes. | Identical exact products and 12-cycle processing; A has four reads/loads, B one; changed weight works without rebuilding or reprogramming. |
| 6 | Optionally capture matched activity and estimate power for A and B on the same routed design. Depends on step 4; not a prerequisite for step 5. | Two activity files, annotation reports and power/energy comparison. | Equivalent workloads and intervals; source enable correctly annotated; assumptions and total/component estimates reported. An energy improvement is not required to pass. |
| 7 | Optionally measure voltage/current if suitable instrumentation is available. Depends on step 5. | Measurement setup, raw observations, energy per batch and uncertainty. | Defined electrical boundary and matched trials; below-resolution differences explicitly reported. |

Source layout:

```text
README.md                       specification, execution guide and results
rtl/source_bram.vhd             runtime-writable synchronous source memory
rtl/temporal_reuse.vhd          scalar datapath and small controller
tb/tb_temporal_reuse.vhd        stimulus, expected results and assertions
scripts/run_sim.tcl             compile and run both self-checking XSim tests
scripts/trace.tcl               capture the required signals
rtl/board_control.vhd           request pulses and four-input snapshot/sequencer
tb/tb_board_control.vhd         control checks with simulated core requests
tb/test_capture_checker.py      host-side capture-validator unit tests
rtl/board_top.vhd               required JTAG-controlled board wrapper
constraints/arty_z7_10.xdc      verified board pins and clock constraints
scripts/build_board.tcl         reproducible debug/clock IP setup and full bitstream build
scripts/verify_implementation.tcl routed RAM-enable, clock and timing checks
scripts/hardware_session.sh     private USB/JTAG server and Vivado session
scripts/discover_board.tcl      JTAG target/device discovery without programming
scripts/run_hardware.tcl        explicit-target programming and four A/B captures
scripts/check_capture.py        check exported ILA CSV products, cycles and enables
```

The RTL, testbenches and scripts are implemented. The board-control test
drives simulated `busy` and `sample_request` signals to check command handling
and input sequencing; it does not simulate JTAG or the clock/debug IP.
Generated simulator and Vivado output belong outside tracked source.
Section 11 gives the simulation, build and hardware-session commands.

For step 4, start with synchronous RAM inference and a block-RAM attribute,
then inspect the result. A one-word array, fixed synthesis-time weight or
unused output can let synthesis remove the intended hardware. Runtime write
and address ports must remain reachable and results must remain observable.
If inference does not preserve the intended source BRAM, correct the mapping
or use a small `RAMB18E1` wrapper before making physical-memory claims.

Inspect the actual RAM read-enable pin, not just a fabric counter or an
output-register enable. Inspect where `w_reg` maps: synthesis may pack it
into a BRAM output register or a DSP input register. Record that mapping;
do not claim a separate fabric register or shorter physical wire without
evidence. No manual floorplanning sweep or blanket `DONT_TOUCH` policy is
part of V1.

An isolated out-of-context core build may help diagnose mapping, but it is
not a substitute for implementing the complete board top. Distinguish the
experiment's one source BRAM from extra memories used by the ILA. Report
both core resources and total board-design resources.

## 9. Energy evaluation

The implemented follow-up is documented in
[Temporal reuse: energy experiment](docs/energy-experiment.md), including
software estimation, repeated-run hardware commands and the remaining
electrical-instrumentation requirements. It preserves the original demo.

| Evidence | Supported conclusion |
| --- | --- |
| Functional assertions and counters | Correct products and fewer accepted source reads. |
| VCD/WDB waveforms and SAIF activity | Signal transitions, enable timing and duty over the simulated interval. |
| Activity-annotated Vivado power report | Estimated FPGA power under the declared design, activity and environment. |
| Voltage/current instrumentation | Actual energy at the chosen physical measurement boundary. |

For `N=4`, B has 75% fewer source reads. This is not a claim of 75% less
energy. Memory internals, registers, control, clocking, arithmetic and static
device power all contribute. Register loads of identical data may produce
few visible transitions. Neither RTL toggles nor access counts alone reveal
the energy used inside a BRAM block.

For optional step 6:

1. Use the same routed checkpoint for both modes with identical voltage,
   temperature assumptions, clock, input sequence, batch count and duration.
2. Capture separate A and B SAIF files. SAIF stores switching/activity
   statistics; it is not an electrical measurement. The available flow is
   XSim `open_saif` / `log_saif` / `close_saif`, then Vivado `read_saif` and
   `report_power`.
3. Prefer mapped/post-route activity when supported. Check annotation
   coverage, hierarchy matching and the actual BRAM enable. Behavioral VHDL
   traces may not expose or match all mapped internal signals. Unmatched
   activity can be estimated by the tool and must be reported as such.
4. Capture an equal number of complete batches, including the first weight
   read in every B batch. Do not compare an A batch against a B interval
   that excludes its initial fetch. Report source-loading time separately
   or include identical loading in both total-transaction measurements.
5. Report total estimated power, BRAM contribution and the rest of the
   circuit. Include the extra control activity; do not count only the
   memory component that is expected to improve.

Use consistent units and boundaries:

```text
energy in observation window [J] = average power [W] * window duration [s]
energy per batch [J] = window energy / K completed batches
energy per product [J] = window energy / (K * N)
```

For measured varying voltage/current, window energy is the integral of
`V(t) * I(t)` over that window. Use complete batches and include any start or
idle gaps in the observed duration. The 120 ns processing interval can be
used only with power averaged over that same processing interval; do not
multiply a repeated-run average that includes gaps by 120 ns.

For an isolated-core estimate, label it as such. Do not call it total board
power. Separate processing-only results from complete transactions including
load/reset overhead. Keep a negative or inconclusive energy result: it does
not invalidate the observed reduction in reads.

Physical power measurement requires a suitable voltage/current instrument
or a calibrated shunt with appropriate acquisition, at a documented supply
boundary. An ILA or logic analyzer verifies digital activity, not joules.
Instrument availability and a usable board measurement point remain to be
established; this specification assumes neither.

Repeat batches over a measurable interval. Match clocking, input sequences,
debug activity, peripherals and thermal conditions between A and B. Measure
raw total energy; label any baseline subtraction separately. Longer runs can
improve averaging but do not enlarge the average-power difference. If the
effect is below noise or resolution, report **not resolved by this setup**.
Do not enlarge the design into a PE array merely to obtain a positive result.

## 10. Required physical deployment

### 10.1. Board and debug wrapper

Before building the board image, identify the actual board revision and
confirm the Z7-10 part, supported programming connection and installed tool
support. Check the official board schematic/reference manual and matching
master constraints for the clock source, pin assignments and I/O standards.
Do not guess pins or reuse constraints for the Z7-20.

The physical board is confirmed as an **Arty Z7-10 Rev. D**. Its Ethernet PHY
supplies the 125 MHz PL clock at H16 with LVCMOS33, as shown in Digilent's
[Rev. D schematic](https://files.digilent.com/resources/programmable-logic/arty-z7/arty-z7-d0-sch.PDF).
The H16 assignment also appears in the
[Z7-10 master constraints](https://raw.githubusercontent.com/Digilent/digilent-xdc/master/Arty-Z7-10-Master.xdc).
The project constrains that source to 8 ns and generates a 100 MHz experiment
clock with Clocking Wizard. Recheck the revision before using these
constraints on another board.

Use one 100 MHz experiment clock. If the board source has another frequency,
derive the experiment clock with the appropriate clocking IP and wait for
lock before releasing reset. Constrain the actual source and generated clock;
do not label a different-frequency source as 100 MHz. Keep the experiment,
VIO and ILA in that clock domain. Synchronize asynchronous reset release and
any external controls. Never gate a clock with ordinary combinational logic.

The implemented wrapper samples Clocking Wizard's `locked` output through
two clocked flip-flops initialized to the reset state. Their qualified lock
status combines with the synchronous VIO reset request. This keeps the
source-RAM enables free of asynchronously reset control registers. VIO reset
does not stop the clock or reset the debug cores.

The board wrapper contains:

- VIO (Virtual Input/Output) probes controlled through Vivado Hardware
  Manager over JTAG: reset, weight address/data, write request, mode and
  start request. Turn held debug requests into one-cycle core commands;
  return each request low before issuing the next. Reject simultaneous
  write/start and requests during a batch.
- Four VIO-controlled, runtime-writable signed 16-bit input slots. Load
  `[1,2,-3,4]` for the baseline test. Snapshot these inputs at accepted start
  and use a sequencer to supply each value before `sample_request` captures it.
  Runtime inputs avoid specializing the multiplier to four hardcoded
  constants during synthesis.
- The unchanged temporal-reuse core, with `N=4` and runtime mode selection.
- An ILA (Integrated Logic Analyzer) capturing accepted start, mode, actual
  source-read enable, weight-load enable, input-capture request, input value,
  `product_valid`, `y`, `busy` and `done`. Trigger on accepted start and
  capture every experiment clock through at least two edges after completion.

For four samples, count the actual read/load pulses in the exported ILA trace;
extra hardware counters are not required. Compare signed products against
the known host-side expectations. Do not add another hardware multiplier
just to check the first one. Confirm the probed read-enable wire controls
the mapped BRAM read port; a debug signal with the right count is not enough.

Verify VIO/ILA generation and programming support in the installed tool
before relying on this route. Save their configuration in the build script.
Keep generated IP runs outside tracked source. Missing board access or tool
support leaves deployment incomplete; record the unavailable prerequisite.

### 10.2. Program and run the same physical circuit

1. Generate the full board bitstream and its matching debug-probe file from
   the checked implementation. Record the source revision, tool version,
   target part, clock and hashes of the programming artifacts.
2. Connect and power the actual Arty Z7-10. Identify the target in Hardware
   Manager, program it and verify that programming and debug discovery
   succeed. A successful build without this step is not deployment.
3. Reset the experiment. Load the four input slots. At source address zero,
   write `w=3` through the runtime write interface; then deassert write.
4. Select A. Arm the ILA, issue one start request and save the complete
   capture. Check `[3,6,-9,12]`, four source reads and four weight loads.
5. Select B without reprogramming. Arm and start again. Check the same four
   products, one source read and one weight load. In both modes, valid
   products follow start by 3, 6, 9 and 12 experiment-clock periods.
6. While idle, overwrite the same source entry with `w=-2`. Repeat A and B
   without rebuilding or reprogramming. Check `[-2,-4,6,-8]`, the same timing
   and the same respective `4/1` access counts. This is required evidence
   that the weight is loaded at runtime rather than compiled into the design.
7. Save four labeled hardware captures: A with `3`, B with `3`, A with `-2`
   and B with `-2`. Include a compact table of expected versus observed
   products, read counts, load counts and processing cycles. Keep a screenshot
   for presentation, but retain exported trace data for verification.

Interpret ILA samples consistently: a synchronous probe sees a registered
output on the next sampling edge after the core updates it. Account for that
observation offset when comparing the capture to Section 6; do not confuse
debug observation latency with an extra computation cycle. The fixed core
processing interval remains 12 clock periods from accepted start.

With the implemented ILA's input pipeline depth set to zero, take the
accepted-start sample as offset zero. Input/read enables retain the edge
numbers in Section 6. Registered products appear at sample offsets
`4,7,10,13`; `done` appears at offset 13. The latched mode is valid from
offset 1 because it is updated on the start edge. `scripts/check_capture.py`
checks these offsets, the signed products and the actual enable pulses in
exported ILA CSV files. Checking synthetic or simulated CSVs does not
establish physical execution.

Use the same bitstream and instrumentation for every A/B pair. Programming
volatile FPGA configuration through JTAG is sufficient for V1; autonomous
boot from flash or an SD card is not required. Do not introduce ARM firmware,
network transport or DMA. Board success establishes this scalar experiment,
not application acceleration or measured energy savings.

The runtime-control mechanism is documented in AMD's
[VIO output-probe guide](https://docs.amd.com/r/2024.1-English/ug908-vivado-programming-debugging/Interacting-with-VIO-Core-Output-Probes).
Use the corresponding instructions for the installed Vivado version.

## 11. Software access and execution guide

For interactive VIO controls and fresh ILA waveforms on the programmed board,
see [the live demonstration guide](docs/live-demo.md).

The development baseline is Linux with Vivado/XSim 2018.1 under
`/opt/Xilinx/Vivado/2018.1`. No other project checkout is required. The setup
script, executables and installed command documentation are available.
Core and board-control simulation pass with this installation. The board
build and physical execution have separate acceptance checks. Other tool
versions require a compatibility check. Use one version throughout each A/B
comparison.

### 11.1. Tools

| Tool | Role | Connected board needed? |
| --- | --- | --- |
| `xvhdl` | Compile VHDL sources. | No. |
| `xelab` | Elaborate the compiled testbench into a simulation snapshot. | No. |
| `xsim` | Run the snapshot and inspect simulation waveforms. | No. |
| `vivado` | Synthesis, placement, routing, reports, bitstream generation and Hardware Manager. | Only for hardware access. |
| `hw_server` | Connect Vivado to the physical JTAG programming/debug interface. | Yes, to discover and use the target. |

Use the same installation for all five tools. The required device support
is `xc7z010clg400-1`; verify Clocking Wizard, VIO and ILA availability before
starting the board wrapper. No SDK application, processor firmware or
separate simulator is required by this experiment.

### 11.2. Set up a shell and a separate run directory

Start in this repository's root directory. These are **Bash commands**:

```bash
export REUSE_REPO="$(pwd -P)"
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"

test -f "$REUSE_REPO/README.md" || exit 1
test -r "$REUSE_VIVADO_ROOT/settings64.sh" || exit 1
source "$REUSE_VIVADO_ROOT/settings64.sh" || exit 1

for reuse_tool in vivado xvhdl xelab xsim hw_server; do
    test -x "$REUSE_VIVADO_ROOT/bin/$reuse_tool" || exit 1
done

export REUSE_RUN="$(mktemp -d /tmp/fpga-temporal-reuse.XXXXXX)"
test -d "$REUSE_RUN" || exit 1
cd "$REUSE_RUN" || exit 1
"$REUSE_VIVADO_ROOT/bin/vivado" -version
df -h .
free -h
```

Change `REUSE_VIVADO_ROOT` before this block if the installation is elsewhere.
Use a new run directory for each attempt. `/tmp` is suitable for a short
check but may be cleared on reboot; retain important results in a durable
workspace outside the source tree before relying on them as evidence.

Repeat environment setup in each new terminal or independent shell process;
exported variables are not shared between unrelated shells. Keep environment
dumps and licensing configuration private.

Run Vivado and XSim from the run directory, not the repository root. They
create logs, journals, `.Xil`, simulation databases and checkpoints. Check
for an existing run before starting another heavy process; do not kill an
unrelated process or overwrite its files. Use bounded commands and retain
failed-run logs.

### 11.3. Simulation command sequence

The implemented runner compiles the sources, elaborates the core and
board-control testbenches separately and runs both with assertion and
waveform checks. This entry point is validated with Vivado/XSim 2018.1.
Use the environment and external `REUSE_RUN` from Section 11.2:

```bash
timeout --signal=TERM --kill-after=10s 1200s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log "$REUSE_RUN/simulation_driver.log" \
    -journal "$REUSE_RUN/simulation_driver.jou" \
    -source "$REUSE_REPO/scripts/run_sim.tcl" \
    -tclargs "$REUSE_REPO" "$REUSE_RUN/sim"
```

Each stage has a 180 s timeout. The runner requires both final markers,
`TEMPORAL_REUSE_ALL_TESTS_PASSED` and `BOARD_CONTROL_SIMULATION_PASS`, then
writes `sim/simulation_pass.txt`. It keeps compilation, elaboration and
simulation logs separate and retains `temporal_reuse.vcd/.wdb` and
`board_control.vcd/.wdb`. Existing output is preserved: rerun in a fresh
directory. A zero exit code without the markers, an open GUI or a timeout
does not establish a pass.

To inspect signals, open the debug-enabled snapshot from its run directory:

```bash
cd "$REUSE_RUN/sim" || exit 1
"$REUSE_VIVADO_ROOT/bin/xsim" temporal_reuse_sim -gui
```

The GUI needs a working graphical session; headless simulation does not.
Use Section 7's signal list. `scripts/trace.tcl` records the selected signals
in both WDB and VCD. XSim 2018.1 omits native enumeration, integer and Boolean
objects from VCD; use WDB for controller states, indices and testbench
counters. The logic-vector enables and products are present in both formats.
A saved waveform layout records a view, not proof that assertions passed.

### 11.4. Vivado console, build and device view

From the external run directory, open a **Vivado Tcl console**:

```bash
"$REUSE_VIVADO_ROOT/bin/vivado" -mode tcl \
    -log console.log -journal console.jou
```

These commands belong inside Vivado, not Bash or plain `tclsh`:

```tcl
version -short
get_parts xc7z010clg400-1
help synth_design
help open_hw
```

Stop if the part is unavailable. Use the installed help and command files
under `REUSE_VIVADO_ROOT/doc/eng/man` for this older release rather than
assuming every command in newer documentation exists here.

`scripts/build_board.tcl` accepts the source root and a fresh output directory
as its two arguments. It generates Clocking Wizard, VIO and ILA IP, then
synthesizes, places and routes the complete `board_top`. The batch entry is:

```bash
timeout --signal=TERM --kill-after=10s 1800s \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode batch \
    -log "$REUSE_RUN/build.log" -journal "$REUSE_RUN/build.jou" \
    -source "$REUSE_REPO/scripts/build_board.tcl" \
    -tclargs "$REUSE_REPO" "$REUSE_RUN/build"
```

The 1800 s limit bounds the command; it is not a build-time estimate. The
script checks setup/hold slack, DRC errors and the core's BRAM/DSP counts
and calls `verify_implementation.tcl` before writing the programming artifacts.
That check verifies a shared routed net between the RAM read enable and ILA
probe, the RAM read latency, the 10 ns experiment clock, timing-constraint
coverage and pulse widths. Retain its `implementation_checks.txt` alongside
`check_timing.rpt`, `timing.rpt`, `clocks.rpt` and `mapping.rpt`. Review the
resource mapping and remaining warnings before programming.

On success, the build writes `temporal_reuse.bit`, `temporal_reuse.ltx` and
the `BOARD_BUILD_PASS` marker. It never connects to or programs a board.
Do not expose every internal data/control signal as a package pin by
implementing the scalar core as the board top. Core-only out-of-context
implementation cannot replace the full-board bitstream check.

Retain the routed checkpoint, resource report, `report_timing_summary`,
`check_timing`, `report_drc`, `.bit` and matching `.ltx` file. The GUI entry is:

```bash
"$REUSE_VIVADO_ROOT/bin/vivado" -mode gui \
    -log gui.log -journal gui.jou
```

Inside its Tcl console, use `open_checkpoint` with the actual generated
`.dcp` path, then **Window -> Device** and **Netlist** to inspect BRAM,
arithmetic resources and their connections. This view is the implemented
design model, not evidence that the board executed it.

See [Reopen the Vivado views](docs/vivado-views.md) for the tested cell names,
schematic commands, offline capture replay and live Hardware Manager layout.

### 11.5. Access the physical board through JTAG

This step needs the powered Arty Z7-10, a working USB data/programming
connection and suitable host cable drivers. Tool installation alone does
not establish any of those conditions.

Check for the interface by USB vendor/product ID:

```bash
lsusb -d 0403:6010
```

Bus/device numbers can change after reconnection. The `0403:6010` ID identifies
a USB interface type, not the FPGA part or a unique board. Use Hardware
Manager to identify the intended FPGA target. Read-only JTAG discovery on the
confirmed Rev. D board has returned `arm_dap_0` and `xc7z010_1`; this establishes
device access, not programming or experiment execution.

`scripts/hardware_session.sh` starts `hw_server` and the Vivado client in
one private user/network namespace. This also isolates the auxiliary GDB
listeners opened by the 2018.1 server. Binding the main server to loopback
alone does not isolate those auxiliary listeners. The launcher needs `unshare`,
`ip`, enabled unprivileged user namespaces and existing USB access. It does
not require `sudo` or change host driver configuration.

Run discovery in a fresh external directory:

```bash
export REUSE_DISCOVERY="$(mktemp -d "$REUSE_RUN/discovery.XXXXXX")"
cd "$REUSE_DISCOVERY" || exit 1
bash "$REUSE_REPO/scripts/hardware_session.sh" \
    "$REUSE_REPO/scripts/discover_board.tcl"
```

The launcher retains `hardware_server.log`, `hardware_client.log` and the
Vivado journal, bounds the client run to 300 s and stops its server afterward.
It refuses to overwrite existing session logs. `discover_board.tcl` opens
targets to list their devices, then closes the connection without programming.

On the tested Linux host, Hardware Manager shutdown with the bundled 2018.1
libraries crashed. The launcher preloads the existing host `libudev.so.1`
and `libselinux.so.1` into the Vivado client process; discovery and shutdown
then completed with exit status zero. The default paths are under
`/lib/x86_64-linux-gnu`; `REUSE_HW_PRELOAD` accepts a colon-separated override.
This is a process-local compatibility workaround. No installed library was
replaced and no system package or driver was changed.

Custom hardware Tcl scripts must run through the same launcher so that their
client and server share the private namespace. `open_hw` is the documented
2018.1 entry point:

```tcl
open_hw
connect_hw_server -url localhost:3121
get_hw_targets
```

Identify the intended board in the returned targets. Replace the placeholder
below with that exact target path; do not automatically select the first
attached target:

```tcl
set reuse_target [get_hw_targets {<exact target path>}]
if {[llength $reuse_target] != 1} {
    error "Select exactly one intended hardware target."
}
current_hw_target $reuse_target
open_hw_target $reuse_target
get_hw_devices -of_objects $reuse_target
```

Confirm the FPGA identity before selecting it. Discovery is separate from
programming. At the Section 10 deployment step, select that device in
Hardware Manager, supply the checked `.bit` and matching `.ltx`, then program
it. For automation, the corresponding commands are `current_hw_device`,
`set_property PROGRAM.FILE`, `set_property PROBES.FILE`,
`program_hw_devices` and `refresh_hw_device`. Resolve the intended device
and artifact paths explicitly before issuing the programming command.

Then use VIO for runtime writes/mode/start and ILA for the four required
captures. A and B run sequentially with the same bitstream. Keep cable
serials and complete hardware-target identifiers in local records only.

The implemented `run_hardware.tcl` automates those four runs. After the build
and mapped-implementation checks pass, set `REUSE_TARGET` to the exact target
from the local discovery log. This command programs volatile FPGA
configuration once, loads both runtime weights and saves all four captures:

```bash
export REUSE_TARGET='<exact target path from discovery>'
export REUSE_HARDWARE="$(mktemp -d "$REUSE_RUN/hardware.XXXXXX")"
cd "$REUSE_HARDWARE" || exit 1
bash "$REUSE_REPO/scripts/hardware_session.sh" \
    "$REUSE_REPO/scripts/run_hardware.tcl" "$REUSE_TARGET" \
    "$REUSE_RUN/build/temporal_reuse.bit" \
    "$REUSE_RUN/build/temporal_reuse.ltx" "$REUSE_HARDWARE/captures"
```

The capture output directory must not already exist. The script saves ILA,
CSV and VCD exports plus `programming.txt` with the programming-artifact
hashes. `HARDWARE_CAPTURE_COMPLETE` means the exports were saved; the CSV
checks below establish their arithmetic, timing and access-count results.
The recorded four-run physical execution passed; see Section 13 and
[the saved captures](results/README.md).

From the directory containing the four exported CSV files, check them with:

```bash
cd "$REUSE_HARDWARE/captures" || exit 1
python3 "$REUSE_REPO/scripts/check_capture.py" --radix HEX \
    --run A 3 A_w3.csv --run B 3 B_w3.csv \
    --run A -2 A_wminus2.csv --run B -2 B_wminus2.csv
```

The complete set must produce `FOUR_RUN_CAPTURE_CHECK_PASS`. Each capture
must contain one accepted start and continue through at least relative
sample 14. The checker uses the CSV radix metadata; use `--radix` only when
the export omits that metadata and the probe radix is known. The tested
2018.1 CSV export has no radix row. The hardware script explicitly selects
HEX for every ILA probe, which is why the command above specifies HEX.
Sample indices remain decimal. The mapped `busy` signal appears as `busy_1`;
the checker accepts this verified probe-8 alias.

The host-side validator also has negative tests, separate from the hardware
evidence. Run these from the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tb -p 'test_*.py'
```

They use synthetic CSVs to check that bad products, extra reads, changed
mode, missing samples, unknown output bits, an unverified probe alias and
missing radix information are rejected.

Close this connection when finished, without closing another user's session:

```tcl
close_hw_target $reuse_target
disconnect_hw_server
close_hw
```

If driver installation is actually needed, the 2018.1 installer is under
`REUSE_VIVADO_ROOT/data/xicom/cable_drivers/lin64/install_script/install_drivers/`.
It must run from that directory because it calls sibling scripts. Running
`sudo ./install_drivers` changes system driver/udev configuration: inspect
the failure and obtain administrator approval before doing so. Reconnect
the cable as directed by the installer. Do not run Vivado as root to conceal
a cable-permission problem.

### 11.6. Troubleshooting and evidence hygiene

| Symptom | First check |
| --- | --- |
| Executable missing or wrong version | Installation root, `settings64.sh` and explicit executable paths. |
| Missing library, license or IP/device support | Exact error and that release's supported environment. Do not silently replace system libraries or change tool versions. |
| Elaboration or simulation fails | `xvhdl`/`xelab`/`xsim` logs, source order, top name and assertion messages. |
| No waveform signals | Elaborate with `-debug typical`; use the matching snapshot and actual signal hierarchy. |
| GUI unavailable | Use a desktop session for GUI work; keep batch verification separate. |
| I/O placement fails | Verify `board_top` and actual package-pin constraints; do not add pins for internal core ports. |
| Board not discovered | Power, USB data cable and correct connector; check enumeration with `lsusb -d 0403:6010`, then cable drivers/permissions and hardware-server discovery. USB enumeration alone does not prove JTAG access. |
| Namespace launcher fails | Check `unshare`, `ip`, unprivileged user-namespace support and USB permissions. Retain the error; do not fall back to exposed server listeners. |
| Hardware Manager crashes during shutdown | Check the launcher logs and the two existing host-library paths in `REUSE_HW_PRELOAD`; the documented process-local workaround was validated for discovery. |
| Programmed but no VIO/ILA | Matching `.bit`/`.ltx`, included debug cores, running debug clock and reset/clock-lock state. |

For optional power analysis, the installed command set includes
`open_saif`, `log_saif`, `close_saif`, `read_saif` and `report_power`.
In 2018.1, `read_saif -strip_path` takes the simulation hierarchy without a
leading slash. Check annotation coverage and use Section 9's matched
measurement windows; do not treat an unannotated power report as measured
energy.

Before publication, inspect logs, journals, screenshots and traces for
usernames, hostnames, absolute personal paths, cable serials, license-server
details and credentials. Publish only sanitized evidence needed to reproduce
the result. Keep bulky generated output outside tracked source. Retain any
applicable third-party source license notices if code is later adapted.

## 12. References and reading path

1. **Vivienne Sze, Yu-Hsin Chen, Tien-Ju Yang and Joel S. Emer,
   _Efficient Processing of Deep Neural Networks_.**
   [Book and DOI](https://doi.org/10.1007/978-3-031-01766-7).
   Read Section 5.4.1, printed pages **79-81**, PDF viewer pages **95-97**
   in the referenced edition. Focus on **Figure 5.2d** on printed page 80.
   The figure motivates adding smaller intermediate storage to exploit
   repeated use. This scalar exercise isolates that principle; it does not
   reproduce the figure's full convolution or compare loop orderings.
   Printed page 74 / PDF page 90 provides the memory-energy motivation.
   Page numbering is edition-specific; use section titles to locate other
   editions. Obtain a legal copy through the publisher or a library; the
   book PDF is not a file to publish in this repository.

2. **Jouppi et al., _In-Datacenter Performance Analysis of a Tensor
   Processing Unit_, ISCA 2017.** [Paper](https://arxiv.org/pdf/1704.04760).
   Section 2 describes the TPU matrix unit and stored weight tiles.
   TPU means Tensor Processing Unit; it is a custom ASIC. It provides an
   industrial example of storing and reusing weights, not the exact design
   or measured benefit of this FPGA experiment.

3. **AMD, 7 Series Libraries Guide, RAMB18E1.**
   [Primitive reference](https://docs.amd.com/r/2023.1-English/ug953-vivado-7series-libraries/RAMB18E1).
   Supports the synchronous BRAM and enable-port discussion. Check the
   selected tool version's primitive template when implementing the memory.

4. **AMD, Block RAM Enable Optimization.**
   [Implementation guidance](https://docs.amd.com/r/2022.2-English/ug904-vivado-implementation/Block-RAM-Enable-Optimization).
   Describes power-related enable-logic optimization and its interaction
   with timing. It supports investigating memory-enable policies; it does
   not promise an energy saving for this specific circuit.

5. **AMD, Specifying Switching Activity for the Analysis.**
   [Power-analysis guidance](https://docs.amd.com/r/2021.1-English/ug907-vivado-power-analysis-optimization/Specifying-Switching-Activity-for-the-Analysis?contentId=mF5vvZ83ATAd487sq4TnqQ).
   Explains SAIF annotation, unmatched activity and the benefits of
   post-implementation activity for power estimation.

6. **AMD, Power Analysis Using Vivado Simulator.**
   [Simulation guidance](https://docs.amd.com/r/2023.1-English/ug900-vivado-logic-simulation/Power-Analysis-Using-Vivado-Simulator).
   Explains SAIF export and limitations of behavioral VHDL signal coverage.
   Use the installed tool's documentation for version-specific command syntax.

This teaching experiment applies established data-reuse techniques. In larger
designs, storage capacity, operation order, competing data and control cost
limit which reuse opportunities are worth exploiting. Results from the cited
systems do not establish the performance or energy use of this circuit.

## 13. Results and publication

V1 acceptance requires a documented datapath, reproducible self-checking
simulation, a full board build and execution of both modes on the physical
Arty Z7-10. The saved hardware evidence must show the exact products,
identical processing latency and `4 reads versus 1 read` for both
runtime-loaded weights specified in Section 10.

Simulation alone, isolated synthesis or a successful place-and-route run
does not satisfy these criteria. Measured energy savings are not a
completion requirement; physical execution of temporal reuse is.

Recorded status on 26 September 2026:

```text
core simulation: pass (18 complete cases, Vivado/XSim 2018.1)
board-control simulation: pass (simulated core handshake)
mapped BRAM and enable checks: pass (RAM read enable and DSP weight-load enable)
full board implementation and timing: pass (100 MHz, positive setup/hold/pulse slack)
read-only JTAG device discovery: pass (xc7z010_1)
physical board programming: pass (one final bitstream for all four runs)
physical A/B products, cycle and access checks: pass (both weights, A=4/B=1 reads)
estimated energy difference: core dynamic about -18.65% in B (isolated-core model)
complete-design estimate: device total about -0.247% in B (qualified vendor model)
autonomous physical runs: pass (10 trials, including 10 million batches per trial)
measured board energy difference: unavailable (no voltage/current instrument)
```

[The physical results](results/README.md) include all four raw CSV captures,
mapped-resource checks, reviewed DRC warnings and source/artifact hashes.
The same product/read/load/cycle values in the simulation table below were
also observed on the final programmed board.

The [energy follow-up](results/energy/README.md) records the separate
activity-annotated core estimate and autonomous board variant. Its 14-clock
batch cadence includes launch/drain overhead around the unchanged 12-clock
core computation. It does not replace the original single-batch evidence.

The recorded **simulation** results for the required four-input workloads are:

| Run | Runtime weight | Observed products | Source reads | Weight loads | Processing periods |
| --- | --- | --- | --- | --- | --- |
| A | `3` | `[3,6,-9,12]` | 4 | 4 | 12 |
| B | `3` | `[3,6,-9,12]` | 1 | 1 | 12 |
| A | `-2` | `[-2,-4,6,-8]` | 4 | 4 | 12 |
| B | `-2` | `[-2,-4,6,-8]` | 1 | 1 | 12 |

The core suite also passes address selection, `N=1`, signed extreme operands
and reset/restart in each processing state. It checks latched mode/address,
actual read/load counts and weight-register retention.
The board-control suite passes held-request, simultaneous-request and
busy-request handling, request rearming, input snapshot isolation, capture
order and reset/restart. Logs and WDB/VCD waveforms are retained outside Git;
Section 11.3 regenerates them with both explicit pass markers.

Update this status only from saved evidence. Record the source revision,
tool version, exact commands, inputs, clock, expected results and actual
results. Keep concise result summaries and a representative waveform for
publication; keep bulky generated runs outside Git. Do not report energy
savings based only on access counts or claim hardware execution from a
simulation screenshot.

## 14. Implementation acceptance checklist

The following stages cover V1 from source creation through physical
verification. Sections 3-7 define the circuit contract; Sections 10-11
provide board and tool procedures.

### 14.1. Build and verification stages

1. **Environment.** Check the current source tree, tool version, target-part
   support and clock/debug IP availability. Use a fresh external run directory
   for each attempt. Check USB/JTAG access before scheduling deployment;
   `0403:6010` is an enumeration filter, not a unique target identifier.
   Record missing tool support or uncertain board revision. RTL and simulation
   can proceed independently when the board is unavailable.

2. **Core simulation.** Implement the files in Section 8 using Section 5's
   interface and Section 6's schedule. Run all Section 7 cases, including
   weight replacement, address selection, `N=1` and reset/restart. Acceptance
   requires exact products, actual read/load counts, register retention and
   the specified completion time. Retain assertion logs and waveforms with
   an explicit final pass marker.

3. **Wrapper simulation.** Implement the verified board clock and reset,
   runtime controls, four input slots and sequencer from Section 10.
   Check that a held debug request produces one command, rejected requests
   never reach the core and snapshotted inputs reach it in order. Controlled
   debug stimulus verifies wrapper logic; it does not verify JTAG.
   Store clock/debug IP configuration in the build script.

4. **Full-board implementation.** Synthesize, place and route `board_top`.
   Verify source BRAM inference, its actual read-port enable and the mapped
   weight-register location. Confirm one scalar arithmetic path and both
   runtime modes. Account separately for ILA memory. Check utilization, clock
   constraints, timing and DRCs before generating the `.bit` and matching
   `.ltx`. Retain the routed checkpoint and reports. Core-only
   out-of-context implementation does not meet this requirement.

5. **Physical A/B runs.** Select the exact board/device and artifact paths,
   then program volatile configuration through JTAG. Run Section 10.2's
   four tests sequentially on the same bitstream with runtime inputs
   `x=[1,2,-3,4]`. Load `w=3` for A and B, then overwrite the same address
   with `w=-2` for A and B. Export all four ILA captures and verify products,
   read/load pulses and cycle counts with the sampling offset accounted for.
   If a correction requires a new bitstream, repeat all four captures using
   that final implementation.

6. **Reproducibility.** Document the validated simulation and build commands.
   Keep both entry points separate from board programming. Record the VIO/ILA
   procedure or provide a hardware-run Tcl script with explicit target and
   artifact arguments. Build scripts must not program a board automatically.
   Include a short annotated four-input waveform, expected/observed results
   and references to retained evidence. Update the project status only from
   completed checks.

The source RAM must retain the one-cycle read response assumed by the
READ/LOAD/MUL schedule. An additional RAM output pipeline stage would change
the specified timing. Both modes keep the clock running; read/load enables
control activity without gating clock pulses. The weight register stores
one operand from the selected source address. Unused BRAM entries need not
be initialized.

### 14.2. Required hardware results

The following values are acceptance criteria, not measured results.

| Run | Runtime weight | Expected products | Source reads | Weight loads | Processing periods |
| --- | --- | --- | --- | --- | --- |
| A | `3` | `[3,6,-9,12]` | 4 | 4 | 12 |
| B | `3` | `[3,6,-9,12]` | 1 | 1 | 12 |
| A | `-2` | `[-2,-4,6,-8]` | 4 | 4 | 12 |
| B | `-2` | `[-2,-4,6,-8]` | 1 | 1 | 12 |

Input captures occur at edges `1,4,7,10` and products become valid after
edges `3,6,9,12`, relative to accepted start at edge zero. Edge numbers
denote time, not memory addresses or operand values.

### 14.3. Run records and incomplete tests

Each run record must identify the source, tool version, commands, inputs,
clock and results. Retain simulation logs/waveforms, mapped-enable findings,
implementation reports, programming-artifact hashes and the four hardware
captures. Include a hash manifest of the actual RTL, constraints and scripts,
plus a commit identifier when available; the identifier alone does not cover
uncommitted changes. A commit is not required to run the experiment.

Keep generated output in a durable external directory. Track source,
reproduction scripts and concise result summaries. Apply Section 11.6's
privacy checks before publication.

After a failure, correct the implementation within the V1 constraints and
rerun the affected checks before using downstream results. The assertions,
100 MHz target and source BRAM requirement remain unchanged. If hardware
or tool support is unavailable, record the affected stage, attempted checks,
retained evidence and prerequisite for resuming. Independent checks may
continue; missing physical execution leaves V1 incomplete.

Programming requires an unambiguous board identity and an available hardware
session. Resolve shared-session conflicts before connecting. System/driver
changes require administrator approval. Deployment is limited to volatile
JTAG configuration, with no flash programming. Existing sources and runs
must be preserved. Repository initialization, commits and publication are
separate operations, not build or deployment steps.

Report completion using Section 13's separate status fields and the
four-run results table. Mark power and energy as `not run` unless evaluated
under Section 9's controls. Energy analysis is optional and does not replace
physical verification.
