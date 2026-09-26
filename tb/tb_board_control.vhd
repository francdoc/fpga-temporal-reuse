library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_board_control is
end entity tb_board_control;

architecture test of tb_board_control is
    signal clk            : std_logic := '0';
    signal rst            : std_logic := '1';
    signal write_request  : std_logic := '0';
    signal start_request  : std_logic := '0';
    signal input0         : signed(15 downto 0) := to_signed(1, 16);
    signal input1         : signed(15 downto 0) := to_signed(2, 16);
    signal input2         : signed(15 downto 0) := to_signed(-3, 16);
    signal input3         : signed(15 downto 0) := to_signed(4, 16);
    signal busy           : std_logic := '0';
    signal sample_request : std_logic := '0';
    signal core_start     : std_logic;
    signal core_write     : std_logic;
    signal x              : signed(15 downto 0);
    signal start_count    : natural := 0;
    signal write_count    : natural := 0;
    signal finished       : boolean := false;
begin
    dut : entity work.board_control
        port map (
            clk => clk,
            rst => rst,
            write_request => write_request,
            start_request => start_request,
            input0 => input0,
            input1 => input1,
            input2 => input2,
            input3 => input3,
            busy => busy,
            sample_request => sample_request,
            core_start => core_start,
            core_write => core_write,
            x => x
        );

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

    count_commands : process (clk)
    begin
        if rising_edge(clk) then
            assert not (core_start = '1' and core_write = '1')
                report "Start and write commands overlapped" severity failure;
            if core_start = '1' then
                start_count <= start_count + 1;
            end if;
            if core_write = '1' then
                write_count <= write_count + 1;
            end if;
        end if;
    end process;

    stimulus : process
        procedure tick is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure expect_commands(constant starts : natural; constant writes : natural) is
        begin
            assert start_count = starts and write_count = writes
                report "Unexpected accepted command count" severity failure;
        end procedure;

        procedure capture_input(constant expected : integer) is
        begin
            sample_request <= '1';
            wait until rising_edge(clk);
            -- This samples x at the same instant as the real core's READ edge.
            assert x = to_signed(expected, 16)
                report "Snapshot input order/value mismatch" severity failure;
            wait for 1 ns;
            sample_request <= '0';
            tick;
            tick;
        end procedure;
    begin
        tick;
        assert core_start = '0' and core_write = '0' and x = to_signed(0, 16)
            report "Reset did not clear control and input state" severity failure;
        rst <= '0';
        tick;

        -- A held write request is accepted once, then must return low to rearm.
        write_request <= '1';
        tick;
        tick;
        tick;
        expect_commands(0, 1);
        write_request <= '0';
        tick;
        write_request <= '1';
        tick;
        expect_commands(0, 2);
        write_request <= '0';
        tick;

        -- Both request levels high rejects both, including when one is lowered.
        write_request <= '1';
        start_request <= '1';
        tick;
        tick;
        write_request <= '0';
        tick;
        expect_commands(0, 2);
        start_request <= '0';
        tick;

        -- A held start snapshots all four inputs and creates only one command.
        start_request <= '1';
        tick;
        busy <= '1';
        input0 <= to_signed(101, 16);
        input1 <= to_signed(102, 16);
        input2 <= to_signed(103, 16);
        input3 <= to_signed(104, 16);
        capture_input(1);
        capture_input(2);
        capture_input(-3);
        capture_input(4);
        assert x = to_signed(4, 16)
            report "Input sequencer advanced past the fourth slot" severity failure;
        busy <= '0';
        tick;
        tick;
        expect_commands(1, 2);
        start_request <= '0';
        tick;

        -- A new rising start while busy is consumed, never queued for idle.
        busy <= '1';
        start_request <= '1';
        tick;
        tick;
        busy <= '0';
        tick;
        tick;
        expect_commands(1, 2);
        start_request <= '0';
        tick;

        -- A write rejected while busy also requires a new rising request.
        busy <= '1';
        write_request <= '1';
        tick;
        busy <= '0';
        tick;
        tick;
        expect_commands(1, 2);
        write_request <= '0';
        tick;
        write_request <= '1';
        tick;
        expect_commands(1, 3);
        write_request <= '0';
        tick;

        -- The next accepted start replaces the snapshot and restarts at slot 0.
        start_request <= '1';
        tick;
        start_request <= '0';
        busy <= '1';
        expect_commands(2, 3);
        capture_input(101);
        capture_input(102);

        -- Reset aborts sequencing and suppresses commands on its active edge.
        rst <= '1';
        start_request <= '1';
        write_request <= '1';
        sample_request <= '1';
        tick;
        assert core_start = '0' and core_write = '0' and x = to_signed(0, 16)
            report "Reset failed during input sequencing" severity failure;
        expect_commands(2, 3);
        start_request <= '0';
        write_request <= '0';
        sample_request <= '0';
        busy <= '0';
        rst <= '0';
        tick;
        start_request <= '1';
        tick;
        start_request <= '0';
        busy <= '1';
        capture_input(101);
        capture_input(102);
        capture_input(103);
        capture_input(104);
        busy <= '0';
        tick;
        expect_commands(3, 3);

        report "BOARD_CONTROL_SIMULATION_PASS" severity note;
        finished <= true;
        wait;
    end process;
end architecture test;
