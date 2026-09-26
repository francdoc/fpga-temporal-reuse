# Export the actual routed board checkpoint for controlled mapped simulation.
if {$argc != 2} { error "Expected CHECKPOINT FRESH_OUTPUT_DIR" }
set checkpoint [file normalize [lindex $argv 0]]
set output_dir [file normalize [lindex $argv 1]]
file mkdir $output_dir
if {[file exists [file join $output_dir board_funcsim.v]]} { error "Use a fresh export directory" }
set_param general.maxThreads 2
open_checkpoint $checkpoint
set blackboxes [get_cells -quiet -hier -filter {IS_BLACKBOX == 1}]
if {[llength $blackboxes]} { error "Unresolved simulation cells: $blackboxes" }
set ram [get_cells -hier -filter {NAME =~ repeater/core/* && REF_NAME == RAMB18E1}]
set dsp [get_cells -hier -filter {NAME =~ repeater/core/* && REF_NAME == DSP48E1}]
if {[llength $ram] != 1 || [llength $dsp] != 1 || [get_property BREG $dsp] != 1} { error "Unexpected core mapping" }
set header [open [file join $output_dir tb_power_board_pins.vh] {WRONLY CREAT EXCL}]
foreach {macro cell pin} [list BOARD_READ_PIN $ram ENBWREN BOARD_LOAD_PIN $dsp CEB2] {
    set hierarchy dut
    foreach component [split $cell /] { append hierarchy ".\\$component " }
    puts $header "`define $macro $hierarchy.$pin"
}
close $header
set mapping [open [file join $output_dir mapping.tsv] {WRONLY CREAT EXCL}]
puts $mapping "ram_cell\t$ram"
puts $mapping "dsp_cell\t$dsp"
puts $mapping "ram_read_pin\t$ram/ENBWREN"
puts $mapping "weight_load_pin\t$dsp/CEB2"
puts $mapping "checkpoint\t$checkpoint"
puts $mapping "checkpoint_sha256\t[lindex [exec sha256sum $checkpoint] 0]"
puts $mapping "blackbox_count\t[llength $blackboxes]"
puts $mapping "design_net_count\t[llength [get_nets -hier]]"
set bscan [get_cells -hier -filter {REF_NAME == BSCANE2}]
if {[llength $bscan] != 1} { error "Expected exactly one JTAG boundary primitive" }
puts $mapping "bscan_cell\t$bscan"
foreach name {cfg_reset cfg_write cfg_mode cfg_start cfg_addr cfg_weight cfg_batches cfg_x0 cfg_x1 cfg_x2 cfg_x3 clk clock_locked run_busy run_done completed_batches product_count read_count load_count cycle_count checksum last_product} {
    set nets [get_nets -quiet ${name}*]
    if {![llength $nets]} { error "Missing expected stimulus/observation net: $name" }
    puts $mapping "$name\t$nets"
}
close $mapping
set nets_file [open [file join $output_dir design_nets.txt] {WRONLY CREAT EXCL}]
foreach net [get_nets -hier] { puts $nets_file $net }
close $nets_file
set scopes [concat [list ""] [get_cells -hier -filter {IS_PRIMITIVE == 0}]]
# Enumerate only mapped hierarchy scopes, not recursive unisim implementation
# arrays. XSim 2018.1 recursive get_objects is prohibitively slow on this design.
set scopes_file [open [file join $output_dir activity_scopes.txt] {WRONLY CREAT EXCL}]
foreach scope [lsort -unique $scopes] { puts $scopes_file "/tb_power_board/dut/$scope" }
close $scopes_file
set pins_file [open [file join $output_dir activity_pins.txt] {WRONLY CREAT EXCL}]
foreach pin [concat [list $ram/ENBWREN $ram/CLKBWRCLK $dsp/CEB2 $dsp/CLK] [get_pins -of_objects $bscan]] {
    puts $pins_file "/tb_power_board/dut/$pin"
}
foreach cell [get_cells -hier -filter {REF_NAME == CFGLUT5}] {
    foreach port {CDI CDO CE CLK I0 I1 I2 I3 I4 O5 O6} { puts $pins_file "/tb_power_board/dut/$cell/$port" }
}
foreach cell [get_cells -hier -filter {REF_NAME == RAM32M}] {
    foreach port {ADDRA ADDRB ADDRC ADDRD DIA DIB DIC DID DOA DOB DOC DOD WCLK WE} { puts $pins_file "/tb_power_board/dut/$cell/$port" }
}
close $pins_file
report_clocks -file [file join $output_dir clocks.rpt]
write_verilog -mode funcsim [file join $output_dir board_funcsim.v]
puts "BOARD_POWER_EXPORT_PASS"
close_design
