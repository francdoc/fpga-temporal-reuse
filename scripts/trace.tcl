# XSim batch script; the runner selects a fresh external working directory.
set trace_top tb_temporal_reuse
set trace_name temporal_reuse
if {[info exists env(REUSE_TRACE_TOP)]} {
    set trace_top $env(REUSE_TRACE_TOP)
    set trace_name $env(REUSE_TRACE_NAME)
}
set traced_objects [list]
if {$trace_top eq "tb_temporal_reuse"} {
    foreach signal_name {clk finished source_read_count weight_load_count product_count source_read_count_one weight_load_count_one product_count_one} {
        set path /tb_temporal_reuse/$signal_name
        set objects [get_objects $path]
        if {[llength $objects] != 1} {
            error "Required testbench waveform object is missing: $path"
        }
        lappend traced_objects {*}$objects
    }
    foreach instance {dut dut_one} {
        foreach signal_name {clk rst start mode mode_latched state input_index weight_write weight_addr weight_data source_address source_read_enable mem_q weight_register_load w_reg sample_request x x_reg product_valid y busy done} {
            set path /tb_temporal_reuse/$instance/$signal_name
            set objects [get_objects $path]
            if {[llength $objects] != 1} {
                error "Required core waveform object is missing: $path"
            }
            lappend traced_objects {*}$objects
        }
    }
} elseif {$trace_top eq "tb_board_control"} {
    foreach signal_name {clk rst write_request start_request input0 input1 input2 input3 busy sample_request core_start core_write x start_count write_count finished} {
        set path /tb_board_control/$signal_name
        set objects [get_objects $path]
        if {[llength $objects] != 1} {
            error "Required wrapper waveform object is missing: $path"
        }
        lappend traced_objects {*}$objects
    }
} else {
    error "Unknown simulation top: $trace_top"
}
log_wave $traced_objects
open_vcd ${trace_name}.vcd
log_vcd -level 1 $traced_objects
run -all
close_vcd
quit
