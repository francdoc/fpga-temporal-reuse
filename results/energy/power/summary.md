# Matched temporal-reuse power estimate

Register reuse reduces estimated core dynamic power by about 18.65% in this isolated-core model. This is not a measurement of total board power or a claim of the same percentage saving for the complete FPGA design.

Each independently reset run computes 4,096 signed products from 1,024 four-input batches over 143,360 ns at 100 MHz. Inputs are `[1, 2, -3, 4]`; weights 7 and 9 are written at runtime. The initial 300 ns reset/write setup is excluded. Each batch occupies 14 clocks. Every B batch includes its first source fetch.

| Weight | Mode | Source BRAM (mW) | Core dynamic (mW) | Core energy/product (pJ) |
| --- | --- | ---: | ---: | ---: |
| 7 | A: repeated fetch | 0.250387 | 1.068883 | 37.4109 |
| 7 | B: register reuse | 0.062597 | 0.869523 | 30.4333 |
| 9 | A: repeated fetch | 0.250386 | 1.068875 | 37.4106 |
| 9 | B: register reuse | 0.062597 | 0.869516 | 30.4331 |

A performs 4,096 actual BRAM reads and DSP B-register loads; B performs 1,024. The mapped `ENBWREN` and `CEB2` pins are checked at the active clock edges, with `BREG=1`. Both runs have equal clock activity, input/output transitions and DSP operand transitions. SAIF matches all 130/130 design nets in each case. The report uses the same routed checkpoint for A and B.

Source-BRAM dynamic power falls by about 75%. The DSP and clock estimates remain unchanged within each pair. Energy per product is average estimated power multiplied by the matched window duration and divided by the product count.

| Weight | Mode | Isolated-design device static (mW) | Isolated-design device total (mW) |
| --- | --- | ---: | ---: |
| 7 | A | 89.340359 | 90.409242 |
| 7 | B | 89.340359 | 90.209883 |
| 9 | A | 89.340359 | 90.409234 |
| 9 | B | 89.340359 | 90.209875 |

These device totals describe only the isolated design. They exclude the board controller, repeater, VIO, ILA, clock wizard, I/O buffers and board power supplies. Full-board total power was not evaluated.

Vivado 2018.1 uses typical process, a fixed junction temperature of 25 C and nominal Vccint/Vccbram of 1.0 V with Vccaux at 1.8 V. The requested ambient is 25 C; with junction temperature fixed, Vivado reports an effective ambient of 24.0 C. The other reported environmental assumptions are retained in `summary.json` and the power reports.

Internal registered paths meet the 10 ns constraint: setup slack 5.944 ns, hold slack 0.143 ns and pulse-width slack 4.500 ns. This OOC run has 46 input ports and 38 output ports without delay constraints. Boundary routes and global clock delay/skew are not represented, so this is not board timing signoff.

Activity comes from functional simulation of the mapped post-route netlist. Routing-delay glitches are not simulated. Primitive internal power remains a vendor model. Vivado's High confidence classification does not validate physical power accuracy. The microwatt text/XML reports retain 1 nW display resolution; that resolution is not an accuracy claim.

Raw evidence is under `build/` and `weight{7,9}_mode{0,1}/`: SAIF, simulation logs, annotation coverage, primitive switching, standard-W reports and microwatt reports/XML. `summary.json` contains counters, activity, power, energy, environmental assumptions and SHA-256 identities.

Checkpoint SHA-256: `259a163b25b3bce5b0c76149ee7859b7d58d0d6401cb4a5d0ca3dc31cbe473db`
