# Physical FPGA results — 26 September 2026

This page records the original baseline session. For a fresh run, use
[Reading results](../docs/reading-results.md). The later
[operator-run reproduction](launcher-checks.md#operator-run-reproduction)
records the Bash workflow and optional core-power estimate separately.

V1 passed on an Arty Z7-10, operator-identified PCB Rev. D, using Vivado/XSim
2018.1 (build 2188600). The final design was programmed through JTAG and all
four runs below used that same bitstream. Both weights and all four inputs
were supplied through VIO at runtime. No processor firmware was used.

## Observed results

Inputs were `[1, 2, -3, 4]`, with signed 16-bit operands and exact signed
32-bit products. The expected and observed products matched in every run.

| Capture | Weight | Expected and observed products | Source reads | Weight loads | Processing periods |
| --- | --- | --- | --- | --- | --- |
| [A_w3.csv](hardware/A_w3.csv) | 3 | `[3, 6, -9, 12]` | 4 | 4 | 12 |
| [B_w3.csv](hardware/B_w3.csv) | 3 | `[3, 6, -9, 12]` | 1 | 1 | 12 |
| [A_wminus2.csv](hardware/A_wminus2.csv) | -2 | `[-2, -4, 6, -8]` | 4 | 4 | 12 |
| [B_wminus2.csv](hardware/B_wminus2.csv) | -2 | `[-2, -4, 6, -8]` | 1 | 1 | 12 |

Each CSV is a full 1024-sample ILA export, not a reconstructed waveform.
Accepted start is buffer sample 16. Relative to that sample, reads occur at
`[1,4,7,10]` in A and `[1]` in B; weight loads at `[2,5,8,11]` and `[2]`.
Registered valid products are observed at `[4,7,10,13]` in both modes.
The ILA samples pre-edge values, so these correspond to multiplication
edges `[3,6,9,12]`. This is 12 processing periods, not 13. At the configured
100 MHz clock, 12 periods correspond to a nominal 120 ns. The oscillator
frequency was not independently measured.

Recheck the saved hardware evidence without a board or Vivado, from the
repository root:

```bash
python3 scripts/check_capture.py --radix HEX \
    --run A 3 results/hardware/A_w3.csv \
    --run B 3 results/hardware/B_w3.csv \
    --run A -2 results/hardware/A_wminus2.csv \
    --run B -2 results/hardware/B_wminus2.csv
```

Expected final marker: `FOUR_RUN_CAPTURE_CHECK_PASS`. The checker verifies
actual enable pulses, input values, signed products, mode, busy/done timing
and the absence of extra events. HEX applies to signal values; buffer/window
sample indices are decimal.

## Implemented circuit and timing

The full placed-and-routed board design passed before programming:

- Part: `xc7z010clg400-1`.
- Source clock: 125 MHz on H16, LVCMOS33; derived experiment clock: 100 MHz.
- Setup slack: **+3.982 ns**; hold slack: **+0.053 ns**; pulse-width slack:
  **+2.000 ns**. No failing timing endpoints.
- `check_timing`: all reported issue counts zero, including unconstrained
  internal endpoints and missing clocks.
- Core: 13 LUTs, 21 flip-flops, one RAMB18E1 and one DSP48E1.
- Complete instrumented design: 1796 LUTs, 3056 flip-flops, two RAMB36
  blocks, one RAMB18 block and one DSP48 block. The two RAMB36 blocks belong
  to the ILA, not the source-weight table.

The source BRAM is at `RAMB18_X0Y4`; the multiplier is at `DSP48_X0Y4`.
Vivado mapped the logical weight register into the DSP's B input register
(`BREG=1`). The input register uses `AREG=1`; the multiplication result uses
`MREG=1`, with `PREG=0`. This remains one multiplier and one logical retained
weight, not a separate cache or a second arithmetic path.

[Implementation checks](implementation_checks.txt) verify that ILA probe 2
shares the physical BRAM `ENBWREN` net and probe 3 shares the DSP `CEB2`
weight-load net. The BRAM has no optional output pipeline register
(`DOB_REG=0`), preserving the specified READ/LOAD/MUL schedule. Counts are
therefore observations of the hardware enables, not inferred counters.

The final bitstream has zero DRC errors and three warning categories:

| Warning | Disposition for this experiment |
| --- | --- |
| `DPOP-1` | Recommends DSP output pipelining. The mapped result already uses MREG; adding PREG would change the specified schedule. Timing passes without it. |
| `RTSTAT-10` | Unused/no-load nets in generated debug IP. The required probes were discovered and all four complete captures passed. |
| `ZPS7-1` | Flags the absence of PS7. This is a PL-only, volatile JTAG demonstration with an external PL clock, not an autonomous Zynq boot image. Processor/boot integration is untested. |

An initial build also warned about asynchronous control reaching the BRAM
enables. The final wrapper uses clocked lock qualification; those warnings
are absent from the tested final build. The duplicate `sys_clk` constraint
warning comes from Clocking Wizard and the board XDC both defining the same
8 ns source clock; the final clock report confirms 8 ns input and 10 ns
experiment clocks. Warnings were reviewed, not globally suppressed.

## Simulation and provenance

[Simulation excerpts](simulation.txt) record 18 passing core cases, including
changed weights, changed address, `N=1`, signed extremes and reset/restart in
each processing state. The separate board-control test passes command
rearming/rejection and input snapshot/sequencing checks. It uses simulated
core handshake signals; it is not a simulation of JTAG or vendor clock/debug
IP. The full physical captures provide the board-level integration evidence.

The capture-validator unit tests also pass:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tb -p 'test_*.py'
sha256sum -c results/source.sha256
```

The implementation was built from the working tree based on README-only
commit `a70c858`. [source.sha256](source.sha256) identifies the actual RTL,
constraints, scripts and tests, including files not committed at build time.
The final bitstream and matching debug-probe hashes are in
[programming.txt](hardware/programming.txt). New builds need not be
byte-identical because generated artifacts can include build metadata.

Full build reports, checkpoints, simulation WDB/VCD files, hardware ILA/VCD
exports and unsanitized tool logs are retained in the external run directory.
The repository keeps the full CSV captures and compact evidence without
personal paths, hostnames or cable identifiers. Reproduce fresh simulation,
implementation and deployment using [README Sections 10–11](../README.md#10-required-physical-deployment).

The original four-run acceptance session closed normally and its server was
stopped. At that point the FPGA was left programmed and idle after mode B
with weight -2. This is the initial session's handoff state, not the current
board state. The configuration is volatile; it does not survive a power cycle.

## Interactive follow-up demo

The later [interactive demonstration](interactive/README.md) attached to the
same programmed circuit without rebuilding or reprogramming. Fresh A/B pairs
with weights 7 and 9 passed: four reads/loads in A versus one in B, identical
products and 12 processing periods. Its record includes the combined VIO/ILA
view, repeatable commands and four additional CSV captures with checksums.
The GUI was left connected for further use; that historical handoff does not
establish present connectivity.

## What was not established

The physical result is **75% fewer source reads for the same four products
and the same processing latency**. It is not a speedup or an energy-saving
measurement. No matched A/B SAIF power analysis or electrical energy
measurement was performed. Vivado's automatically generated vectorless power
report is not used as A/B evidence. No spatial reuse, placement sweep,
neural-network inference or autonomous boot was tested.
