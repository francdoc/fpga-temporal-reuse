# Run from an external directory after sourcing the selected Vivado settings64.sh:
# vivado -mode batch -source ROOT/scripts/run_sim.tcl -tclargs ROOT OUTPUT
# This entry point compiles and simulates only. It never opens hardware.

proc read_text {path} {
    set channel [open $path r]
    set contents [read $channel]
    close $channel
    return $contents
}

proc run_stage {label command log_path} {
    puts "Running $label; log: $log_path"
    set failed [catch {exec timeout --signal=TERM --kill-after=10s 180s {*}$command > $log_path 2>@1} message]
    if {$failed} {
        error "$label failed or timed out: $message. See $log_path"
    }
    set contents [read_text $log_path]
    if {[regexp -nocase {(^|\n)[ \t]*(fatal|failure|error)(:|[ \t]+\[)} $contents]} {
        error "$label reported an error or assertion failure. See $log_path"
    }
    return $contents
}

proc run_simulation {} {
    global argc argv env
    if {$argc != 2} {
        error "Usage: vivado -mode batch -source run_sim.tcl -tclargs SOURCE_ROOT OUTPUT_DIRECTORY"
    }
    set source_root [file normalize [lindex $argv 0]]
    set output_root [file normalize [lindex $argv 1]]
    if {[string first "$source_root/" "$output_root/"] == 0} {
        error "Simulation output must be outside the source tree"
    }
    set sources [list [file join $source_root rtl source_bram.vhd] \
                      [file join $source_root rtl temporal_reuse.vhd] \
                      [file join $source_root tb tb_temporal_reuse.vhd] \
                      [file join $source_root rtl board_control.vhd] \
                      [file join $source_root tb tb_board_control.vhd]]
    set trace_script [file join $source_root scripts trace.tcl]
    foreach path [concat $sources [list $trace_script]] {
        if {![file isfile $path]} {
            error "Required source does not exist: $path"
        }
    }
    if {[info exists env(REUSE_VIVADO_ROOT)]} {
        set installation [file normalize $env(REUSE_VIVADO_ROOT)]
    } elseif {[info exists env(XILINX_VIVADO)]} {
        set installation [file normalize $env(XILINX_VIVADO)]
    } else {
        error "Source settings64.sh and set REUSE_VIVADO_ROOT to the selected Vivado installation"
    }
    foreach name {xvhdl xelab xsim} {
        set executable [file join $installation bin $name]
        if {![file executable $executable]} {
            error "Selected installation is missing an executable: $executable"
        }
        set tool($name) $executable
    }
    if {[auto_execok timeout] eq ""} {
        error "The simulation runner requires the timeout command"
    }
    file mkdir $output_root
    foreach name {compile.log elaborate.log simulate.log elaborate_board_control.log simulate_board_control.log xsim.dir .Xil temporal_reuse.wdb temporal_reuse.vcd board_control.wdb board_control.vcd simulation_pass.txt} {
        if {[file exists [file join $output_root $name]]} {
            error "Preserving existing run: use a fresh output directory ($name already exists)"
        }
    }
    cd $output_root
    run_stage compilation [concat [list $tool(xvhdl)] $sources] [file join $output_root compile.log]
    foreach {top basename marker suffix} {
        tb_temporal_reuse temporal_reuse TEMPORAL_REUSE_ALL_TESTS_PASSED {}
        tb_board_control board_control BOARD_CONTROL_SIMULATION_PASS _board_control
    } {
        run_stage "$top elaboration" \
            [list $tool(xelab) $top -debug typical -s ${basename}_sim -log ${basename}_xelab.log] \
            [file join $output_root elaborate${suffix}.log]
        set env(REUSE_TRACE_TOP) $top
        set env(REUSE_TRACE_NAME) $basename
        set simulation_log [run_stage "$top simulation" \
            [list $tool(xsim) ${basename}_sim -wdb ${basename}.wdb -log ${basename}_xsim.log -tclbatch $trace_script] \
            [file join $output_root simulate${suffix}.log]]
        if {[string first $marker $simulation_log] < 0} {
            error "$top did not reach its final pass marker. See simulate${suffix}.log"
        }
        foreach extension {vcd wdb} {
            set artifact [file join $output_root ${basename}.${extension}]
            if {![file isfile $artifact] || [file size $artifact] == 0} {
                error "Required waveform was not written: $artifact"
            }
        }
    }
    set channel [open [file join $output_root simulation_pass.txt] {WRONLY CREAT EXCL}]
    puts $channel "TEMPORAL_REUSE_ALL_TESTS_PASSED"
    puts $channel "BOARD_CONTROL_SIMULATION_PASS"
    puts $channel "Source root: $source_root"
    puts $channel "Tool installation: $installation"
    puts $channel "Clock: 10 ns; complete batch latency: 3*N periods"
    puts $channel "See separate compile, elaborate and simulate logs and both VCD/WDB captures."
    close $channel
    puts "SIMULATION PASS: all assertions and final marker checked; waveforms in $output_root"
}

if {[catch {run_simulation} message]} {
    puts stderr "SIMULATION FAILED: $message"
    exit 1
}
exit 0
