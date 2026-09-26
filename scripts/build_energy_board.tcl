# Independent energy variant; never overwrites the original demo bitstream.
# vivado -mode batch -source build_energy_board.tcl -tclargs SOURCE_ROOT FRESH_OUTPUT_DIR
if {$argc != 2} { error "Expected SOURCE_ROOT and FRESH_OUTPUT_DIR" }
set source_root [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {[string first "$source_root/" "$output_dir/"] == 0} { error "Build outside the source tree" }
file mkdir $output_dir
if {[file exists [file join $output_dir project]] || [file exists [file join $output_dir energy_board.bit]]} {
    error "Use a fresh output directory"
}
set_param general.maxThreads 2
create_project energy_board [file join $output_dir project] -part xc7z010clg400-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
foreach name {source_bram temporal_reuse batch_repeater energy_board_top} {
    add_files [file join $source_root rtl ${name}.vhd]
}
add_files -fileset constrs_1 [file join $source_root constraints arty_z7_10.xdc]
set_property top energy_board_top [current_fileset]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name energy_clock
set_property -dict [list CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} CONFIG.USE_RESET {false} \
    CONFIG.USE_LOCKED {true}] [get_ips energy_clock]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name energy_vio
set_property -dict [list CONFIG.C_NUM_PROBE_IN {10} CONFIG.C_NUM_PROBE_OUT {11} \
    CONFIG.C_PROBE_IN0_WIDTH {1} CONFIG.C_PROBE_IN1_WIDTH {1} CONFIG.C_PROBE_IN2_WIDTH {1} \
    CONFIG.C_PROBE_IN3_WIDTH {32} CONFIG.C_PROBE_IN4_WIDTH {32} CONFIG.C_PROBE_IN5_WIDTH {32} \
    CONFIG.C_PROBE_IN6_WIDTH {32} CONFIG.C_PROBE_IN7_WIDTH {32} CONFIG.C_PROBE_IN8_WIDTH {64} \
    CONFIG.C_PROBE_IN9_WIDTH {32} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT0_INIT_VAL {0x1} \
    CONFIG.C_PROBE_OUT1_WIDTH {10} CONFIG.C_PROBE_OUT2_WIDTH {16} \
    CONFIG.C_PROBE_OUT3_WIDTH {1} CONFIG.C_PROBE_OUT4_WIDTH {1} \
    CONFIG.C_PROBE_OUT5_WIDTH {1} CONFIG.C_PROBE_OUT6_WIDTH {16} \
    CONFIG.C_PROBE_OUT7_WIDTH {16} CONFIG.C_PROBE_OUT8_WIDTH {16} \
    CONFIG.C_PROBE_OUT9_WIDTH {16} CONFIG.C_PROBE_OUT10_WIDTH {24}] [get_ips energy_vio]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name energy_ila
set_property -dict [list CONFIG.C_NUM_OF_PROBES {12} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_INPUT_PIPE_STAGES {0} CONFIG.C_PROBE5_WIDTH {16} \
    CONFIG.C_PROBE7_WIDTH {32}] [get_ips energy_ila]
generate_target all [get_ips]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
open_run impl_1

# Hierarchical utilization keeps the experimental datapath separate from the
# repeater/counters and the common VIO/ILA instrumentation.
report_utilization -hierarchical -file [file join $output_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output_dir timing.rpt]
check_timing -verbose -file [file join $output_dir check_timing.rpt]
report_drc -file [file join $output_dir drc.rpt]
report_clocks -file [file join $output_dir clocks.rpt]
report_pulse_width -file [file join $output_dir pulse_width.rpt]
write_checkpoint [file join $output_dir routed.dcp]

set rams [get_cells -hier -filter {NAME =~ repeater/core/* && REF_NAME == RAMB18E1}]
set dsps [get_cells -hier -filter {NAME =~ repeater/core/* && REF_NAME == DSP48E1}]
set all_dsps [get_cells -hier -filter {REF_NAME == DSP48E1}]
if {[llength $rams] != 1} { error "Expected one source RAMB18E1, found [llength $rams]" }
if {[llength $dsps] != 1 || [llength $all_dsps] != 1} { error "Expected one scalar DSP and no instrumentation DSPs" }
if {[get_property READ_WIDTH_B $rams] != 18 || [get_property DOB_REG $rams] != 0} {
    error "Unexpected source RAM width or latency"
}

proc require_shared_net {first_pin second_pin} {
    set first_nets [get_nets -segments -of_objects $first_pin]
    foreach net [get_nets -segments -of_objects $second_pin] {
        if {[lsearch -exact $first_nets $net] >= 0} { return }
    }
    error "Observed enable differs from physical enable: $first_pin / $second_pin"
}
set read_probe [get_pins -of_objects [get_cells capture_ila] -filter {REF_PIN_NAME =~ probe2*}]
set load_probe [get_pins -of_objects [get_cells capture_ila] -filter {REF_PIN_NAME =~ probe3*}]
if {[llength $read_probe] != 1 || [llength $load_probe] != 1} { error "Missing enable probes" }
require_shared_net [get_pins $rams/ENBWREN] $read_probe
require_shared_net [get_pins $dsps/CEB2] $load_probe
if {[get_property BREG $dsps] != 1} { error "Expected the enabled weight register in the scalar DSP" }
set clocks [get_clocks -of_objects [get_pins $dsps/CLK]]
if {[llength $clocks] != 1 || [get_property PERIOD $clocks] != 10.0} { error "Expected the 100 MHz experiment clock" }
foreach delay_type {max min} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
    if {[llength $paths] == 0 || [get_property SLACK $paths] < 0} { error "Timing failed ($delay_type)" }
}
set timing_check [check_timing -verbose -return_string]
if {[regexp {There are [1-9][0-9]* } $timing_check]} { error "check_timing findings require review" }
if {[string match *VIOLATED* [report_pulse_width -return_string]]} { error "Pulse-width violation" }
if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} { error "Unresolved DRC errors" }

set report [open [file join $output_dir implementation_checks.txt] {WRONLY CREAT EXCL}]
puts $report "Core RAM: $rams; READ_WIDTH_B=18 DOB_REG=0"
puts $report "Core DSP: $dsps; total DSP count=1; BREG=1"
puts $report "ILA probes 2/3 share physical source-read/weight-load enable nets"
puts $report "Experiment clock: $clocks; period 10 ns"
puts $report "Setup, hold, check_timing, pulse-width and error-level DRC checks passed"
puts $report "ENERGY_IMPLEMENTATION_CHECKS_PASS"
close $report
write_debug_probes [file join $output_dir energy_board.ltx]
write_bitstream [file join $output_dir energy_board.bit]
puts "ENERGY_BOARD_BUILD_PASS"
close_project
