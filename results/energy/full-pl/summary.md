# Complete implemented PL: qualified matched estimate

Same routed board checkpoint, runtime weight 7 and signed inputs `[1, 2, -3, 4]`. These are partially annotated vendor-model estimates, not measured board power.

| Mode | Source BRAM (mW) | Attributed core (mW) | Repeater incl. core (mW) | Full PL dynamic (mW) | Device total (mW) |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | 0.250395 | 2.106912 | 3.731568 | 128.838844 | 218.280891 |
| B | 0.062599 | 1.789681 | 3.366892 | 128.299031 | 217.741078 |

Each run processes 1024 products in 256 batches over 35840 ns. A/B physical read and load counts are 1024/256. All products, hardware counters, checksum and completion checks pass. The first fetch of every B batch is included.

SAIF matches 8863/8879 physical design nets (99.819800%) in each run. The unmatched nets are unused debug FIFO outputs. The separate DCP-name audit preserves 52 high-Z records in unused vector holes and classifies 553 absent exact-name records. Raw activity, classifications and primitive/JTAG checks are in `summary.json` and the adjacent audit files. These limitations are not silently zeroed or assumed to cancel.

The full-design estimate includes the repeater, VIO, unarmed ILA, debug hub, MMCM and FPGA clock routing. Counter and debug-input switching contribute to the mode delta. Core hierarchy power is Vivado-attributed power inside this instrumented design, not an electrically isolated core measurement. No PS7/ARM workload is instantiated. Regulators and off-chip board power are excluded.

The JTAG simulation boundary is initialized before measurement then held idle. Vivado 2018.1 rejects the requested zero-TCK override and retains the original 33 ns timing-clock model (30.30 MHz). Its JTAG clock power therefore does not represent the constant TCK waveform. Other clocks also use the original routed timing constraints.

Junction temperature is fixed at 25 C, typical process and nominal voltages. Requested ambient is 25 C; the effective reported environment is preserved per case. Activity is mapped functional simulation without routing-delay glitches. Display resolution is 1 nW and is not model accuracy.

Checkpoint SHA-256: `c1d202fd8c38132cd834305d82932439027c8e6abe52c01d90e792a646a4c6ec`
