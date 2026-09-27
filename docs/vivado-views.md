# Reopen the Vivado views

Commands for the Vivado 2018.1 views used during the physical demonstration
on 26 September 2026. Two separate Vivado windows were open:

| Window or tab | Contents | Needs a connected board? |
| --- | --- | --- |
| Device | Placed FPGA resources from the routed checkpoint. | No. |
| Netlist and Cell Properties | Design hierarchy, selected cells and their mapped sites. | No. |
| Temporal reuse - BRAM and multiplier | Schematic of the source BRAM and scalar multiplier. | No. |
| Hardware Manager | Connected target, FPGA and debug cores. | Yes, for live access. |
| `hw_ila_1` | Latest uploaded hardware waveform and ILA controls. | Yes, for new acquisitions. |
| `hw_vios` or VIO panel inside `hw_ila_1` | Runtime operands, mode, commands and status. | Yes. |
| `capture_001_A` through `capture_014_B` | Separate saved waveform tabs from the recorded session. | No, when reopened from `.ila` files. |
| Tcl Console | Commands for the corresponding Vivado session. | Depends on the command. |

The Device view is static. A saved ILA waveform is a recording of physical
hardware, not a simulation or a continuously updating activity display.
Reopening either one does not run the FPGA.

## 1. Set paths in Bash

Start in the repository root. Replace the two `/path/to/...` values below:
`REUSE_BUILD` is the path printed as `BUILD_DIR` by a successful `build.sh`;
`REUSE_CAPTURE_DIR` is the path printed as `CAPTURES_DIR` by `hardware.sh run`,
or an interactive session's capture directory. These are values to copy,
not variables automatically exported by the launchers. The capture directory
must contain `.ila` files, not just the published CSV exports.

```bash
export REUSE_REPO="$(pwd -P)"
export REUSE_VIVADO_ROOT="${REUSE_VIVADO_ROOT:-/opt/Xilinx/Vivado/2018.1}"
export REUSE_BUILD="/path/to/tested/build-directory"
export REUSE_CAPTURE_DIR="/path/to/hardware-session/captures"
export REUSE_HW_PRELOAD="${REUSE_HW_PRELOAD:-/lib/x86_64-linux-gnu/libudev.so.1:/lib/x86_64-linux-gnu/libselinux.so.1}"

test -f "$REUSE_REPO/README.md" || exit 1
source "$REUSE_VIVADO_ROOT/settings64.sh" || exit 1
```

The recorded build directory was named `build-final`; it contains
`routed.dcp`, `temporal_reuse.bit` and `temporal_reuse.ltx`. The interactive
session stores `capture_*.ila` beside `capture_*.csv` in its `captures`
directory. These generated artifacts remain outside the repository.

The preload setting reproduces the Linux library setup used by the working
GUI launcher. It is host-specific, not an FPGA requirement. Check those
library paths before using it on a different machine. A graphical desktop
session is required. Repeat setup in each new terminal; shell exports do
not update an already running Vivado process.

## 2. Routed Device, Netlist, properties and schematic

In Bash, open a new offline viewer from a fresh external directory:

```bash
test -r "$REUSE_BUILD/routed.dcp" || exit 1
export REUSE_VIEW_RUN="$(mktemp -d /tmp/fpga-reuse-views.XXXXXX)"
cd "$REUSE_VIEW_RUN" || exit 1
env LD_PRELOAD="$REUSE_HW_PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}" \
    "$REUSE_VIVADO_ROOT/bin/vivado" -mode gui \
    -log viewer.log -journal viewer.jou
```

Then enter this in that window's **Tcl Console**:

```tcl
open_checkpoint [file join $::env(REUSE_BUILD) routed.dcp]
set reuse_blocks [get_cells {core/source_memory/memory_reg core/y_reg}]
if {[llength $reuse_blocks] != 2} {
    error "Expected the source BRAM and scalar multiplier cells"
}
select_objects $reuse_blocks
show_schematic -name {Temporal reuse - BRAM and multiplier} $reuse_blocks
```

These are the exact cell names used in the tested routed design. If a later
build changes them, inspect its Netlist rather than selecting unrelated cells.
No synthesis, implementation or programming command is needed.

Use the **Window** menu to show **Device**, **Netlist**, **Properties** and
**Tcl Console** if any are hidden. Selecting a cell in Netlist or Device
updates its Cell Properties. Switch between the Device tab and the named
schematic tab to compare physical placement with logical connectivity.
`show_schematic` requires GUI mode; batch/Tcl-only mode does not display it.

