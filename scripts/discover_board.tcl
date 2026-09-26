# Read-only JTAG discovery. Keep complete target identifiers in local records.
open_hw
connect_hw_server -url localhost:3121
foreach target [get_hw_targets] {
    puts "TARGET: $target"
    current_hw_target $target
    open_hw_target $target
    puts "DEVICES: [get_hw_devices -of_objects $target]"
    close_hw_target $target
}
disconnect_hw_server
close_hw
