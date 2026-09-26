# Energy estimates and autonomous FPGA results

Recorded on 26 September 2026 with Vivado/XSim 2018.1 and an Arty Z7-10
Rev. D, part `xc7z010clg400-1`.

Register reuse reduced the modeled dynamic energy of the isolated core by
about **18.65%** for this workload. The physical FPGA also completed matched
repeated workloads with 75% fewer source reads in B. **Electrical board
energy was not measured:** no voltage/current instrument was available.

The isolated-core estimate, complete implemented-design estimate and physical
execution checks have different boundaries. Neither estimate is an electrical
measurement of the programmed board. Instructions are in the
[energy experiment guide](../../docs/energy-experiment.md).

## 1. Matched Vivado estimate

Both modes used one routed, out-of-context `temporal_reuse` checkpoint.
The workload was 1,024 four-input batches at 100 MHz, using runtime
`x = [1, 2, -3, 4]` and weights 7 and 9. Each case produced 4,096 checked
products over 143,360 ns. The 14-clock cadence includes two inter-batch
control slots; the unchanged core itself computes a batch in 12 clocks.
Reset and source writes are outside the activity window in both modes.

| Modeled quantity, weight 7 | A | B |
| --- | ---: | ---: |
| Core dynamic power | 1.068883 mW | 0.869523 mW |
| Source BRAM primitive power, included in core dynamic | 0.250387 mW | 0.062597 mW |
| DSP power, included in core dynamic | 0.286719 mW | 0.286719 mW |
| Core clock power, included in core dynamic | 0.300474 mW | 0.300474 mW |
| Core dynamic energy per product | 37.41 pJ | 30.43 pJ |
| Isolated-design device-static power | 89.340359 mW | 89.340359 mW |
| Isolated-design modeled total power | 90.409242 mW | 90.209883 mW |

The modeled dynamic reduction is about **0.199 mW**, or **6.98 pJ per
product**. The BRAM component decreases by about 75%; the core dynamic
total decreases by about 18.65%. Including the tool's device-static term
reduces the relative difference to about **0.22%**. None of these percentages
is a measured board-power saving. Component rows are parts of the totals,
not additional quantities to sum with them.

Weight 9 gives essentially the same result: core dynamic power is
1.068875 mW in A and 0.869516 mW in B, with 37.41 versus 30.43 pJ per product.
These two operands are correctness checks, not a representative neural-network
workload survey. The extra displayed digits preserve the report values;
they do not express measurement precision or model accuracy.

Energy was calculated from the matching activity window:

```text
E_per_product = P_average * 143360 ns / 4096
             = P_average * 35 ns
```

The [machine-readable summary](power/summary.json) retains component values,
SAIF hashes, checkpoint identity, activity statistics and environmental
settings. [Generated estimate report](power/summary.md) presents both weights.
Its raw-evidence directory names refer to the external run directory, not
files published here.

### Checks supporting the estimate

- All four mapped simulations passed exact-product, order, cycle, input,
  completion and access assertions. A had 4,096 reads/loads; B had 1,024.
- Physical RAMB18E1 `ENBWREN` and DSP48E1 `CEB2` events were checked against
  the logical observation signals. The actual primitive pins have the
  expected activity, not merely a testbench counter.
- Each SAIF spans 143,360,000 ps. Enable duty is `4/14` in A and `1/14` in B.
  Clock duty and input/output data transitions match within each pair.
- Vivado matched all 130 design nets for each case. Clock activity is taken
  from the 10 ns timing constraint; Vivado ignores clock-net SAIF annotation.
- The estimate uses typical process, fixed junction temperature 25°C,
  VCCINT/VCCBRAM 1.0 V and VCCAUX 1.8 V. Although the requested ambient was
  25°C, Vivado reports effective ambient 24.0°C with junction fixed.
- Internal constrained core paths meet the 10 ns requirement: setup slack
  +5.944 ns and hold slack +0.143 ns. This is not board timing signoff:
  out-of-context input/output delays and physical boundary locations are
  unspecified.

Mapped **functional** simulation supplies the activity. It does not include
SDF routing-delay glitches. The isolated core placement is separate from
the physical board variant and excludes its repeater, counters, VIO, ILA,
clock wizard, regulators and peripherals. The generic thermal/board settings
in the tool are model inputs, not a characterization of this Arty board.
The reported High confidence concerns the tool inputs; it does not validate
the power model electrically.

