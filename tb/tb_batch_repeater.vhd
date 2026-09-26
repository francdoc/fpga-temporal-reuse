library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_batch_repeater is
end entity;

architecture simulation of tb_batch_repeater is
    signal clk : std_logic := '0';
    signal finished : boolean := false;
    signal rst : std_logic := '1';
    signal write_request, start_request, mode : std_logic := '0';
    signal weight_addr : unsigned(9 downto 0) := (others => '0');
    signal weight_data : signed(15 downto 0) := (others => '0');
    signal batch_count : unsigned(23 downto 0) := (others => '0');
    signal input0, input1, input2, input3 : signed(15 downto 0) := (others => '0');
    signal run_busy, run_done, core_start, core_write, core_busy, core_done : std_logic;
    signal sample_request, product_valid, source_read_enable, weight_register_load, active_mode : std_logic;
    signal completed_batches, product_count, read_count, load_count, cycle_count : unsigned(31 downto 0);
    signal checksum : signed(63 downto 0);
    signal last_product : signed(31 downto 0);
    signal core_x : signed(15 downto 0);
    type input_values_t is array (0 to 3) of integer;
begin
    clock : process
    begin
        while not finished loop
            clk <= '0';
            wait for 5 ns;
            clk <= '1';
            wait for 5 ns;
        end loop;
        wait;
    end process;
    dut : entity work.batch_repeater
        port map (
            clk => clk, rst => rst, write_request => write_request, start_request => start_request,
            mode => mode, weight_addr => weight_addr, weight_data => weight_data,
            batch_count => batch_count, input0 => input0, input1 => input1, input2 => input2, input3 => input3,
            run_busy => run_busy, run_done => run_done, completed_batches => completed_batches,
            product_count => product_count, read_count => read_count, load_count => load_count,
            cycle_count => cycle_count, checksum => checksum, last_product => last_product,
            core_start => core_start, core_write => core_write, core_busy => core_busy, core_done => core_done,
            sample_request => sample_request, product_valid => product_valid,
            source_read_enable => source_read_enable, weight_register_load => weight_register_load,
            core_x => core_x, active_mode => active_mode
        );

    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure write_weight(address_value : natural; weight_value : integer) is
        begin
            wait until falling_edge(clk);
            start_request <= '0';
            write_request <= '0';
            tick;
            wait until falling_edge(clk);
            weight_addr <= to_unsigned(address_value, 10);
            weight_data <= to_signed(weight_value, 16);
            write_request <= '1';
            wait for 1 ns;
            assert core_write = '1' report "Idle weight write was not accepted" severity failure;
            tick;
            assert core_write = '0' report "Held write generated multiple writes" severity failure;
            wait until falling_edge(clk);
            write_request <= '0';
            tick;
        end procedure;

        procedure run_case(selected_mode : std_logic; address_value : natural; weight_value : integer;
                           k : positive; values : input_values_t; disturb_controls : boolean) is
            variable starts, samples, products, reads, loads : natural := 0;
            variable expected_reads : natural;
            variable expected_product : integer;
            variable expected_sum : signed(63 downto 0) := (others => '0');
        begin
            wait until falling_edge(clk);
            start_request <= '0';
            write_request <= '0';
            tick;
            wait until falling_edge(clk);
            mode <= selected_mode;
            weight_addr <= to_unsigned(address_value, 10);
            batch_count <= to_unsigned(k, 24);
            input0 <= to_signed(values(0), 16);
            input1 <= to_signed(values(1), 16);
            input2 <= to_signed(values(2), 16);
            input3 <= to_signed(values(3), 16);
            start_request <= '1';
            tick;
            assert run_busy = '1' and run_done = '0' and cycle_count = 0
                report "Run did not start with cleared telemetry" severity failure;

            for cycle in 1 to 14*k loop
                wait until falling_edge(clk);
                if cycle = 1 then
                    start_request <= '0';
                elsif cycle = 2 and disturb_controls then
                    -- Independently pulse busy commands and alter every field.
                    start_request <= '1';
                    write_request <= '0';
                    mode <= not selected_mode;
                    weight_addr <= to_unsigned(address_value, 10);
                    weight_data <= to_signed(12345, 16);
                    batch_count <= to_unsigned(1, 24);
                    input0 <= to_signed(99, 16);
                    input1 <= to_signed(98, 16);
                    input2 <= to_signed(97, 16);
                    input3 <= to_signed(96, 16);
                elsif cycle = 3 and disturb_controls then
                    start_request <= '0';
                    write_request <= '1';
                elsif cycle = 4 and disturb_controls then
                    weight_addr <= to_unsigned((address_value + 1) mod 1024, 10);
                elsif cycle = 5 and disturb_controls then
                    write_request <= '0';
                elsif cycle = 14 and disturb_controls then
                    -- The core is idle here but the wrapper is still busy.
                    -- Hold the rejected edge beyond the end of the whole run.
                    if selected_mode = '0' then
                        weight_addr <= to_unsigned(address_value, 10);
                        write_request <= '1';
                    else
                        start_request <= '1';
                    end if;
                end if;
                wait until rising_edge(clk);
                assert core_write = '0' report "Busy write was accepted" severity failure;
                assert active_mode = selected_mode report "Mode changed during a run" severity failure;
                if core_start = '1' then
                    starts := starts + 1;
                    assert cycle = 1 + 14*(starts - 1)
                        report "Inter-batch start interval is not 14 clocks" severity failure;
                end if;
                if sample_request = '1' then
                    assert core_x = to_signed(values(samples mod 4), 16)
                        report "Input slot order or latching failed" severity failure;
                    samples := samples + 1;
                end if;
                if source_read_enable = '1' then
                    reads := reads + 1;
                    if selected_mode = '1' then
                        assert cycle = 2 + 14*(reads - 1)
                            report "Reuse mode must fetch a fresh weight every batch" severity failure;
                    end if;
                end if;
                if weight_register_load = '1' then
                    loads := loads + 1;
                end if;
                if product_valid = '1' then
                    expected_product := values(products mod 4) * weight_value;
                    assert last_product = to_signed(expected_product, 32)
                        report "Exact signed product mismatch" severity failure;
                    expected_sum := expected_sum + to_signed(expected_product, 64);
                    products := products + 1;
                end if;
                wait for 1 ns;
                assert cycle_count = to_unsigned(cycle, 32) report "Cycle count mismatch" severity failure;
                assert product_count = to_unsigned(products, 32) and read_count = to_unsigned(reads, 32)
                    and load_count = to_unsigned(loads, 32) and checksum = expected_sum
                    report "Event counter or checksum mismatch" severity failure;
                if cycle < 14*k then
                    assert run_busy = '1' and run_done = '0' report "Run completed too early" severity failure;
                end if;
            end loop;
            if selected_mode = '0' then expected_reads := 4*k; else expected_reads := k; end if;
            assert run_busy = '0' and run_done = '1' report "Run did not complete at 14*K" severity failure;
            assert completed_batches = to_unsigned(k, 32) and starts = k and samples = 4*k and products = 4*k
                report "Batch or product total mismatch" severity failure;
            assert reads = expected_reads and loads = expected_reads report "Read/load policy mismatch" severity failure;
            for idle_cycle in 1 to 3 loop
                tick;
                assert run_busy = '0' and run_done = '1' and core_start = '0' and core_write = '0'
                    and cycle_count = to_unsigned(14*k, 32) and checksum = expected_sum
                    report "Completion is unstable or a rejected command was queued" severity failure;
            end loop;
            report "REPEATER_CASE_PASS mode=" & std_logic'image(selected_mode) & " K=" & integer'image(k)
                & " weight=" & integer'image(weight_value) & " cycles=" & integer'image(14*k) severity note;
        end procedure;
    begin
        tick;
        tick;
        wait until falling_edge(clk);
        rst <= '0';
        tick;

        -- Zero batches and simultaneous idle commands are rejected.
        wait until falling_edge(clk);
        start_request <= '1';
        tick;
        assert run_busy = '0' and core_start = '0' report "K=0 was accepted" severity failure;
        wait until falling_edge(clk);
        start_request <= '0';
        tick;
        wait until falling_edge(clk);
        batch_count <= to_unsigned(4, 24);
        start_request <= '1';
        write_request <= '1';
        tick;
        assert run_busy = '0' and core_start = '0' and core_write = '0'
            report "Simultaneous idle commands were accepted" severity failure;

        write_weight(17, 7);
        run_case('0', 17, 7, 1, (1, -2, 1, 4), true);
        run_case('1', 17, 7, 1, (1, -2, 1, 4), true);
        run_case('0', 17, 7, 4, (3, -4, 11, -2), true);
        run_case('1', 17, 7, 4, (3, -4, 11, -2), true);
        -- The second runtime write changes an existing BRAM location.
        write_weight(17, -9);
        write_weight(1023, -32768);
        run_case('0', 17, -9, 257, (-8, 2, -1, 17), true);
        run_case('1', 17, -9, 257, (-8, 2, -1, 17), true);
        run_case('0', 1023, -32768, 4, (-32768, 32767, -1, 1), true);
        run_case('1', 1023, -32768, 4, (-32768, 32767, -1, 1), true);
        -- Accumulations beyond signed 32-bit range exercise checksum carry/sign.
        run_case('0', 1023, -32768, 4, (-32768, -32768, -32768, -32768), false);
        run_case('1', 1023, -32768, 4, (-32768, -32768, -32768, -32768), false);
        run_case('0', 1023, -32768, 4, (32767, 32767, 32767, 32767), false);
        run_case('1', 1023, -32768, 4, (32767, 32767, 32767, 32767), false);

        -- Reset aborts a partially completed run and clears all readbacks.
        wait until falling_edge(clk);
        write_request <= '0';
        start_request <= '0';
        tick;
        wait until falling_edge(clk);
        weight_addr <= to_unsigned(17, 10);
        batch_count <= to_unsigned(100, 24);
        start_request <= '1';
        tick;
        for cycle in 1 to 20 loop tick; end loop;
        assert run_busy = '1' and completed_batches = 1 report "Reset test did not enter a repeated run" severity failure;
        wait until falling_edge(clk);
        rst <= '1';
        start_request <= '0';
        tick;
        assert run_busy = '0' and run_done = '0' and completed_batches = 0 and product_count = 0
            and read_count = 0 and load_count = 0 and cycle_count = 0 and checksum = 0
            report "Mid-run reset did not clear the controller" severity failure;
        wait until falling_edge(clk);
        rst <= '0';
        tick;
        -- BRAM survives reset, and the next start fetches its weight again.
        run_case('1', 17, -9, 4, (1, -2, 1, 4), false);
        report "BATCH_REPEATER_ALL_TESTS_PASSED" severity note;
        finished <= true;
        wait;
    end process;

    watchdog : process
    begin
        wait for 500 us;
        assert finished report "Repeater simulation watchdog expired" severity failure;
        wait;
    end process;
end architecture;
