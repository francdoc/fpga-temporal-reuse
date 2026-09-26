library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_temporal_reuse is
end entity;

architecture test of tb_temporal_reuse is
    constant CLOCK_PERIOD : time := 10 ns;
    constant SETTLE_TIME : time := 1 ns;
    type integer_vector_t is array (natural range <>) of integer;
    constant BASELINE : integer_vector_t(0 to 3) := (1, 2, -3, 4);
    constant EXTREMES : integer_vector_t(0 to 3) := (-32768, 32767, -1, 0);
    constant SINGLE_INPUT : integer_vector_t(0 to 0) := (0 => -3);

    type stimulus_t is record
        rst, start, mode, weight_write : std_logic;
        weight_addr : unsigned(9 downto 0);
        weight_data, x : signed(15 downto 0);
    end record;
    type response_t is record
        sample_request, product_valid, busy, done : std_logic;
        source_read_enable, weight_register_load : std_logic;
        y : signed(31 downto 0);
    end record;
    constant RESET_STIMULUS : stimulus_t := (
        rst => '1', start => '0', mode => '0', weight_write => '0',
        weight_addr => (others => '0'), weight_data => (others => '0'),
        x => (others => '0')
    );

    signal clk : std_logic := '0';
    signal finished : boolean := false;
    signal stimulus, stimulus_one : stimulus_t := RESET_STIMULUS;
    signal observed, observed_one : response_t;
    signal source_read_count, weight_load_count, product_count : natural := 0;
    signal source_read_count_one, weight_load_count_one, product_count_one : natural := 0;

    function logic(value : boolean) return std_logic is
    begin
        if value then
            return '1';
        end if;
        return '0';
    end function;

    procedure check_idle(signal result : in response_t; constant edges : positive := 3) is
    begin
        for edge in 1 to edges loop
            wait until rising_edge(clk);
            assert result.sample_request = '0' and result.source_read_enable = '0' and result.weight_register_load = '0'
                report "Unexpected capture, read or load while idle" severity failure;
            wait for SETTLE_TIME;
            assert result.busy = '0' and result.product_valid = '0' and result.done = '0'
                report "Extra product, completion or busy cycle while idle" severity failure;
        end loop;
    end procedure;

    procedure reset_core(signal drive : inout stimulus_t; signal result : in response_t) is
    begin
        wait until falling_edge(clk);
        drive.rst <= '1';
        drive.start <= '0';
        drive.weight_write <= '0';
        wait for SETTLE_TIME;
        assert result.sample_request = '0' and result.source_read_enable = '0' and result.weight_register_load = '0'
            report "Reset did not suppress capture/read/load enables" severity failure;
        wait until rising_edge(clk);
        wait for SETTLE_TIME;
        assert result.busy = '0' and result.product_valid = '0' and result.done = '0' and result.y = to_signed(0, 32)
            report "Reset did not discard pending output and clear the datapath" severity failure;
        wait until falling_edge(clk);
        drive.rst <= '0';
        check_idle(result);
    end procedure;

    procedure write_weight(signal drive : inout stimulus_t; signal result : in response_t;
                           constant address : natural; constant weight : integer) is
    begin
        wait until falling_edge(clk);
        assert result.busy = '0' report "Testbench attempted a busy write" severity failure;
        drive.start <= '0';
        drive.weight_addr <= to_unsigned(address, 10);
        drive.weight_data <= to_signed(weight, 16);
        drive.weight_write <= '1';
        wait until rising_edge(clk);
        wait for SETTLE_TIME;
        assert result.busy = '0' and result.product_valid = '0' and result.done = '0'
            report "Weight write unexpectedly started processing" severity failure;
        wait until falling_edge(clk);
        drive.weight_write <= '0';
    end procedure;

    procedure run_batch(signal drive : inout stimulus_t; signal result : in response_t;
                        signal reads_trace, loads_trace, products_trace : out natural;
                        constant label_text : string; constant selected_mode : std_logic;
                        constant address : natural; constant weight : integer;
                        constant samples : integer_vector_t) is
        variable reads, loads, products, captures, completions : natural := 0;
        variable sample_index, slot, expected_accesses : natural;
        variable expected_product : signed(31 downto 0);
        variable need_weight : boolean;
        variable start_time : time;
    begin
        wait until falling_edge(clk);
        assert result.busy = '0' and drive.weight_write = '0' and drive.rst = '0'
            report label_text & ": illegal start stimulus" severity failure;
        reads_trace <= 0;
        loads_trace <= 0;
        products_trace <= 0;
        drive.mode <= selected_mode;
        drive.weight_addr <= to_unsigned(address, 10);
        drive.start <= '1';
        wait until rising_edge(clk);
        start_time := now;
        assert result.source_read_enable = '0' and result.weight_register_load = '0'
            report label_text & ": source access occurred on start edge zero" severity failure;
        wait for SETTLE_TIME;
        assert result.busy = '1' and result.sample_request = '1' and result.product_valid = '0' and result.done = '0'
            report label_text & ": start did not enter READ without producing output" severity failure;

        for edge in 1 to 3 * samples'length loop
            sample_index := samples'low + (edge - 1) / 3;
            slot := (edge - 1) mod 3;
            need_weight := selected_mode = '0' or sample_index = samples'low;
            wait until falling_edge(clk);
            drive.start <= '0';
            -- These external changes must not alter the accepted batch.
            drive.mode <= not selected_mode;
            drive.weight_addr <= to_unsigned((address + 1) mod 1024, 10);
            if slot = 0 then
                drive.x <= to_signed(samples(sample_index), 16);
            else
                drive.x <= to_signed(16381, 16);
            end if;
            wait until rising_edge(clk);
            assert result.busy = '1' report label_text & ": busy fell before final MUL" severity failure;
            assert result.sample_request = logic(slot = 0)
                report label_text & ": wrong input-capture schedule" severity failure;
            assert result.source_read_enable = logic(slot = 0 and need_weight)
                report label_text & ": wrong actual source-read enable" severity failure;
            assert result.weight_register_load = logic(slot = 1 and need_weight)
                report label_text & ": wrong actual weight-load enable" severity failure;

            -- Count the actual pre-edge enables, before registered updates settle.
            if result.sample_request = '1' then
                captures := captures + 1;
            end if;
            if result.source_read_enable = '1' then
                reads := reads + 1;
            end if;
            if result.weight_register_load = '1' then
                loads := loads + 1;
            end if;
            reads_trace <= reads;
            loads_trace <= loads;
            wait for SETTLE_TIME;
            assert result.product_valid = logic(slot = 2)
                report label_text & ": wrong product-valid schedule" severity failure;
            assert result.done = logic(edge = 3 * samples'length)
                report label_text & ": done was early, missing or repeated" severity failure;
            assert result.busy = logic(edge /= 3 * samples'length)
                report label_text & ": wrong completion/busy schedule" severity failure;
            if result.product_valid = '1' then
                assert reads > 0 and loads > 0
                    report label_text & ": product appeared before read and load" severity failure;
                assert not is_x(std_logic_vector(result.y))
                    report label_text & ": unknown bit in valid product" severity failure;
                expected_product := to_signed(samples(sample_index) * weight, 32);
                assert result.y = expected_product
                    report label_text & ": wrong signed product at index " & integer'image(products) severity failure;
                report label_text & ": product[" & integer'image(products) & "]=" & integer'image(to_integer(result.y)) &
                    " at edge " & integer'image(edge) severity note;
                products := products + 1;
                products_trace <= products;
            end if;
            if result.done = '1' then
                completions := completions + 1;
                assert now - SETTLE_TIME - start_time = 3 * samples'length * CLOCK_PERIOD
                    report label_text & ": completion latency is not 3*N clock periods" severity failure;
            end if;
        end loop;

        expected_accesses := 1;
        if selected_mode = '0' then
            expected_accesses := samples'length;
        end if;
        assert reads = expected_accesses and loads = expected_accesses
            report label_text & ": incorrect total source reads or weight loads" severity failure;
        assert captures = samples'length and products = samples'length and completions = 1
            report label_text & ": incorrect total captures, products or done pulses" severity failure;
        check_idle(result);
        report "CASE PASS: " & label_text & " mode=" & std_logic'image(selected_mode) &
            " N=" & integer'image(samples'length) & " weight=" & integer'image(weight) &
            " reads=" & integer'image(reads) & " loads=" & integer'image(loads) &
            " products=" & integer'image(products) & " cycles=" & integer'image(3 * samples'length) severity note;
    end procedure;

    procedure abort_batch(signal drive : inout stimulus_t; signal result : in response_t;
                          constant selected_mode : std_logic; constant completed_edges : natural) is
    begin
        wait until falling_edge(clk);
        drive.mode <= selected_mode;
        drive.weight_addr <= to_unsigned(0, 10);
        drive.start <= '1';
        drive.x <= to_signed(7, 16);
        wait until rising_edge(clk);
        wait for SETTLE_TIME;
        assert result.busy = '1' report "Abort test could not start the batch" severity failure;
        for edge in 1 to completed_edges loop
            wait until falling_edge(clk);
            drive.start <= '0';
            wait until rising_edge(clk);
            wait for SETTLE_TIME;
            assert result.product_valid = '0' and result.done = '0'
                report "Output appeared before the aborted first MUL" severity failure;
        end loop;
        -- Reset in READ, LOAD or MUL before the first output can commit.
        reset_core(drive, result);
    end procedure;
begin
    dut : entity work.temporal_reuse
        generic map (N => 4)
        port map (
            clk => clk, rst => stimulus.rst, start => stimulus.start, mode => stimulus.mode,
            weight_write => stimulus.weight_write, weight_addr => stimulus.weight_addr,
            weight_data => stimulus.weight_data, x => stimulus.x,
            sample_request => observed.sample_request, product_valid => observed.product_valid,
            busy => observed.busy, done => observed.done, source_read_enable => observed.source_read_enable,
            weight_register_load => observed.weight_register_load, y => observed.y
        );

    dut_one : entity work.temporal_reuse
        generic map (N => 1)
        port map (
            clk => clk, rst => stimulus_one.rst, start => stimulus_one.start, mode => stimulus_one.mode,
            weight_write => stimulus_one.weight_write, weight_addr => stimulus_one.weight_addr,
            weight_data => stimulus_one.weight_data, x => stimulus_one.x,
            sample_request => observed_one.sample_request, product_valid => observed_one.product_valid,
            busy => observed_one.busy, done => observed_one.done, source_read_enable => observed_one.source_read_enable,
            weight_register_load => observed_one.weight_register_load, y => observed_one.y
        );

    clock_generator : process
    begin
        while not finished loop
            clk <= '0';
            wait for CLOCK_PERIOD / 2;
            clk <= '1';
            wait for CLOCK_PERIOD / 2;
        end loop;
        clk <= '0';
        wait;
    end process;

    protocol_monitor : process(clk)
    begin
        if rising_edge(clk) then
            assert not (stimulus.start = '1' and stimulus.weight_write = '1') and
                   not (stimulus_one.start = '1' and stimulus_one.weight_write = '1')
                report "Testbench protocol violation: simultaneous write/start" severity failure;
            if stimulus.rst = '0' and observed.busy = '1' then
                assert stimulus.start = '0' and stimulus.weight_write = '0'
                    report "Testbench protocol violation: busy request for N=4" severity failure;
            end if;
            if stimulus_one.rst = '0' and observed_one.busy = '1' then
                assert stimulus_one.start = '0' and stimulus_one.weight_write = '0'
                    report "Testbench protocol violation: busy request for N=1" severity failure;
            end if;
        end if;
    end process;

    tests : process
    begin
        reset_core(stimulus, observed);
        write_weight(stimulus, observed, 0, 3);
        for policy in 0 to 1 loop
            run_batch(stimulus, observed, source_read_count, weight_load_count, product_count,
                      "baseline", logic(policy = 1), 0, 3, BASELINE);
        end loop;
        write_weight(stimulus, observed, 0, -2);
        for policy in 0 to 1 loop
            run_batch(stimulus, observed, source_read_count, weight_load_count, product_count,
                      "weight_replacement", logic(policy = 1), 0, -2, BASELINE);
        end loop;
        write_weight(stimulus, observed, 731, 5);
        for policy in 0 to 1 loop
            run_batch(stimulus, observed, source_read_count, weight_load_count, product_count,
                      "address_selection", logic(policy = 1), 731, 5, BASELINE);
        end loop;
        for policy in 0 to 1 loop
            for phase in 0 to 2 loop
                abort_batch(stimulus, observed, logic(policy = 1), phase);
                -- No rewrite: reset must preserve the source array and force a fresh read.
                run_batch(stimulus, observed, source_read_count, weight_load_count, product_count,
                          "reset_restart_phase_" & integer'image(phase), logic(policy = 1), 0, -2, BASELINE);
            end loop;
        end loop;
        write_weight(stimulus, observed, 1023, -32768);
        for policy in 0 to 1 loop
            run_batch(stimulus, observed, source_read_count, weight_load_count, product_count,
                      "signed_minimum_weight", logic(policy = 1), 1023, -32768, EXTREMES);
        end loop;
        write_weight(stimulus, observed, 1023, 32767);
        for policy in 0 to 1 loop
            run_batch(stimulus, observed, source_read_count, weight_load_count, product_count,
                      "signed_maximum_weight", logic(policy = 1), 1023, 32767, EXTREMES);
        end loop;

        reset_core(stimulus_one, observed_one);
        write_weight(stimulus_one, observed_one, 0, 3);
        for policy in 0 to 1 loop
            run_batch(stimulus_one, observed_one, source_read_count_one, weight_load_count_one, product_count_one,
                      "single_input", logic(policy = 1), 0, 3, SINGLE_INPUT);
        end loop;
        report "TEMPORAL_REUSE_ALL_TESTS_PASSED" severity note;
        finished <= true;
        wait;
    end process;

    watchdog : process
    begin
        wait until finished for 20 us;
        assert finished report "Testbench watchdog expired" severity failure;
        wait;
    end process;
end architecture;