Vivado 2018.1's default watt reports rounded the tiny components too coarsely.
The documented `set_units -power uW` command exposes 1 nW reporting increments.
Changing display units does not improve model accuracy.

## 2. Complete implemented-design estimate

A separate matched simulation used the same routed energy-board checkpoint
that was programmed for the physical tests. It includes the repeater,
counters, VIO, unarmed ILA, debug hub, clock generator and FPGA routing.
Both modes used weight 7 and `[1, 2, -3, 4]`: 256 batches, 1,024 individually
checked products and 35,840 ns. A performed 1,024 reads/loads; B performed
256. The initial fetch of every B batch is included.

| Modeled quantity | A | B |
| --- | ---: | ---: |
| Source RAMB18 primitive | 0.250395 mW | 0.062599 mW |
| Implemented `repeater/core` hierarchy attribution | 2.106912 mW | 1.789681 mW |
| Repeater hierarchy, including that core hierarchy | 3.731568 mW | 3.366892 mW |
| Complete implemented PL dynamic power | 128.838844 mW | 128.299031 mW |
| Device-static term | 89.442047 mW | 89.442047 mW |
| Modeled device total | 218.280891 mW | 217.741078 mW |
| PL dynamic energy per product | 4.509360 nJ | 4.490466 nJ |
| Modeled device-total energy per product | 7.639831 nJ | 7.620938 nJ |

The modeled difference is **0.539813 mW**, or **18.893455 pJ per product**:
about **0.419%** of PL dynamic power and **0.247%** of the modeled device
total. This difference includes instrumentation activity, not just BRAM
reads. Rows overlap and must not be added together.

This estimate has specific limitations:

- Vivado matched **8,863/8,879 physical nets (99.8198%)**. Its displayed
  rounded `100%` is not complete coverage. The 16 unmatched nets are unused
  debug FIFO RAM outputs; checkpoint checks confirmed zero physical loads.
- Native SAIF preserves 52 high-impedance records in unused vector slots.
  All have zero physical drivers and loads. They were not forced to zero.
  The remaining absent exact-name records were classified as constants
  or primitive-name aliases. Critical controls, data and RAM/DSP enable
  activity are known and checked.
- The ILA's arm and capture-write controls stayed zero throughout both
  windows. Nevertheless, Vivado 2018.1 retains the **33 ns JTAG clock
  constraint**, about 30.30 MHz, despite constant TCK in the simulation.
  It rejects the requested zero-activity override and assigns about
  0.840 mW to that clock domain in both reports. This is a retained model
  assumption, not a fully activity-matched estimate of quiet JTAG.
- Synthesis moved some wrapper/checksum logic into `repeater/core`.
  Hierarchy power also includes routed-load attribution. That row is not
  the original scalar RTL in isolation; subtracting it from the repeater
  does not isolate all instrumentation power.
- Activity is mapped functional simulation without SDF glitches. Typical
  process, nominal voltages and a fixed 25°C junction are used; effective
  reported ambient is 22.5°C. The model includes no running ARM/PS7 workload
  and no external regulators or peripherals. The static term is the tool's
  device model, not measured board idle power.

The 256-batch simulation is not the 10-million-batch physical trial. Its
counter activity differs, particularly in upper bits. Do not extrapolate
these numbers into a claimed electrical energy for the long hardware run.

[Generated report](full-pl/summary.md) and
[machine-readable evidence](full-pl/summary.json) retain powers, activity,
coverage classifications, zero-load audits and checkpoint identity. References
to adjacent raw audit files in the generated report refer to the external
run directory. Both mode checks and `BOARD_POWER_RUN_PASS` completed.

## 3. Autonomous execution on the physical FPGA

The energy variant was synthesized, placed, routed and programmed once for
all ten trials. Short A/B checks used weights 7, 9 and -2 with 1, 4 and 16
batches respectively. The sustained trials then ran A–B–B–A with weight 7
and 10,000,000 batches per trial:

