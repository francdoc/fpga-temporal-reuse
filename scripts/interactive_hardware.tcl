# Attach to the existing design by default. --program explicitly reloads the bitstream.
# Keep this Hardware Manager session open for manual VIO/ILA use after the demo.
if {$argc < 4 || $argc > 5} { error "Expected TARGET BITSTREAM PROBES OUTPUT_DIR ?--program?" }
namespace eval reuse_live {
    variable vio
    variable ila
    variable target
    variable output_dir
    variable sequence 0
    variable checker [file join [file dirname [info script]] check_capture.py]
}
set reuse_target_name [lindex $argv 0]
set reuse_bitstream [file normalize [lindex $argv 1]]
set reuse_probes_file [file normalize [lindex $argv 2]]
set reuse_live::output_dir [file normalize [lindex $argv 3]]
if {$argc == 5 && [lindex $argv 4] ne "--program"} { error "Unsupported option" }
foreach artifact [list $reuse_bitstream $reuse_probes_file] {
    if {![file isfile $artifact] || [file size $artifact] == 0} { error "Missing artifact: $artifact" }
}
if {[file exists $reuse_live::output_dir]} { error "OUTPUT_DIR must be new" }
file mkdir $reuse_live::output_dir

proc reuse_live::probe {core name} {
    set found {}
    foreach p [get_hw_probes -of_objects $core] {
        set leaf [file tail [get_property NAME $p]]
        regsub {\[[0-9:]+\]$} $leaf {} leaf
        if {$leaf eq $name || ($name eq "busy" && $leaf eq "busy_1")} { lappend found $p }
    }
    if {[llength $found] != 1} { error "Expected exactly one $name probe" }
    return $found
}

proc reuse_live::format_controls {} {
    variable ila
    variable vio
    foreach name {core_x product} { set_property DISPLAY_RADIX SIGNED [probe $ila $name] }
    foreach name {cfg_weight cfg_x0 cfg_x1 cfg_x2 cfg_x3} {
        set_property OUTPUT_VALUE_RADIX SIGNED [probe $vio $name]
    }
}

proc reuse_live::drive {name value} {
    variable vio
    set p [probe $vio $name]
    set_property OUTPUT_VALUE_RADIX HEX $p
    set_property OUTPUT_VALUE $value $p
    commit_hw_vio $vio
}

proc reuse_live::idle {} {
    variable vio
    refresh_hw_vio $vio
    if {[get_property INPUT_VALUE [probe $vio clock_locked]] ne "1"} {
        error "Experiment clock is not locked"
    }
    if {[get_property INPUT_VALUE [probe $vio busy]] ne "0"} {
        error "Core is busy; no new command was issued"
    }
}

proc reuse_live::arm {} {
    variable ila
    # CSV validation has an explicit HEX contract; GUI formatting is restored later.
    foreach p [get_hw_probes -of_objects $ila] { set_property DISPLAY_RADIX HEX $p }
    set_property CONTROL.DATA_DEPTH 1024 $ila
    set_property CONTROL.TRIGGER_POSITION 16 $ila
    set_property CONTROL.WINDOW_COUNT 1 $ila
    set_property TRIGGER_COMPARE_VALUE eq1'b1 [probe $ila core_start]
    run_hw_ila $ila
}

