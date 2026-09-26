# Interactive hardware demo — 26 September 2026

The live Vivado Hardware Manager demo ran on the Arty Z7-10 Rev. D with
Vivado 2018.1. It attached to the already programmed design, discovered its
VIO and ILA and acquired fresh A/B traces. No RTL change, synthesis,
bitstream rebuild or FPGA reprogramming was needed for this session.

This record covers selected runs with weights 7 and 9. They supplement the
[original acceptance runs](../README.md) at weights 3 and -2; they do not
replace that acceptance set. The circuit and programming-artifact provenance
remain the original [implementation checks](../implementation_checks.txt),
[source manifest](../source.sha256) and [programming record](../hardware/programming.txt).

## Observed results

Inputs were `[1, 2, -3, 4]`. Operands were signed 16-bit values and products
were exact signed 32-bit values. Both modes used the same programmed circuit.

| Capture | Weight | Expected and observed products | Source reads | Weight loads | Processing periods |
| --- | --- | --- | --- | --- | --- |
| [A_w7.csv](A_w7.csv) | 7 | `[7, 14, -21, 28]` | 4 | 4 | 12 |
| [B_w7.csv](B_w7.csv) | 7 | `[7, 14, -21, 28]` | 1 | 1 | 12 |
| [A_w9.csv](A_w9.csv) | 9 | `[9, 18, -27, 36]` | 4 | 4 | 12 |
| [B_w9.csv](B_w9.csv) | 9 | `[9, 18, -27, 36]` | 1 | 1 | 12 |

These are full 1024-sample hardware ILA CSV exports, not simulated or
reconstructed traces. Their original acquisition names were `capture_003_A`,
`capture_004_B`, `capture_005_A` and `capture_006_B`, respectively. Only the
filenames changed for publication; [captures.sha256](captures.sha256) records
the byte-identical CSV content.

Accepted start is buffer sample 16. A reads BRAM at samples 17/20/23/26 and
loads the weight register at 18/21/24/27. B reads at 17 and loads at 18 only.
Both show valid products at samples 20/23/26/29. Registered outputs appear
one ILA sample after their update edge; processing still takes 12 periods,
or nominally 120 ns at the configured 100 MHz clock.

The captured enables are the routed BRAM-read and DSP-weight-load signals
checked in the original implementation. The retained weight's internal value
is not directly probed. Reduced accesses are established; energy savings
were not measured or estimated in this demo.

## What the GUI showed

The `hw_ila_1` dashboard was arranged with the acquired waveform above the
VIO controls. The waveform was zoomed around the computation and numeric
operands/results were displayed as signed decimal. VIO exposed the runtime
weight, four inputs, address, mode, reset, write and start controls.

The selected demonstration ended its initial handoff view on B with weight
9 and products `[9, 18, -27, 36]`, leaving Hardware Manager connected for
further use. That is a historical display state, not a claim about current
connectivity or FPGA contents. Subsequent commands can change both.

Numbered waveform tabs preserve each acquisition. The live dashboard controls
can acquire another run; an already displayed waveform is not a continuous
view of the circuit. The physical Device/floorplan view is static as well.

## Recheck the evidence without hardware

From the repository root:

```bash
python3 scripts/check_capture.py --radix HEX \
    --run A 7 results/interactive/A_w7.csv \
    --run B 7 results/interactive/B_w7.csv \
    --run A 9 results/interactive/A_w9.csv \
    --run B 9 results/interactive/B_w9.csv
sha256sum -c results/interactive/captures.sha256
```

Expected: four `PASS` lines followed by `CAPTURE_CHECK_PASS`, plus four
successful hash checks. The checker also explains that this set is not the
separate four-run acceptance set at weights 3 and -2. HEX describes exported
signal values; sample indices are decimal.

During setup, the launcher passed `bash -n`, the Tcl script passed the
`info complete` check and all five capture-checker unit tests passed.
`TCL_SYNTAX_COMPLETE` means complete Tcl command structure, not successful
hardware execution. The fresh ILA captures and arithmetic/enable checks
provide the hardware evidence. The original source-manifest checks remained
unchanged and passing.

## Repeat the live demonstration

Follow [the interactive guide](../../docs/live-demo.md) to open the GUI and
connect the intended board. The implementation uses
[hardware_gui.sh](../../scripts/hardware_gui.sh) for the private GUI/server
session and [interactive_hardware.tcl](../../scripts/interactive_hardware.tcl)
for VIO control, acquisition, display and validation.

In the connected Vivado Tcl Console:

```tcl
reuse_demo 7
reuse_demo 9
```

Each command loads that weight, restores the four standard inputs and
captures A then B without changing the bitstream. `reuse_capture A` and
`reuse_capture B` instead capture the currently configured operands without
writing a new weight or checking arbitrary input values.

Private logs, journals, `.ila` files and screenshots are not published here:
they contain host paths or device identifiers. Temporary GUI-arrangement
helpers are not project dependencies; the guide records the equivalent
dashboard actions. The four reviewed signal-only CSVs are the retained
public evidence.
