`timescale 1ns/1ps
`include "tb_power_pins.vh"

// Identical useful work and wall-clock windows in independently started runs.
module tb_power_temporal_reuse;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, start = 0, mode = 0, weight_write = 0;
    reg [9:0] weight_addr = 0;
    reg signed [15:0] weight_data = 0, x = 0;
    wire sample_request, product_valid, busy, done;
    wire source_read_enable, weight_register_load;
    wire signed [31:0] y;
    integer selected_mode = 0, weight = 7, batches = 1024;
    integer batch, edge_index, sample_index, slot, expected_access;
    integer reads = 0, loads = 0, products = 0, captures = 0;
    integer physical_reads = 0, physical_loads = 0, completions = 0;
    integer samples [0:3];
    reg need_weight;
    temporal_reuse dut (
        .clk(clk), .rst(rst), .start(start), .mode(mode),
        .weight_write(weight_write), .weight_addr(weight_addr),
        .weight_data(weight_data), .x(x), .sample_request(sample_request),
        .product_valid(product_valid), .busy(busy), .done(done),
        .source_read_enable(source_read_enable),
        .weight_register_load(weight_register_load), .y(y)
    );

    initial begin
        if (!$value$plusargs("power_mode=%d", selected_mode)) $fatal(1, "Missing mode");
        if (!$value$plusargs("power_weight=%d", weight)) $fatal(1, "Missing weight");
        if (!$value$plusargs("power_batches=%d", batches)) $fatal(1, "Missing batch count");
        if (selected_mode < 0 || selected_mode > 1 || batches < 1) $fatal(1, "Invalid parameters");
        samples[0] = 1; samples[1] = 2; samples[2] = -3; samples[3] = 4;
        // Wait for the primitive global startup reset, then program real BRAM.
        #200;
        rst = 0;
        mode = selected_mode;
        weight_data = weight;
        weight_write = 1;
        #10;
        weight_write = 0;
        #90;
        // Measurement begins at 300 ns; setup/write/reset are outside it.
        for (batch = 0; batch < batches; batch = batch + 1) begin
            start = 1;
            @(posedge clk);
            if (source_read_enable !== 0 || weight_register_load !== 0) $fatal(1, "Unexpected start-edge access");
            for (edge_index = 1; edge_index <= 12; edge_index = edge_index + 1) begin
                sample_index = (edge_index - 1) / 3;
                slot = (edge_index - 1) % 3;
                need_weight = selected_mode == 0 || sample_index == 0;
                @(negedge clk);
                start = 0;
                if (slot == 0) x = samples[sample_index];
                @(posedge clk);
                if (sample_request !== (slot == 0)) $fatal(1, "Wrong sample schedule");
                if (source_read_enable !== (slot == 0 && need_weight)) $fatal(1, "Wrong read enable");
                if (weight_register_load !== (slot == 1 && need_weight)) $fatal(1, "Wrong load enable");
                if (`POWER_READ_PIN !== source_read_enable) $fatal(1, "Physical BRAM enable mismatch");
                if (`POWER_LOAD_PIN !== weight_register_load) $fatal(1, "Physical DSP enable mismatch");
                captures = captures + sample_request;
                reads = reads + source_read_enable;
                loads = loads + weight_register_load;
                physical_reads = physical_reads + `POWER_READ_PIN;
                physical_loads = physical_loads + `POWER_LOAD_PIN;
                #1;
                if (product_valid !== (slot == 2)) $fatal(1, "Wrong valid schedule");
                if (done !== (edge_index == 12)) $fatal(1, "Wrong completion schedule");
                if (product_valid) begin
                    if (y !== samples[sample_index] * weight) $fatal(1, "Wrong signed product");
                    products = products + 1;
                end
                completions = completions + done;
            end
            @(negedge clk);
            @(posedge clk);
            if (source_read_enable !== 0 || weight_register_load !== 0 || `POWER_READ_PIN !== 0 || `POWER_LOAD_PIN !== 0) $fatal(1, "Unexpected idle-edge access");
            #1;
            if (busy !== 0 || product_valid !== 0 || done !== 0) $fatal(1, "Unexpected idle output");
            if (batch == batches - 1) begin
                expected_access = batches * (selected_mode == 0 ? 4 : 1);
                if (reads != expected_access || loads != expected_access || physical_reads != expected_access || physical_loads != expected_access) $fatal(1, "Wrong access totals");
                if (products != batches * 4 || captures != batches * 4 || completions != batches) $fatal(1, "Wrong work totals");
                $display("POWER_SIMULATION_PASS mode=%0d weight=%0d batches=%0d reads=%0d loads=%0d physical_reads=%0d physical_loads=%0d products=%0d captures=%0d completions=%0d window_ns=%0d", selected_mode, weight, batches, reads, loads, physical_reads, physical_loads, products, captures, completions, batches * 140);
            end
            @(negedge clk);
        end
    end
endmodule