| Observation in each sustained trial | A | B |
| --- | ---: | ---: |
| Completed batches | 10,000,000 | 10,000,000 |
| Products | 40,000,000 | 40,000,000 |
| Source reads | 40,000,000 | 10,000,000 |
| Weight loads | 40,000,000 | 10,000,000 |
| Counted clock periods | 140,000,000 | 140,000,000 |
| Nominal window duration | 1.4 s | 1.4 s |
| Signed sum of products | 280,000,000 | 280,000,000 |
| Last product | 28 | 28 |

All ten trials passed. [Hardware readbacks](hardware.csv) preserve their
order; [hardware report](hardware.md) includes the bitstream and probe-file
hashes. Before each trial, reset cleared completion and counters and the
script checked those zeros. Source BRAM survived reset. This prevents a
repeated B trial from passing solely with the preceding B trial's readbacks.

The checksum is an aggregate check, not proof of every output sample.
Per-product checks passed in simulation; the original individual-batch
hardware captures remain separate evidence. No ILA acquisition was armed
during the sustained trials. Host commands supplied configuration/start and
read results after completion. Host wait duration was not used as FPGA time.

The implementation passes at 100 MHz: setup slack +1.380 ns, hold slack
+0.017 ns and pulse-width slack +2.000 ns, with no failing timing endpoints
or `check_timing` findings. The complete instrumented variant uses 2,843
LUTs, 4,709 flip-flops, two RAMB36 blocks, one RAMB18 block and one DSP48.
The two RAMB36 blocks belong to the ILA. The core still has exactly one
source RAMB18E1 and one multiplier. Its logical weight register maps to
the DSP B input register with `BREG=1`.

[Implementation checks](implementation_checks.txt) confirm the physical
enable connections and mapping. The three DRC warning categories are
`DPOP-1` (optional DSP output pipeline), `RTSTAT-10` (unused generated debug
nets) and `ZPS7-1` (PL-only design without PS7). Their disposition is the same
as in the [original board report](../README.md#implemented-circuit-and-timing).
No DRC errors remain. The automatically generated, unannotated board power
report is not used for the A/B estimate.

After these trials, the original interactive bitstream was restored.
Fresh weight-7 A/B captures again passed: `[7, 14, -21, 28]`, reads `4/1`
and 12 core processing periods. Hardware Manager was left connected.

## 4. What this establishes

There is now a quantitative **vendor-model estimate** consistent with the
EPDNN temporal-reuse argument: retaining the operand suppresses source reads
and reduces modeled core dynamic energy for the same useful work. The real
board establishes the access reduction over sustained execution.

Actual electrical savings remain unverified. No voltage/current equipment
was available and no synchronized analog measurement window was established.
The board top has no external run marker. A future measurement needs a safe,
verified supply boundary and a method for aligning integration with the
hardware window. Read/load counters themselves have different activity in
A and B, so their contribution cannot be assumed to cancel.

The estimates therefore cannot establish total board joules or a universal
energy reduction from temporal reuse. The complete-design result supplies
a qualified model of the expected difference, not a validated instrument
sensitivity requirement. Direct electrical measurement remains outstanding.

## 5. Reproduction and provenance

Use the [run guide](../../docs/energy-experiment.md) for simulation, power
estimation, full-board build and physical tests. The power entry point is:

```bash
bash scripts/run_power.sh
```

It creates a fresh external run directory and writes `summary.json` and
`summary.md` only after the four cases pass their checks. Use its printed
directory to retain the full evidence; neither SAIF files nor programming
artifacts are included in Git.

After building the energy-board variant, estimate that exact routed design:

```bash
bash scripts/run_board_power.sh /path/to/energy-build/routed.dcp
```

This offline command writes its own `summary.json` and `summary.md` in a new
external directory. It neither programs nor connects to the FPGA. The guide
provides the full build and physical-run commands.

The baseline was committed first as `3e6f144`. This follow-up was built from
the working tree on top of that commit. [Source hashes](source.sha256)
identify the actual RTL, constraints, scripts and tests. Check them from the
repository root with `sha256sum -c results/energy/source.sha256`.

The baseline regression and capture-validator unit tests passed again.
The repeater regression passed 13 complete cases plus protocol/reset tests,
including signed extrema and 64-bit checksum carry/sign behavior. Explicit
waveform signal selection avoids the observed XSim 2018.1 wildcard-logging
exception. [Verification summary](verification.txt) records the pass markers.
