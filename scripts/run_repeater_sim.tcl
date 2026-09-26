# vivado -mode batch -source run_repeater_sim.tcl -tclargs SOURCE_ROOT FRESH_OUTPUT_DIR
proc run_repeater_simulation {} {
    global argc argv env
    if {$argc != 2} { error "Expected SOURCE_ROOT and FRESH_OUTPUT_DIR" }
    set source_root [file normalize [lindex $argv 0]]
    set output_dir [file normalize [lindex $argv 1]]
    if {[string first "$source_root/" "$output_dir/"] == 0} { error "Use an output directory outside the source tree" }
    if {[file exists $output_dir]} {
        foreach entry [glob -nocomplain -tails -directory $output_dir * .*] {
            if {$entry ni {. ..}} { error "Use a fresh output directory" }
        }
    }
    if {[info exists env(REUSE_VIVADO_ROOT)]} {
        set installation $env(REUSE_VIVADO_ROOT)
    } elseif {[info exists env(XILINX_VIVADO)]} {
        set installation $env(XILINX_VIVADO)
    } else {
        error "Source Vivado settings64.sh first"
    }
    file mkdir $output_dir
    cd $output_dir
    set sources [list]
    foreach name {source_bram temporal_reuse batch_repeater} {
        lappend sources [file join $source_root rtl ${name}.vhd]
    }
    lappend sources [file join $source_root tb tb_batch_repeater.vhd]
    set trace [open repeater_trace.tcl {WRONLY CREAT EXCL}]
    puts $trace {set signals {}}
    puts $trace {foreach name {clk rst write_request start_request mode weight_addr weight_data batch_count input0 input1 input2 input3 run_busy run_done core_start core_write core_busy core_done sample_request product_valid source_read_enable weight_register_load active_mode completed_batches product_count read_count load_count cycle_count checksum last_product core_x} {lappend signals [get_objects /tb_batch_repeater/$name]}}
    puts $trace {log_wave $signals}
    puts $trace {open_vcd batch_repeater.vcd}
    puts $trace {log_vcd -level 1 $signals}
    puts $trace {run -all}
    puts $trace {close_vcd}
    puts $trace {quit}
    close $trace
    foreach {stage command} [list \
        compile [concat [list [file join $installation bin xvhdl]] $sources] \
        elaborate [list [file join $installation bin xelab] tb_batch_repeater -debug typical -O0 -s repeater_sim] \
        simulate [list [file join $installation bin xsim] repeater_sim -wdb batch_repeater.wdb -tclbatch repeater_trace.tcl]] {
        puts "Running repeater $stage"
        if {[catch {exec timeout --signal=TERM --kill-after=10s 180s {*}$command > ${stage}.log 2>@1} message]} {
            error "$stage failed: $message; see $output_dir/${stage}.log"
        }
        set channel [open ${stage}.log r]
        set contents [read $channel]
        close $channel
        if {[regexp -nocase {(^|\n)[ \t]*(fatal_error|fatal|failure|error)(:|[ \t]+\[)} $contents]} {
            error "$stage reported an error; see $output_dir/${stage}.log"
        }
    }
    if {[string first BATCH_REPEATER_ALL_TESTS_PASSED $contents] < 0} { error "Simulation pass marker missing" }
    foreach name {batch_repeater.vcd batch_repeater.wdb} {
        if {![file exists $name] || [file size $name] == 0} { error "Missing waveform: $name" }
    }
    set channel [open simulation_pass.txt {WRONLY CREAT EXCL}]
    puts $channel "BATCH_REPEATER_ALL_TESTS_PASSED"
    puts $channel "Clock 10 ns; autonomous run window 14*K cycles in both modes"
    close $channel
    puts "REPEATER_SIMULATION_PASS: $output_dir"
}
if {[catch {run_repeater_simulation} message]} {
    puts stderr "REPEATER_SIMULATION_FAILED: $message"
    exit 1
}
exit 0