If this checkpoint is already open, skip `open_checkpoint` and run only the
cell-selection and `show_schematic` commands. Do not load a new checkpoint
into the connected Hardware Manager window just to obtain a floorplan.

## 3. Reopen all saved hardware waveform tabs without the board

For the four baseline captures from `hardware.sh run`, use a new offline GUI
launched as in Section 2 and enter this in its **Vivado Tcl Console**:

```tcl
open_hw
set reuse_capture_dir $::env(REUSE_CAPTURE_DIR)
foreach reuse_name {A_w3 B_w3 A_wminus2 B_wminus2} {
    set reuse_snapshot [read_hw_ila_data [file join $reuse_capture_dir ${reuse_name}.ila]]
    display_hw_ila_data $reuse_snapshot
}
```

Skip `open_hw` if Hardware Manager is already open. No server connection or
board is required. These filenames differ from the interactive demo's
`capture_*.ila` names below; choose the example matching your saved files.

Use a new offline GUI launched as in Section 2, or an existing offline viewer.
Do not run the live-demo launcher merely to read an old capture. For the
numbered interactive captures, use this alternative in the
**Vivado Tcl Console**:

```tcl
open_hw
set reuse_capture_dir $::env(REUSE_CAPTURE_DIR)
set reuse_files [lsort -dictionary [glob -nocomplain \
    -directory $reuse_capture_dir capture_*.ila]]
if {[llength $reuse_files] == 0} {
    error "No saved .ila captures found in $reuse_capture_dir"
}
foreach reuse_file $reuse_files {
    set reuse_snapshot [read_hw_ila_data $reuse_file]
    display_hw_ila_data $reuse_snapshot
    set reuse_numbers [get_waves core_x product]
    if {[llength $reuse_numbers]} {
        set_property radix dec $reuse_numbers
    }
}
```

`open_hw` opens Hardware Manager; it does not connect to a server or program
the FPGA. Skip it if Hardware Manager is already open. This loop restores
one waveform tab per recording, including all 14 files from the session
when pointed at that session's capture directory. Use the tab overflow list
to reach tabs that do not fit across the window.

If an existing GUI was launched without `REUSE_CAPTURE_DIR`, replace the
environment-based assignment with
`set reuse_capture_dir {/path/to/interactive-session/captures}`. A checkpoint
is not needed for waveform replay; the `.ila` files are sufficient.

To open only one file instead of the loop:

```tcl
set reuse_snapshot [read_hw_ila_data \
    [file join $reuse_capture_dir capture_003_A.ila]]
display_hw_ila_data $reuse_snapshot
set reuse_numbers [get_waves core_x product]
if {[llength $reuse_numbers]} { set_property radix dec $reuse_numbers }
```

In the recorded session, `capture_003_A` / `capture_004_B` are the verified
weight-7 pair and `capture_005_A` / `capture_006_B` are the weight-9 pair.
Numbers restart in each new session, so retain the associated run record.

For a dataset already loaded, list its actual name and display it directly:

```tcl
get_hw_ila_datas
display_hw_ila_data [get_hw_ila_datas capture_003_A]
```

Repeated imports can add name suffixes. The value returned by
`read_hw_ila_data` identifies the correct new object without guessing its name.
An imported dataset is independent of the live ILA core. Its tab may be
labelled with a `.wcfg` suffix; that is its waveform configuration.

The published `.csv` files can be checked offline with
[`check_capture.py`](../scripts/check_capture.py), but are not inputs to
`read_hw_ila_data`. Retain the `.ila` archives to reopen the Vivado waveforms.

## 4. Reopen the connected Hardware Manager and live controls

If the working Hardware Manager window is still connected, use it. Do not
start a second session competing for the same JTAG target.

To replace a closed session, set the exact previously verified target in
Bash, then launch the existing helper:

```bash
export REUSE_TARGET='<exact verified JTAG target>'
export REUSE_BIT="$REUSE_BUILD/temporal_reuse.bit"
export REUSE_LTX="$REUSE_BUILD/temporal_reuse.ltx"
export REUSE_LIVE="$(mktemp -d /tmp/fpga-reuse-live.XXXXXX)"
cd "$REUSE_LIVE" || exit 1
bash "$REUSE_REPO/scripts/hardware_gui.sh" \
    "$REUSE_TARGET" "$REUSE_BIT" "$REUSE_LTX" "$REUSE_LIVE/captures"
```

