# Program the explicitly selected board and capture four sequential A/B runs.
# Invoke through hardware_session.sh from a fresh external run directory.
if {$argc != 4} { error "Expected TARGET BITSTREAM PROBES OUTPUT_DIR" }
set target_name [lindex $argv 0]
set bitstream [file normalize [lindex $argv 1]]
set probes_file [file normalize [lindex $argv 2]]
set output_dir [file normalize [lindex $argv 3]]
foreach artifact [list $bitstream $probes_file] {
    if {![file isfile $artifact] || [file size $artifact] == 0} {
        error "Missing programming artifact: $artifact"
    }
}
if {[file exists $output_dir]} { error "Capture output directory must not exist" }
file mkdir $output_dir

proc probe_named {core name} {
    set matches [get_hw_probes -of_objects $core -filter "NAME =~ *$name*"]
    if {[llength $matches] != 1} { error "Expected one $name probe, found $matches" }
    return $matches
}
proc drive {vio name value} {
    set_property OUTPUT_VALUE $value [probe_named $vio $name]
    commit_hw_vio $vio
}

open_hw
connect_hw_server -url localhost:3121
set target [get_hw_targets $target_name]
if {[llength $target] != 1} { error "Select exactly one intended target" }
if {[get_property NAME $target] ne $target_name} { error "Use the exact target name, not a wildcard" }
current_hw_target $target
open_hw_target $target
set device [get_hw_devices -of_objects $target -filter {NAME == xc7z010_1}]
if {[llength $device] != 1} { error "Expected one xc7z010_1 device on selected target" }
current_hw_device $device
set_property PROGRAM.FILE $bitstream $device
set_property PROBES.FILE $probes_file $device
program_hw_devices $device
refresh_hw_device $device
set vio [get_hw_vios -of_objects $device]
set ila [get_hw_ilas -of_objects $device]
if {[llength $vio] != 1 || [llength $ila] != 1} { error "Expected one VIO and one ILA" }
foreach probe [get_hw_probes -of_objects $vio -filter {TYPE == vio_output}] {
    set_property OUTPUT_VALUE_RADIX HEX $probe
}
foreach probe [get_hw_probes -of_objects $ila] {
    set_property DISPLAY_RADIX HEX $probe
}

# One configuration and programming operation for all four runs.
foreach {name value} {cfg_reset 1 cfg_addr 000 cfg_weight 0003 cfg_write 0 cfg_mode 0 cfg_start 0 cfg_x0 0001 cfg_x1 0002 cfg_x2 FFFD cfg_x3 0004} {
    set_property OUTPUT_VALUE $value [probe_named $vio $name]
}
commit_hw_vio $vio
refresh_hw_vio $vio
if {[get_property INPUT_VALUE [probe_named $vio clock_locked]] ne "1"} {
    error "Experiment clock is not locked"
}
drive $vio cfg_reset 0
set_property CONTROL.DATA_DEPTH 1024 $ila
set_property CONTROL.TRIGGER_POSITION 16 $ila
set_property CONTROL.WINDOW_COUNT 1 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b1 [probe_named $ila core_start]

foreach {weight label} {0003 w3 FFFE wminus2} {
    drive $vio cfg_weight $weight
    drive $vio cfg_write 1
    drive $vio cfg_write 0
    foreach {mode mode_label} {0 A 1 B} {
        drive $vio cfg_mode $mode
        run_hw_ila $ila
        drive $vio cfg_start 1
        drive $vio cfg_start 0
        wait_on_hw_ila -timeout 10 $ila
        set data [upload_hw_ila_data $ila]
        set base [file join $output_dir ${mode_label}_${label}]
        write_hw_ila_data ${base}.ila $data
        write_hw_ila_data -csv_file ${base}.csv $data
        write_hw_ila_data -vcd_file ${base}.vcd $data
        puts "CAPTURE_SAVED: ${mode_label}_${label}"
    }
}
set manifest [open [file join $output_dir programming.txt] w]
puts $manifest "Tool: [version -short]"
puts $manifest "Part: xc7z010clg400-1"
puts $manifest "Board: Arty Z7-10 Rev. D (operator identification)"
puts $manifest "Clock: 100 MHz derived from 125 MHz"
puts $manifest "Bitstream SHA256: [lindex [exec sha256sum $bitstream] 0]"
puts $manifest "Probes SHA256: [lindex [exec sha256sum $probes_file] 0]"
puts $manifest "One programming operation; captures in order A_w3 B_w3 A_wminus2 B_wminus2"
puts $manifest "ILA CSV signal radix: HEX (sample indices are decimal)"
close $manifest
close_hw_target $target
disconnect_hw_server
close_hw
puts "HARDWARE_CAPTURE_COMPLETE: validate the CSVs with check_capture.py"
