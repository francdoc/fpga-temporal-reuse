`timescale 1ns/1ps
`include "tb_power_board_pins.vh"

// Full mapped board, including MMCM, repeater, VIO, ILA and debug hub.
// Configure VIO output nets before the window; initialize the JTAG model boundary
// during GSR, then hold it in a known idle state throughout measurement.
module tb_power_board;
    reg sys_clk = 0;
    always #4 sys_clk = ~sys_clk;
    energy_board_top dut (.sys_clk(sys_clk));
    wire experiment_clock = dut.clk_out1;
    integer selected_mode = 0, batches = 256;
    integer reads = 0, loads = 0, products = 0, captures = 0;
    integer cycles = 0, launches = 0, completions = 0;
    integer samples [0:3];
    integer expected_accesses;
    reg measure_active = 0, measure_ready = 0, simulation_done = 0;
    time window_start;

    initial begin
        force glbl.JTAG_TCK_GLBL = 1'b0;
        force glbl.JTAG_TDI_GLBL = 1'b0;
        force glbl.JTAG_TMS_GLBL = 1'b0;
        force glbl.JTAG_CAPTURE_GLBL = 1'b0;
        force glbl.JTAG_RESET_GLBL = 1'b1;
        force glbl.JTAG_SHIFT_GLBL = 1'b0;
        force glbl.JTAG_UPDATE_GLBL = 1'b0;
        force glbl.JTAG_RUNTEST_GLBL = 1'b1;
        force glbl.JTAG_SEL1_GLBL = 1'b0;
        force glbl.JTAG_SEL2_GLBL = 1'b0;
        force glbl.JTAG_SEL3_GLBL = 1'b0;
        force glbl.JTAG_SEL4_GLBL = 1'b0;
        #20; force glbl.JTAG_TCK_GLBL = 1'b1;
        #20; force glbl.JTAG_TCK_GLBL = 1'b0;
        #10; force glbl.JTAG_RESET_GLBL = 1'b0;
    end

    always @(posedge experiment_clock) begin
        if (measure_active) begin
            cycles = cycles + 1;
            if (`BOARD_READ_PIN !== dut.source_read_enable) $fatal(1, "Physical BRAM enable mismatch");
            if (`BOARD_LOAD_PIN !== dut.weight_register_load) $fatal(1, "Physical DSP enable mismatch");
            if (dut.rst !== 0 || dut.clock_locked !== 1) $fatal(1, "Reset or clock unlock during window");
            reads = reads + `BOARD_READ_PIN;
            loads = loads + `BOARD_LOAD_PIN;
            captures = captures + dut.sample_request;
            launches = launches + dut.core_start;
            completions = completions + dut.core_done;
            if (dut.product_valid === 1) begin
                if ($signed(dut.last_product) !== samples[products % 4] * 7) $fatal(1, "Wrong signed product");
                products = products + 1;
            end else if (dut.product_valid !== 0) $fatal(1, "Unknown product valid");
        end
    end

    initial begin
        if (!$value$plusargs("power_mode=%d", selected_mode)) $fatal(1, "Missing mode");
        if (!$value$plusargs("power_batches=%d", batches)) $fatal(1, "Missing batches");
        if (selected_mode < 0 || selected_mode > 1 || batches < 1 || batches > 24'hffffff) $fatal(1, "Invalid parameters");
        samples[0] = 1; samples[1] = 2; samples[2] = -3; samples[3] = 4;
        force dut.cfg_reset = 1'b1;
        force dut.cfg_write = 1'b0;
        force dut.cfg_start = 1'b0;
        force dut.cfg_mode = selected_mode;
        force dut.cfg_addr = 10'd0;
        force dut.cfg_weight = 16'd7;
        force dut.cfg_batches = batches;
        force dut.cfg_x0 = 16'd1;
        force dut.cfg_x1 = 16'd2;
        force dut.cfg_x2 = 16'hfffd;
        force dut.cfg_x3 = 16'd4;
        wait (dut.clock_locked === 1);
        repeat (10) @(posedge experiment_clock);
        @(negedge experiment_clock);
        force dut.cfg_reset = 1'b0;
        repeat (4) @(posedge experiment_clock);
        @(negedge experiment_clock);
        force dut.cfg_write = 1'b1;
        @(posedge experiment_clock);
        if (dut.core_write !== 1) $fatal(1, "Runtime weight write not accepted");
        @(negedge experiment_clock);
        force dut.cfg_write = 1'b0;
        repeat (4) @(posedge experiment_clock);
        @(negedge experiment_clock);
        force dut.cfg_start = 1'b1;
        @(posedge experiment_clock);
        #1;
        if (dut.run_busy !== 1 || dut.run_done !== 0 || dut.cycle_count !== 0) $fatal(1, "Start acceptance failed");
        window_start = $time;
        measure_ready = 1;
        measure_active = 1;
        // Tcl polls this flag in 1 ns increments, then opens its exact 14K window.
        repeat (14 * batches) @(posedge experiment_clock);
        #1;
        measure_active = 0;
        if ($time - window_start != 64'd140 * batches) $fatal(1, "Wrong window duration");
        expected_accesses = batches * (selected_mode == 0 ? 4 : 1);
        if (reads !== expected_accesses || loads !== expected_accesses) $fatal(1, "Wrong physical enable count");
        if (cycles !== 14 * batches || products !== 4 * batches || captures !== 4 * batches || launches !== batches || completions !== batches) $fatal(1, "Wrong work totals");
        if (dut.run_busy !== 0 || dut.run_done !== 1) $fatal(1, "Run did not complete");
        if (dut.completed_batches !== batches || dut.product_count !== 4 * batches || dut.read_count !== expected_accesses || dut.load_count !== expected_accesses || dut.cycle_count !== 14 * batches) $fatal(1, "Hardware counter mismatch");
        if ($signed(dut.checksum) !== 28 * batches || $signed(dut.last_product) !== 28) $fatal(1, "Wrong checksum or final product");
        simulation_done = 1;
        $display("BOARD_POWER_SIMULATION_PASS mode=%0d weight=7 batches=%0d reads=%0d loads=%0d products=%0d captures=%0d launches=%0d completions=%0d cycles=%0d checksum=%0d last_product=%0d window_ns=%0d", selected_mode, batches, reads, loads, products, captures, launches, completions, cycles, $signed(dut.checksum), $signed(dut.last_product), 64'd140 * batches);
    end
endmodule