**This starts new FPGA work.** By default the launcher does not reprogram
the FPGA, but it resets the experiment, writes weight 7 and the four inputs,
then runs and checks both A and B. It leaves Hardware Manager connected.
Append `--program` only when explicitly intending to load the specified
bitstream, for example after the board has lost its configuration.

The launcher places Vivado and its server in one private network namespace.
A separately launched viewer cannot connect to that server through its own
`localhost`. Use the window opened by the helper for VIO and live ILA access.
Closing that GUI stops its server. The server has a one-hour inactivity limit.

In the connected session, this displays the most recently uploaded data
without acquiring anything new:

```tcl
get_hw_ila_datas
display_hw_ila_data [get_hw_ila_datas hw_ila_data_1]
```

`hw_ila_data_1` is the live upload dataset name in the recorded session;
`hw_ila_1` is the ILA core/dashboard, not a dataset. Use the actual name from
`get_hw_ila_datas` if a new session differs. This command does not replace
the saved numbered snapshots.

To execute a **new** A/B comparison, use the connected window's Tcl Console:

```tcl
reuse_demo 7
```

For manual operands, `reuse_capture A` and `reuse_capture B` each run a new
acquisition without writing a replacement weight. These commands are defined
by [`interactive_hardware.tcl`](../scripts/interactive_hardware.tcl), not
built into Vivado. See [the live-demo guide](live-demo.md) for their contracts.

## 5. Restore the combined ILA/VIO layout

The commands above reopen the design and waveform data. The tested 2018.1
dashboard arrangement uses these GUI steps:

1. In Hardware Manager, expand the connected FPGA to see `hw_ila_1` and
   `hw_vio_1`. Select the `hw_ila_1` dashboard tab.
2. Open its narrow **Dashboard Options** tab. Enable **Waveform** and
   `hw_vio_1`. Hide Status, Settings, Trigger Setup and Capture Setup if
   needed to reproduce the uncluttered two-panel view.
3. In the VIO panel, click **+**, select the `hw_vio_1` probe tree and confirm
   to add all 12 probes. The separate `hw_vios` dashboard has its own probe
   selection; adding probes there does not populate the combined panel.
4. Keep the waveform above VIO. Widen the Name columns to read full signal
   names. Open **Window -> Tcl Console** for the helper commands.
5. In the waveform, use **Go to Time 0**, then zoom to about samples 0–40.
   Start is sample 16. The full capture has 1024 samples, so the active
   calculation is hard to see when the whole capture fits in the window.

In the connected helper session, restore signed operand display with:

```tcl
reuse_live::format_controls
```

For a selected saved waveform, use `get_waves core_x product` and the
`radix dec` command from Section 3, or select those signals and choose signed
decimal in the waveform's radix menu. Controls stay binary. Formatting does
not change stored samples or the HEX CSV validation format. Editing a VIO
output value, unlike changing its radix, can change the running hardware.

Dashboard docking, probe-table columns and waveform zoom are GUI layout
settings. The commands here do not claim to recreate their exact screen
coordinates. No additional RTL or bitstream is needed for this arrangement.

## 6. Preserve a chosen waveform layout

With the desired waveform current, save its configuration to a new durable
private path in the Tcl Console:

```tcl
set reuse_layout {/path/to/private/reuse-view.wcfg}
if {[file exists $reuse_layout]} { error "Choose a new layout filename" }
save_wave_config $reuse_layout
```

Later, after importing the matching capture as `reuse_snapshot`:

```tcl
display_hw_ila_data -wcfg $reuse_layout $reuse_snapshot
```

A `.wcfg` stores waveform display configuration, not captured samples or
the entire desktop/dashboard layout. Keep the `.ila` recording too. Do not
depend on temporary `.Xil` session paths for reproducible reopening.

| File | Role in reopening |
| --- | --- |
| `.dcp` | Restores the implemented circuit, placement and routing. |
| `.bit` + matching `.ltx` | Programming image and probe mapping for live debug. |
| `.ila` | Saved hardware acquisition that Vivado can reopen offline. |
| `.wcfg` | Optional saved waveform presentation. |
| `.csv` | Exported signal samples for independent checks. |

Keep tool logs, unreviewed screenshots and raw GUI artifacts outside Git.
They can contain local paths or cable identifiers. The commands were checked
against the working launch scripts, saved session logs and installed Vivado
2018.1 command help.
