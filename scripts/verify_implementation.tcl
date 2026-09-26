# Run against the open routed board design, before programming it.
proc verify_implementation {output_dir} {
    set report [open [file join $output_dir implementation_checks.txt] w]
    set ram [get_cells -hier -filter {NAME =~ core/* && REF_NAME == RAMB18E1}]
    set dsp [get_cells -hier -filter {NAME =~ core/* && REF_NAME == DSP48E1}]
    if {[llength $ram] != 1 || [llength $dsp] != 1} { error "Core resource contract failed" }
    set read_pin [get_pins $ram/ENBWREN]
    set ila_pin [get_pins -of_objects [get_cells capture_ila] -filter {REF_PIN_NAME =~ probe2*}]
    if {[llength $ila_pin] != 1} { error "Missing unique ILA read-enable probe" }
    set read_nets [get_nets -segments -of_objects $read_pin]
    set ila_nets [get_nets -segments -of_objects $ila_pin]
    set shared 0
    foreach net $read_nets {
        if {[lsearch -exact $ila_nets $net] >= 0} { set shared 1 }
    }
    if {!$shared} { error "ILA read-enable probe is not the physical RAM read enable" }
    puts $report "Read enable: $read_pin and $ila_pin share a routed net"
    set load_pin [get_pins -of_objects [get_cells capture_ila] -filter {REF_PIN_NAME =~ probe3*}]
    set load_nets [get_nets -segments -of_objects $load_pin]
    set weight_ce [get_pins $dsp/CEB2]
    set shared 0
    foreach net [get_nets -segments -of_objects $weight_ce] {
        if {[lsearch -exact $load_nets $net] >= 0} { set shared 1 }
    }
    if {!$shared || [get_property BREG $dsp] != 1} {
        error "Weight register is not controlled by the observed load enable"
    }
    puts $report "Weight load: $weight_ce and $load_pin share a routed net; BREG=1"
    if {[get_property READ_WIDTH_B $ram] != 18 || [get_property DOB_REG $ram] != 0} {
        error "Unexpected RAM read port width or latency"
    }
    puts $report "Source RAM: [get_property LOC $ram]; READ_WIDTH_B=18; DOB_REG=0"
    puts $report "Multiplier: $dsp at [get_property LOC $dsp]"
    foreach pin_name {A B} {
        puts $report "DSP ${pin_name}REG=[get_property ${pin_name}REG $dsp]"
        foreach number {1 2} {
            set pin [get_pins $dsp/CE${pin_name}${number}]
            puts $report "  $pin: [get_nets -of_objects $pin]"
        }
    }
    foreach pin_name {A B} {
        set pin [get_pins [format {%s/%s[0]} $dsp $pin_name]]
        puts $report "DSP operand $pin: [get_nets -of_objects $pin]"
    }
    set clocks [get_clocks -of_objects [get_pins $dsp/CLK]]
    if {[llength $clocks] != 1 || [get_property PERIOD $clocks] != 10.0} {
        error "Expected one 10 ns experiment clock"
    }
    puts $report "Experiment clock: $clocks period [get_property PERIOD $clocks] ns"
    foreach delay_type {max min} {
        set path [get_timing_paths -delay_type $delay_type -max_paths 1]
        if {[llength $path] != 1 || [get_property SLACK $path] < 0} { error "Timing failed" }
        puts $report "$delay_type slack: [get_property SLACK $path] ns"
    }
    set timing_check [check_timing -verbose -return_string]
    if {[regexp {There are [1-9][0-9]* } $timing_check]} { error "check_timing findings require review" }
    puts $report "check_timing: all reported counts zero"
    set pulse_report [report_pulse_width -return_string]
    if {[string match *VIOLATED* $pulse_report]} { error "Pulse-width violation" }
    puts $report "Pulse-width report: no violations"
    set pulse_file [open [file join $output_dir pulse_width.rpt] w]
    puts $pulse_file $pulse_report
    close $pulse_file
    if {[llength [get_drc_violations -quiet -filter {SEVERITY == Error}]]} { error "DRC errors" }
    puts $report "IMPLEMENTATION_CHECKS_PASS"
    close $report
}