proc reuse_capture {mode} {
    # Capture the current runtime operands. Does not write a new weight.
    set mode [string toupper $mode]
    if {$mode ni {A B}} { error "Use reuse_capture A or reuse_capture B" }
    reuse_live::idle
    reuse_live::drive cfg_start 0
    reuse_live::drive cfg_write 0
    reuse_live::drive cfg_mode [expr {$mode eq "B"}]
    reuse_live::arm
    reuse_live::drive cfg_start 1
    reuse_live::drive cfg_start 0
    wait_on_hw_ila -timeout 10 $reuse_live::ila
    set data [upload_hw_ila_data $reuse_live::ila]
    display_hw_ila_data $data
    # Preserve a separate dataset for each run: the live upload object is overwritten.
    set base [file join $reuse_live::output_dir [format "capture_%03d_%s" [incr reuse_live::sequence] $mode]]
    write_hw_ila_data ${base}.ila $data
    write_hw_ila_data -csv_file ${base}.csv $data
    set snapshot [read_hw_ila_data ${base}.ila]
    display_hw_ila_data $snapshot
    set numbers [get_waves core_x product]
    if {[llength $numbers]} { set_property radix dec $numbers }
    reuse_live::format_controls
    display_hw_ila_data $data
    puts "FRESH_HARDWARE_CAPTURE: $mode -> ${base}.csv"
    return ${base}.csv
}

proc reuse_demo {weight} {
    # One convenience command for the fixed-input A/B lesson, with a chosen weight.
    if {![string is integer -strict $weight] || $weight < -32768 || $weight > 32767} {
        error "Weight must be a signed 16-bit integer (-32768..32767)"
    }
    set weight [expr {int($weight)}]
    reuse_live::idle
    foreach {name value} {cfg_reset 0 cfg_start 0 cfg_write 0 cfg_addr 000 cfg_x0 0001 cfg_x1 0002 cfg_x2 FFFD cfg_x3 0004} {
        set p [reuse_live::probe $reuse_live::vio $name]
        set_property OUTPUT_VALUE_RADIX HEX $p
        set_property OUTPUT_VALUE $value $p
    }
    commit_hw_vio $reuse_live::vio
    reuse_live::drive cfg_weight [format %04X [expr {$weight & 65535}]]
    reuse_live::drive cfg_write 1
    reuse_live::drive cfg_write 0
    set a [reuse_capture A]
    set b [reuse_capture B]
    puts [exec python3 $reuse_live::checker --radix HEX --run A $weight $a --run B $weight $b]
    puts "DEMO_COMPLETE: weight=$weight; both fresh captures checked; Hardware Manager remains connected."
}

open_hw
connect_hw_server -url localhost:3121
set reuse_live::target [get_hw_targets $reuse_target_name]
if {[llength $reuse_live::target] != 1 || [get_property NAME $reuse_live::target] ne $reuse_target_name} {
    error "Use the exact intended hardware target, not a wildcard"
}
current_hw_target $reuse_live::target
open_hw_target $reuse_live::target
set reuse_device [get_hw_devices -of_objects $reuse_live::target -filter {NAME == xc7z010_1}]
if {[llength $reuse_device] != 1} { error "Expected one xc7z010_1 device" }
current_hw_device $reuse_device
set_property PROGRAM.FILE $reuse_bitstream $reuse_device
set_property PROBES.FILE $reuse_probes_file $reuse_device
if {$argc == 5} { program_hw_devices $reuse_device }
refresh_hw_device $reuse_device
set reuse_live::vio [get_hw_vios -of_objects $reuse_device]
set reuse_live::ila [get_hw_ilas -of_objects $reuse_device]
if {[llength $reuse_live::vio] != 1 || [llength $reuse_live::ila] != 1} {
    error "Expected one matching VIO and ILA; check configuration and .ltx before proceeding"
}
# Establish known idle controls before accepting interactive commands.
foreach {name value} {cfg_reset 1 cfg_start 0 cfg_write 0 cfg_mode 0} {
    set p [reuse_live::probe $reuse_live::vio $name]
    set_property OUTPUT_VALUE_RADIX HEX $p
    set_property OUTPUT_VALUE $value $p
}
commit_hw_vio $reuse_live::vio
reuse_live::drive cfg_reset 0
reuse_live::idle
reuse_demo 7
puts "LIVE_DEMO_READY: enter reuse_demo 9 for another weight, or reuse_capture A / reuse_capture B after manual VIO writes."
puts "Keep this window open. Closing Vivado releases this session's private hardware server."
