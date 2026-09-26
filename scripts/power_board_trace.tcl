# write_verilog escapes instance identifiers containing dots or brackets; XSim
# requires that Verilog spelling (including terminating space) in scope paths.
proc simulation_path {mapped_path} {
    set result {}
    foreach component [split [string trimright $mapped_path /] /] {
        if {$component ne "" && ![regexp {^[a-zA-Z_][a-zA-Z0-9_$]*$} $component]} {
            lappend result "\\$component "
        } else { lappend result $component }
    }
    return [join $result /]
}
set setup_ns 0
while {[get_value /tb_power_board/measure_ready] ne "1" && $setup_ns < 100000} {
    run 1 ns -quiet
    incr setup_ns
}
if {[get_value /tb_power_board/measure_ready] ne "1" || [get_value /tb_power_board/simulation_done] ne "0"} {
    error "Board simulation did not reach the start of the measurement window"
}
puts "BOARD_POWER_WINDOW_START_NS=$setup_ns"
open_saif activity.saif
puts "BOARD_POWER_SAIF_OPEN"
set object_count 0
set scope_count 0
set scopes_file [open [file join $::env(REUSE_BOARD_POWER_EXPORT_DIR) activity_scopes.txt] r]
foreach scope [split [string trim [read $scopes_file]] \n] {
    set objects [get_objects [list "[simulation_path $scope]/*"]]
    if {![llength $objects]} { error "No simulation objects for mapped scope $scope" }
    log_saif $objects
    incr object_count [llength $objects]
    incr scope_count
}
close $scopes_file
set pins_file [open [file join $::env(REUSE_BOARD_POWER_EXPORT_DIR) activity_pins.txt] r]
foreach pin [split [string trim [read $pins_file]] \n] {
    set objects [get_objects [list [simulation_path $pin]]]
    if {[llength $objects] != 1} { error "Missing or ambiguous physical pin $pin" }
    log_saif $objects
    incr object_count
}
close $pins_file
puts "BOARD_POWER_CAPTURE_OBJECTS=$object_count SCOPES=$scope_count"
run $::env(REUSE_BOARD_POWER_WINDOW_NS) ns
close_saif
# Check settled telemetry even if the last testbench delta coincides with run's end.
run 1 ns
if {[get_value /tb_power_board/simulation_done] ne "1"} { error "Board simulation did not complete its matched window" }
puts "BOARD_POWER_SAIF_PASS"
quit
