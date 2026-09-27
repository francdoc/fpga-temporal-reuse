# Reading the code

Follow one weight from source memory to a product, then read the checks and
board connections. No FPGA or Vivado installation is needed to read these files.
For running them, use the [Quick Start](quick-start.md); for interpreting a run,
use [Reading results](reading-results.md).

The baseline computes `y[i] = x[i] * w` for four inputs. A fetches the same
weight before every multiplication. B fetches it once per batch and retains it.
Both modes use the same datapath and clock schedule.

Read the files below in order. Search for the named signals and procedures
within each file; the links are relative to this repository.

## 1. Source memory: where the weight begins

Open [rtl/source_bram.vhd](../rtl/source_bram.vhd). Start with `memory_t`,
then read `process (clk)`.

- The array holds 1024 signed 16-bit values. A batch selects one address.
- At a rising clock edge, `write_enable` permits a write and `read_enable`
  permits a read. The read result becomes available after that edge.
- Without a read enable, `read_data` holds its previous value.
- The array is not reset. The selected entry must be written before use.

An unchanged output does not prove that a read was skipped: repeatedly reading
the same address could return the same value. Follow the enable as well.

## 2. The core: why A and B access memory differently

Open [rtl/temporal_reuse.vhd](../rtl/temporal_reuse.vhd). Its `entity` declares
the interface; its `architecture` contains the registers, connections and control.

First find the access-policy expression:

```vhdl
need_weight <= '1' when mode_latched = '0' or input_index = 0 else '0';
```

Mode A (`0`) needs a fetch for every input. Mode B (`1`) needs one only for
input index zero. Every new batch starts at zero, so B fetches again next batch.
`read_enable` applies this decision in `READ`; `load_enable` applies it in `LOAD`.
The observation outputs expose these actual enables.

Next follow `source_memory`, `mem_q`, `w_reg` and `x_reg`. `mem_q` is the
memory's returned value. `w_reg` holds just one signed 16-bit weight; it loads
from `mem_q` only when enabled and otherwise retains its value, unless reset.
`N=4` means four input samples, not four weights in this register.

Finally read `case state is`:

- `IDLE`: accept a start and latch the mode and selected source address.
- `READ`: capture the input into `x_reg`; request the weight if needed.
- `LOAD`: allow `w_reg` to capture the returned weight if needed.
- `MUL`: register `x_reg * w_reg`, assert `product_valid` and advance or finish.

The weight assignment is above the state case, guarded by `load_enable`.
Both modes still visit `READ`, `LOAD` and `MUL` for every input.

VHDL describes concurrent hardware, not a sequence of software calls. The
memory and core processes respond to the same clock edge; signal assignments
take effect after their processes run. This is why a read requested at one edge
needs a later edge to load `w_reg`. See the [exact clock schedule](../README.md#6-exact-clock-schedule).

## 3. The testbench: how the behavior is checked

Open [tb/tb_temporal_reuse.vhd](../tb/tb_temporal_reuse.vhd). Read
`write_weight`, then `run_batch`, then the calls to those procedures near the end.

`run_batch` drives inputs before their capture edges. At each rising edge it
counts the actual read/load enables, then waits for registered updates before
checking products and valid signals. Its assertions check exact products,
access counts and completion after `3 * N` periods. It also changes the external
mode and address during a batch to check that the core uses its latched values.

The remaining cases cover weight replacement, address selection, signed limits,
reset/restart and `N=1`. Back in the core, `check_weight_retention` asserts that
`w_reg` cannot change without a load or reset. That check is simulation-only.

### Try tracing two inputs yourself

Assume reset is released, the selected source entry already contains `w=3`
and mode B starts a four-input batch. Trace its first two inputs, `1` and `2`.
Edge zero accepts start; the state column below means the state before the edge.

| Edge | State | Action | Result after the edge |
| --- | --- | --- | --- |
| 1 | READ | Capture `x=1`; enable the source read. | `x_reg=1`, `mem_q=3`. |
| 2 | LOAD | Enable the weight-register load. | `w_reg=3`. |
| 3 | MUL | Multiply the stored operands. | `y=3`, `product_valid=1`. |
| 4 | READ | Capture `x=2`; source read disabled. | `x_reg=2`; weight remains available. |
| 5 | LOAD | Weight-register load disabled. | `w_reg` still equals `3`. |
| 6 | MUL | Multiply the stored operands. | `y=6`, `product_valid=1`. |

Why does the second multiplication work without another BRAM read? Find why
`w_reg` receives no new assignment at edge 5, then the expression that suppresses
the second read. Repeat the trace in A: edges 4 and 5 now read and reload, but the
products and their timing stay the same. The batch continues through edge 12.

## 4. Board controls: how four inputs reach the core

Open [rtl/board_control.vhd](../rtl/board_control.vhd). Follow
`accepted_start`, `accepted_write`, `previous_start` and `previous_write`.
Held requests become single accepted commands; conflicting requests and requests
while busy are rejected rather than queued.

At accepted start, the four input slots are copied into `inputs_latched`.
`input_index` selects `x` and advances when `sample_request` captures it.
The core captures the current input at the edge; the next input appears after
the index updates. [tb/tb_board_control.vhd](../tb/tb_board_control.vhd)
checks this wrapper behavior separately.

## 5. Board top: how the blocks connect

Open [rtl/board_top.vhd](../rtl/board_top.vhd). Follow the instances
`clock_generator`, `control_vio`, `commands`, `core` and `capture_ila`.
They connect the experiment clock, runtime controls, input sequencer, arithmetic
core and hardware recorder. Follow the lock/reset logic as well.

VIO supplies controls through JTAG. ILA records the actual read/load enables,
inputs, products and status; it does not calculate the products. The core is
the same one exercised by the testbench, instantiated with `N=4`.

## After the first pass

Use the [script reference](../scripts/README.md) to follow the launchers into
their Tcl runners. For the link between RTL and physical evidence, read
[verify_implementation.tcl](../scripts/verify_implementation.tcl) and
[check_capture.py](../scripts/check_capture.py). The former checks mapped
resources, enable connections and timing; the latter validates exported ILA
CSV captures. A logical register can be packed into a DSP input register rather
than appear as separate fabric flip-flops.

Leave `batch_repeater.vhd`, `energy_board_top.vhd` and the power-analysis scripts
for a second pass through the [energy experiment](energy-experiment.md).
Correct products with fewer reads establish reuse, not measured energy savings.
