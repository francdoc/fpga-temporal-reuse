# Independent Vivado process for each mode; original routed board remains intact.
if {$argc != 3} { error "Expected CHECKPOINT SAIF OUTPUT_DIR" }
set checkpoint [file normalize [lindex $argv 0]]
set saif [file normalize [lindex $argv 1]]
set output_dir [file normalize [lindex $argv 2]]
set_param general.maxThreads 2
open_checkpoint $checkpoint
set_operating_conditions -process typical -junction_temp 25 -ambient_temp 25 -voltage {Vccint 1.0 Vccaux 1.8 Vccbram 1.0}
read_saif -strip_path tb_power_board/dut -out_file [file join $output_dir annotation.rpt] $saif
# Preserve physical connectivity proof for every accepted floating vector hole
# and every unmatched power net. Names are exact dictionary lookups, not globs.
set by_name [dict create]
foreach net [get_nets -hier] { dict set by_name [get_property NAME $net] $net }
set queries [dict create]
foreach stage {1 2} {
    foreach bit [concat [list 0] {11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32}] {
        dict set queries [format {capture_ila/U0/ila_core_inst/u_ila_cap_ctrl/u_cap_addrgen/cfg_data_vec_sync%d[%d]} $stage $bit] floating_vector_hole
    }
}
foreach bit {13 14 15 16} { dict set queries [format {capture_ila/U0/ila_core_inst/u_ila_regs/s_daddr[%d]} $bit] floating_vector_hole }
foreach bit {1 2} { dict set queries [format {repeater/core/in0[%d]} $bit] floating_vector_hole }
set annotation_file [open [file join $output_dir annotation.rpt] r]
set in_design 0
while {[gets $annotation_file line] >= 0} {
    if {$line eq {--- Unmatched design nets ---}} { set in_design 1; continue }
    if {$in_design && [string trim $line] ne {}} { dict set queries [string trim $line] unmatched_design_net }
}
close $annotation_file
set audit_file [open [file join $output_dir connectivity.tsv] {WRONLY CREAT EXCL}]
puts $audit_file "category\tnet\ttype\tleaf_drivers\tleaf_loads"
dict for {name category} $queries {
    if {![dict exists $by_name $name]} { error "Missing audited DCP net $name" }
    set net [dict get $by_name $name]
    set segments [get_nets -segments $net]
    set drivers [get_pins -quiet -leaf -of_objects $segments -filter {DIRECTION == OUT}]
    set loads [get_pins -quiet -leaf -of_objects $segments -filter {DIRECTION == IN}]
    puts $audit_file "$category\t$name\t[get_property TYPE $net]\t[llength $drivers]\t[llength $loads]"
    if {[llength $loads] || ($category eq "floating_vector_hole" && [llength $drivers])} { error "Audited unused net has physical connections: $name" }
}
close $audit_file
set bscan [get_cells -hier -filter {REF_NAME == BSCANE2}]
set tck_nets [get_nets -segments -of_objects [get_pins $bscan/TCK]]
# Request the explicitly idle JTAG boundary. Vivado 2018.1 emits Power 33-324
# and retains constraint-derived 30.30 MHz activity here; it does not honor
# this override. Keep that limitation visible without changing timing clocks.
set_switching_activity -signal_rate 0 -static_probability 0 $tck_nets
report_switching_activity -signal_rate -static_probability -toggle_rate [get_nets -hier] -file [file join $output_dir switching.rpt]
set_units -power uW
report_power -hier all -l 10000 -file [file join $output_dir power.rpt]
report_power -hier all -l 10000 -format xml -file [file join $output_dir power.xml]
report_clocks -file [file join $output_dir clocks.rpt]
set ram [get_cells -hier -filter {NAME =~ repeater/core/* && REF_NAME == RAMB18E1}]
set dsp [get_cells -hier -filter {NAME =~ repeater/core/* && REF_NAME == DSP48E1}]
set pins [concat [get_pins $ram/ENBWREN] [get_pins $ram/CLKBWRCLK] [get_pins $dsp/CEB2] [get_pins $dsp/CLK] [get_pins -of_objects $bscan]]
report_switching_activity -signal_rate -static_probability -toggle_rate $pins -file [file join $output_dir primitive_switching.rpt]
set metadata [open [file join $output_dir analysis_identity.tsv] {WRONLY CREAT EXCL}]
puts $metadata "checkpoint_sha256\t[lindex [exec sha256sum $checkpoint] 0]"
foreach clock [get_clocks] { puts $metadata "clock\t$clock\t[get_property PERIOD $clock]" }
close $metadata
puts "BOARD_POWER_REPORT_PASS"
close_design
