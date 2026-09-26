# Route one isolated core once; both access policies use this checkpoint.
if {$argc != 2} { error "Expected SOURCE_ROOT FRESH_OUTPUT_DIR" }
set source_root [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
if {[file exists [file join $output_dir routed.dcp]]} { error "Use a fresh output directory" }
file mkdir $output_dir
set_param general.maxThreads 2
create_project -in_memory -part xc7z010clg400-1
read_vhdl [file join $source_root rtl source_bram.vhd]
read_vhdl [file join $source_root rtl temporal_reuse.vhd]
synth_design -top temporal_reuse -mode out_of_context -part xc7z010clg400-1
create_clock -name core_clock -period 10.000 [get_ports clk]
opt_design
place_design
route_design
report_utilization -hierarchical -file [file join $output_dir utilization.rpt]
report_timing_summary -file [file join $output_dir timing.rpt]
set ram [get_cells -hier -filter {REF_NAME == RAMB18E1}]
set dsp [get_cells -hier -filter {REF_NAME == DSP48E1}]
if {[llength $ram] != 1 || [llength $dsp] != 1} { error "Expected one RAMB18E1 and one DSP48E1" }
if {[get_property BREG $dsp] != 1 || [get_property READ_WIDTH_B $ram] != 18} { error "Unexpected BRAM/DSP mapping" }
foreach {pin port} [list $ram/ENBWREN source_read_enable $dsp/CEB2 weight_register_load] {
    set pin_nets [get_nets -segments -of_objects [get_pins $pin]]
    set shared 0
    foreach net [get_nets -segments -of_objects [get_ports $port]] {
        if {[lsearch -exact $pin_nets $net] >= 0} { set shared 1 }
    }
    if {!$shared} { error "$pin is not connected to observed $port" }
}
set mapping [open [file join $output_dir mapping.tsv] {WRONLY CREAT EXCL}]
puts $mapping "ram_cell\t$ram"
puts $mapping "dsp_cell\t$dsp"
puts $mapping "ram_read_pin\t$ram/ENBWREN"
puts $mapping "weight_load_pin\t$dsp/CEB2"
puts $mapping "ram_read_net\t[get_nets -of_objects [get_pins $ram/ENBWREN]]"
puts $mapping "weight_load_net\t[get_nets -of_objects [get_pins $dsp/CEB2]]"
puts $mapping "dsp_breg\t[get_property BREG $dsp]"
puts $mapping "dsp_areg\t[get_property AREG $dsp]"
puts $mapping "ram_loc\t[get_property LOC $ram]"
puts $mapping "dsp_loc\t[get_property LOC $dsp]"
puts $mapping "clock_ns\t10"
close $mapping
set header [open [file join $output_dir tb_power_pins.vh] {WRONLY CREAT EXCL}]
foreach {macro cell pin} [list POWER_READ_PIN $ram ENBWREN POWER_LOAD_PIN $dsp CEB2] {
    set hierarchy dut
    foreach component [split $cell /] { append hierarchy ".\\$component " }
    puts $header "`define $macro $hierarchy.$pin"
}
close $header
write_checkpoint [file join $output_dir routed.dcp]
# Functional simulation of the routed, mapped netlist captures primitive enables.
# It does not model routing-delay glitches or constitute physical rail measurement.
write_verilog -mode funcsim [file join $output_dir core_funcsim.v]
puts "POWER_BUILD_PASS"
close_project
