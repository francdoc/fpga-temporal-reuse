# Interactive FPGA demonstration

Use Vivado Hardware Manager to control the physical board with VIO and capture
its internal signals with ILA. The existing bitstream is sufficient. No RTL
change or synthesis is required.

The [completed demo record](../results/interactive/README.md) includes fresh
physical-board results for weights 7 and 9, all four CSV captures and offline
verification commands. Both A/B pairs passed with four reads in A versus one
in B and identical products in 12 processing periods. It also records the
two-panel GUI setup without publishing personal paths or device identifiers.

[Reopen the Vivado views](vivado-views.md) gives commands for the routed
Device view, BRAM/multiplier schematic, saved capture tabs and connected
Hardware Manager. Offline viewing is separate from starting new FPGA runs.

## Launch

Set `REUSE_REPO`, `REUSE_TARGET`, `REUSE_BIT` and `REUSE_LTX` to the repository,
the exact previously verified JTAG target and the matching tested artifacts.
Do not select an arbitrary attached target. Follow README Section 11 for the
installed Vivado version and device discovery.

Run from a new external directory:

```bash
export REUSE_LIVE="$(mktemp -d /tmp/fpga-reuse-live.XXXXXX)"
cd "$REUSE_LIVE" || exit 1
bash "$REUSE_REPO/scripts/hardware_gui.sh" \
    "$REUSE_TARGET" "$REUSE_BIT" "$REUSE_LTX" "$REUSE_LIVE/captures"
```

The launcher keeps Vivado and its JTAG server in the same private network
namespace. A separately opened Vivado window cannot reach that private server
through its own `localhost`. Use the Hardware Manager window opened by this
launcher. Closing that Vivado process stops its server; the volatile FPGA
configuration remains until power-off or reprogramming. There is no batch
timeout on the GUI. The server has a one-hour inactivity limit.

By default the script attaches without programming. It checks for the matching
ILA and VIO, resets the experiment, writes weight 7 and captures A followed by
B. It verifies their products, enables and cycle counts. If the FPGA has lost
its configuration, close the session and explicitly append `--program` to a
fresh invocation. That programs the specified `.bit` once; A and B still use
the same circuit.

Keep full tool runs, raw logs and unreviewed captures outside Git. They may
contain local paths and JTAG identifiers. Publish only reviewed evidence,
such as the signal-only CSVs in the completed demo record. `/tmp` is temporary;
copy useful results to durable private storage.

## Repeat with a chosen weight

In the **Vivado Tcl Console**, not a shell:

```tcl
reuse_demo 7
reuse_demo 9
reuse_demo -2
```

Each command writes the chosen signed 16-bit weight to source address zero,
sets inputs to `[1, 2, -3, 4]` and captures both modes. Valid weights range from
`-32768` to `32767`. The result checks use these four fixed inputs.

For weight 7, both modes must produce `[7, 14, -21, 28]`. A must have four
BRAM-read and weight-load pulses; B must have one of each. Both take 12
processing periods. A `CAPTURE_CHECK_PASS` followed by `DEMO_COMPLETE` records
the fresh pair's success. The checker distinguishes this pair from the
project's separate four-run acceptance set at weights 3 and -2.

Each acquisition is exported as a numbered `.ila` and `.csv` in the capture
directory. The numbered waveform tabs are preserved recordings of those new
hardware runs, not continuously updating displays. The `hw_ila_1` dashboard
shows the latest uploaded capture and supplies the live ILA controls.

## Arrange the two-panel view

Vivado 2018.1 stores dashboard layout separately from RTL. On a fresh desktop:

1. Select the `hw_ila_1` dashboard. Open its narrow **Dashboard Options** tab.
2. Keep **Waveform** enabled and enable `hw_vio_1`. Status, Settings, Trigger
   Setup and Capture Setup can be hidden to leave space for these two panels.
3. In the VIO panel, click **+**, select the `hw_vio_1` tree and confirm to add
   all 12 probes. The separate `hw_vios` dashboard has its own probe selection.
4. In the waveform, use **Go to Time 0** and zoom until approximately samples
   0–40 are visible. Accepted start is sample 16. Later acquisitions may need
   the view recentered. Widen the Name column if signal names are truncated.

The helper formats inputs, products and VIO operands as signed decimal after
capture. CSV signal values are deliberately exported as HEX for validation.
One-bit controls remain binary. Only interpret `product` when `product_valid`
is high; stale products before start or after completion are not new results.

## Manual controls

Keep `clock_locked=1`, `busy=0`, `cfg_reset=0`, `cfg_start=0` and `cfg_write=0`
before configuring a batch. VIO's output fields control hardware immediately.

1. Set `cfg_addr` and `cfg_weight`, then set `cfg_write` to 1 and back to 0.
   Changing the weight field alone does not write BRAM.
2. Set `cfg_x0` through `cfg_x3`. Leave operands unchanged during a batch.
3. Use `reuse_capture A` or `reuse_capture B` in the Tcl Console. It selects
   the mode, arms the ILA, pulses start, uploads the capture and displays it.
   It does not replace your operands or automatically validate arbitrary
   input values.

To start entirely from the GUI instead: select `cfg_mode=0` for A or 1 for B,
arm **Run Trigger** in the ILA waveform, then set `cfg_start` to 1 and back to
0 in VIO. The configured trigger is `core_start == 1`. Upload/display the new
capture if Vivado does not do so automatically. Do not issue write and start
together. A held request must return to 0 before the next request.

Read `source_read_enable`, `weight_register_load`, `sample_request`, `core_x`,
`product_valid`, `product` and `done`. In B the products continue after the
single read/load pair. The register's internal value is not directly probed.

## Interpretation

The 100 MHz circuit completes the batch in a nominal 120 ns. The ILA records
real FPGA cycles for later inspection; this is neither a simulation nor a
human-speed animation. The capture contains 1024 samples. With start at
sample 16, A reads at 17/20/23/26 while B reads at 17. Product-valid samples
are 20/23/26/29 in both. Registered outputs appear one ILA sampling edge after
the core updates them, so the processing interval remains 12 periods.

No energy measurement is performed by this demo. The existing placement view
remains useful for locating resources but does not display their live activity.
