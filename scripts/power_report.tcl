# Start Vivado independently for each case so no activity survives from another.
if {$argc != 3} { error "Expected CHECKPOINT SAIF OUTPUT_DIR" }
set checkpoint [file normalize [lindex $argv 0]]
set saif [file normalize [lindex $argv 1]]
set output_dir [file normalize [lindex $argv 2]]
set_param general.maxThreads 2
open_checkpoint $checkpoint
set_operating_conditions -process typical -junction_temp 25 -ambient_temp 25 -voltage {Vccint 1.0 Vccaux 1.8 Vccbram 1.0}
read_saif -strip_path tb_power_temporal_reuse/dut -out_file [file join $output_dir annotation.rpt] $saif
report_switching_activity -signal_rate -static_probability -toggle_rate [get_nets -hier] -file [file join $output_dir switching.rpt]
report_power -verbose -hier all -l 1000 -file [file join $output_dir power.rpt]
# The 2018.1 text/XML formatter otherwise rounds component power to milliwatts.
# Reporting in microwatts preserves nanowatt resolution without changing activity.
set_units -power uW
report_power -hier all -l 1000 -file [file join $output_dir power_micro_watts.rpt]
report_power -hier all -l 1000 -format xml -file [file join $output_dir power.xml]
set evidence [open [file join $output_dir activity_properties.txt] {WRONLY CREAT EXCL}]
proc write_properties {channel object} {
    set available [list_property $object]
    foreach property {NAME REF_NAME LOC BEL AREG BREG MREG PREG READ_WIDTH_A READ_WIDTH_B WRITE_WIDTH_A WRITE_WIDTH_B DOA_REG DOB_REG REF_PIN_NAME DIRECTION} {
        if {[lsearch -exact $available $property] >= 0} { puts $channel "$property\t[get_property $property $object]" }
    }
}
set primitive_pins {}
foreach cell [get_cells -hier -filter {REF_NAME == RAMB18E1 || REF_NAME == DSP48E1}] {
    puts $evidence "CELL $cell"
    write_properties $evidence $cell
    foreach pin [get_pins -of_objects $cell -filter {REF_PIN_NAME == ENBWREN || REF_PIN_NAME == ENARDEN || REF_PIN_NAME == CEB2 || REF_PIN_NAME == CLK || REF_PIN_NAME == CLKBWRCLK || REF_PIN_NAME == CLKARDCLK}] {
        lappend primitive_pins $pin
        puts $evidence "PIN $pin"
        write_properties $evidence $pin
        foreach net [get_nets -of_objects $pin] {
            puts $evidence "NET $net"
            write_properties $evidence $net
        }
    }
}
close $evidence
report_switching_activity -signal_rate -static_probability -toggle_rate $primitive_pins -file [file join $output_dir primitive_switching.rpt]
puts "POWER_REPORT_PASS"
close_design
