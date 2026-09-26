# vivado -mode batch -source build_board.tcl -tclargs SOURCE_ROOT EMPTY_OUTPUT_DIR
if {$argc != 2} { error "Expected SOURCE_ROOT and OUTPUT_DIR" }
set source_root [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
file mkdir $output_dir
if {[file exists [file join $output_dir project]]} { error "Use a fresh output directory" }
set_param general.maxThreads 2
create_project temporal_reuse [file join $output_dir project] -part xc7z010clg400-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

foreach name {source_bram temporal_reuse board_control board_top} {
    add_files [file join $source_root rtl ${name}.vhd]
}
add_files -fileset constrs_1 [file join $source_root constraints arty_z7_10.xdc]
set_property top board_top [current_fileset]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name reuse_clock
set_property -dict [list CONFIG.PRIM_IN_FREQ {125.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} CONFIG.USE_RESET {false} \
    CONFIG.USE_LOCKED {true}] [get_ips reuse_clock]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name reuse_vio
set_property -dict [list CONFIG.C_NUM_PROBE_IN {2} CONFIG.C_NUM_PROBE_OUT {10} \
    CONFIG.C_PROBE_IN0_WIDTH {1} CONFIG.C_PROBE_IN1_WIDTH {1} \
    CONFIG.C_PROBE_OUT0_WIDTH {1} CONFIG.C_PROBE_OUT0_INIT_VAL {0x1} \
    CONFIG.C_PROBE_OUT1_WIDTH {10} CONFIG.C_PROBE_OUT2_WIDTH {16} \
    CONFIG.C_PROBE_OUT3_WIDTH {1} CONFIG.C_PROBE_OUT4_WIDTH {1} \
    CONFIG.C_PROBE_OUT5_WIDTH {1} CONFIG.C_PROBE_OUT6_WIDTH {16} \
    CONFIG.C_PROBE_OUT7_WIDTH {16} CONFIG.C_PROBE_OUT8_WIDTH {16} \
    CONFIG.C_PROBE_OUT9_WIDTH {16}] [get_ips reuse_vio]

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name reuse_ila
set_property -dict [list CONFIG.C_NUM_OF_PROBES {12} CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_INPUT_PIPE_STAGES {0} CONFIG.C_PROBE5_WIDTH {16} \
    CONFIG.C_PROBE7_WIDTH {32}] [get_ips reuse_ila]
generate_target all [get_ips]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
open_run impl_1

report_utilization -hierarchical -file [file join $output_dir utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $output_dir timing.rpt]
check_timing -verbose -file [file join $output_dir check_timing.rpt]
report_drc -file [file join $output_dir drc.rpt]
report_clocks -file [file join $output_dir clocks.rpt]
write_checkpoint [file join $output_dir routed.dcp]

foreach delay_type {max min} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
    if {[llength $paths] == 0} { error "No $delay_type timing paths" }
    if {[get_property SLACK $paths] < 0} { error "Timing failed ($delay_type)" }
}
set errors [get_drc_violations -filter {SEVERITY == Error}]
if {[llength $errors]} { error "Unresolved DRC errors: $errors" }

# Restrict these checks to the experimental core, excluding ILA storage.
set rams [get_cells -hier -filter {NAME =~ core/* && REF_NAME == RAMB18E1}]
set dsps [get_cells -hier -filter {NAME =~ core/* && REF_NAME == DSP48E1}]
if {[llength $rams] != 1} { error "Expected one source RAMB18E1, found [llength $rams]" }
if {[llength $dsps] != 1} { error "Expected one scalar DSP48E1, found [llength $dsps]" }
set mapping [open [file join $output_dir mapping.rpt] w]
puts $mapping "Source RAM: $rams"
puts $mapping "Scalar multiplier: $dsps"
foreach pin [get_pins -of_objects $rams -filter {REF_PIN_NAME == ENARDEN || REF_PIN_NAME == ENBWREN || REF_PIN_NAME == REGCEAREGCE || REF_PIN_NAME == REGCEB}] {
    puts $mapping "RAM pin $pin: [get_nets -of_objects $pin]"
    puts $mapping "  startpoints: [all_fanin -flat -startpoints_only -to $pin]"
}
puts $mapping "Weight-register fabric cells: [get_cells -quiet -hier -filter {NAME =~ core/w_reg*}]"
puts $mapping "DSP input register configuration: AREG=[get_property AREG $dsps] BREG=[get_property BREG $dsps]"
close $mapping

source [file join $source_root scripts verify_implementation.tcl]
verify_implementation $output_dir
write_debug_probes [file join $output_dir temporal_reuse.ltx]
write_bitstream [file join $output_dir temporal_reuse.bit]
puts "BOARD_BUILD_PASS"
close_project
