# Functional verification of the autonomous repeater. No analog power measurement.
# CLI: hardware_session.sh THIS.tcl TARGET BIT LTX NEW_OUTPUT_DIR
# GUI: set reuse_energy_library_only 1; source THIS.tcl; then call reuse_energy_run.
namespace eval reuse_energy {}

proc reuse_energy::probe {core name} {
    set matches {}
    foreach probe [get_hw_probes -of_objects $core] {
        set leaf [file tail [get_property NAME $probe]]
        regsub {\[[0-9:]+\]$} $leaf {} leaf
        if {$leaf eq $name} { lappend matches $probe }
    }
    if {[llength $matches] != 1} { error "Expected exactly one $name probe: $matches" }
    return $matches
}

proc reuse_energy::drive {vio name value} {
    set p [probe $vio $name]
    set_property OUTPUT_VALUE_RADIX HEX $p
    set_property OUTPUT_VALUE $value $p
    commit_hw_vio $vio
}

proc reuse_energy::read_unsigned {vio name} {
    set value [get_property INPUT_VALUE [probe $vio $name]]
    regsub -nocase {^0x} $value {} value
    if {![regexp {^[0-9a-fA-F]+$} $value]} { error "Invalid HEX readback for $name: $value" }
    return [expr "0x$value"]
}

proc reuse_energy::expect {actual expected description} {
    if {$actual != $expected} { error "$description: observed $actual, expected $expected" }
}

proc reuse_energy_run {device bitstream probes_file output_dir} {
    if {[llength $device] != 1 || [get_property NAME $device] ne "xc7z010_1"} {
        error "Select the verified xc7z010_1 device explicitly"
    }
    foreach artifact [list $bitstream $probes_file] {
        if {![file isfile $artifact] || [file size $artifact] == 0} { error "Missing artifact: $artifact" }
    }
    if {[file exists $output_dir]} { error "Use a new results directory" }
    file mkdir $output_dir
    current_hw_device $device
    set_property PROGRAM.FILE [file normalize $bitstream] $device
    set_property PROBES.FILE [file normalize $probes_file] $device
    program_hw_devices $device
    refresh_hw_device $device
    set vio [get_hw_vios -of_objects $device]
    set ila [get_hw_ilas -of_objects $device]
    if {[llength $vio] != 1 || [llength $ila] != 1} { error "Expected one energy VIO and ILA" }
    foreach p [get_hw_probes -of_objects $vio] {
        if {[get_property TYPE $p] eq "vio_input"} {
            set_property INPUT_VALUE_RADIX HEX $p
        }
    }
    foreach {name value} {
        cfg_reset 1 cfg_addr 000 cfg_weight 0007 cfg_write 0 cfg_mode 0 cfg_start 0
        cfg_x0 0001 cfg_x1 0002 cfg_x2 FFFD cfg_x3 0004 cfg_batches 000001
    } {
        set p [reuse_energy::probe $vio $name]
        set_property OUTPUT_VALUE_RADIX HEX $p
        set_property OUTPUT_VALUE $value $p
    }
    commit_hw_vio $vio
    refresh_hw_vio $vio
    reuse_energy::expect [reuse_energy::read_unsigned $vio clock_locked] 1 "clock lock"
    reuse_energy::drive $vio cfg_reset 0

    set rows {}
    # Short arithmetic/reload checks followed by sustained runs in A-B-B-A order.
    # ILA is deliberately not armed. Counts are read only after completion.
    foreach {weight batches modes} {7 1 {A B} 9 4 {A B} -2 16 {A B} 7 10000000 {A B B A}} {
        refresh_hw_vio $vio
        reuse_energy::expect [reuse_energy::read_unsigned $vio run_busy] 0 "idle before write"
        reuse_energy::drive $vio cfg_weight [format %04X [expr {$weight & 65535}]]
        reuse_energy::drive $vio cfg_write 1
        reuse_energy::drive $vio cfg_write 0
        reuse_energy::drive $vio cfg_batches [format %06X $batches]
        foreach mode $modes {
            # Clear sticky completion and counters before every trial. In particular,
            # the second B trial must not pass using the first B trial's readbacks.
            # Reset leaves the source BRAM contents and VIO configuration intact.
            reuse_energy::drive $vio cfg_start 0
            reuse_energy::drive $vio cfg_write 0
            reuse_energy::drive $vio cfg_reset 1
            reuse_energy::drive $vio cfg_reset 0
            refresh_hw_vio $vio
            foreach name {run_busy run_done completed_batches product_count read_count load_count cycle_count checksum} {
                reuse_energy::expect [reuse_energy::read_unsigned $vio $name] 0 "reset $name"
            }
            reuse_energy::drive $vio cfg_mode [expr {$mode eq "B"}]
            reuse_energy::drive $vio cfg_start 1
            # Start can stay high: the hardware accepts one edge, not one run per clock.
            # Wait longer than 14*K clocks. This host wait is NOT an energy window.
            after [expr {int(ceil(14.0 * $batches / 100000.0)) + 250}]
            refresh_hw_vio $vio
            reuse_energy::expect [reuse_energy::read_unsigned $vio run_busy] 0 "completed run"
            reuse_energy::expect [reuse_energy::read_unsigned $vio run_done] 1 "sticky completion"
            set completed [reuse_energy::read_unsigned $vio completed_batches]
            set products [reuse_energy::read_unsigned $vio product_count]
            set reads [reuse_energy::read_unsigned $vio read_count]
            set loads [reuse_energy::read_unsigned $vio load_count]
            set cycles [reuse_energy::read_unsigned $vio cycle_count]
            set checksum [reuse_energy::read_unsigned $vio checksum]
            if {$checksum >= (1 << 63)} { set checksum [expr {$checksum - (1 << 64)}] }
            set last [reuse_energy::read_unsigned $vio last_product]
            if {$last >= (1 << 31)} { set last [expr {$last - (1 << 32)}] }
            reuse_energy::expect $completed $batches "batch count"
            reuse_energy::expect $products [expr {4 * $batches}] "product count"
            set expected_reads [expr {$mode eq "A" ? 4 * $batches : $batches}]
            reuse_energy::expect $reads $expected_reads "source reads"
            reuse_energy::expect $loads $expected_reads "weight loads"
            reuse_energy::expect $cycles [expr {14 * $batches}] "window cycles"
            reuse_energy::expect $checksum [expr {4 * $weight * $batches}] "signed product checksum"
            reuse_energy::expect $last [expr {4 * $weight}] "last product"
            reuse_energy::drive $vio cfg_start 0
            lappend rows [list $mode $weight $completed $products $reads $loads $cycles $checksum $last]
            puts "ENERGY_REPEATER_CHECK_PASS: [lindex $rows end]"
        }
    }
    set csv [open [file join $output_dir hardware.csv] {WRONLY CREAT EXCL}]
    puts $csv "mode,weight,batches,products,source_reads,weight_loads,cycles,checksum,last_product"
    foreach row $rows { puts $csv [join $row ,] }
    close $csv
    set report [open [file join $output_dir hardware.md] {WRONLY CREAT EXCL}]
    puts $report "# Autonomous batch repeater: physical verification"
    puts $report "\nTool: [version -short]. Device: xc7z010clg400-1. Clock: 100 MHz."
    puts $report "\nOne programming operation; both modes use the same bitstream."
    puts $report "\nBitstream SHA256: `[lindex [exec sha256sum $bitstream] 0]`"
    puts $report "\nProbe file SHA256: `[lindex [exec sha256sum $probes_file] 0]`"
    puts $report "\n| Mode | Weight | Batches | Products | Reads | Loads | Cycles | Checksum | Last product |"
    puts $report "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
    foreach row $rows { puts $report "| [join $row { | }] |" }
    puts $report "\nAll counter, checksum, last-product and completion assertions passed."
    puts $report "The checksum is a functional aggregate check, not a proof of every output sample."
    puts $report "ILA acquisition was not armed. JTAG supplies configuration/start and reads completion."
    puts $report "The hardware window is cycles / 100000000 seconds, not the host wait duration."
    puts $report "\nMeasured voltage/current and electrical energy: **not measured**."
    close $report
    puts "ENERGY_HARDWARE_PASS: [llength $rows] runs; results in $output_dir"
}

if {![info exists ::reuse_energy_library_only]} {
    if {$argc != 4} { error "Expected TARGET BITSTREAM PROBES NEW_OUTPUT_DIR" }
    open_hw
    connect_hw_server -url localhost:3121
    set target [get_hw_targets [lindex $argv 0]]
    if {[llength $target] != 1 || [get_property NAME $target] ne [lindex $argv 0]} {
        error "Use the exact intended hardware target, not a wildcard"
    }
    current_hw_target $target
    open_hw_target $target
    set device [get_hw_devices -of_objects $target -filter {NAME == xc7z010_1}]
    reuse_energy_run $device [lindex $argv 1] [lindex $argv 2] [lindex $argv 3]
    close_hw_target $target
    disconnect_hw_server
    close_hw
}
