library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity energy_board_top is
    port (sys_clk : in std_logic);
end entity;

architecture rtl of energy_board_top is
    component energy_clock is
        port (clk_in1 : in std_logic; clk_out1 : out std_logic; locked : out std_logic);
    end component;
    component energy_vio is
        port (
            clk : in std_logic;
            probe_in0, probe_in1, probe_in2 : in std_logic_vector(0 downto 0);
            probe_in3, probe_in4, probe_in5, probe_in6, probe_in7 : in std_logic_vector(31 downto 0);
            probe_in8 : in std_logic_vector(63 downto 0);
            probe_in9 : in std_logic_vector(31 downto 0);
            probe_out0 : out std_logic_vector(0 downto 0);
            probe_out1 : out std_logic_vector(9 downto 0);
            probe_out2 : out std_logic_vector(15 downto 0);
            probe_out3, probe_out4, probe_out5 : out std_logic_vector(0 downto 0);
            probe_out6, probe_out7, probe_out8, probe_out9 : out std_logic_vector(15 downto 0);
            probe_out10 : out std_logic_vector(23 downto 0)
        );
    end component;
    component energy_ila is
        port (
            clk : in std_logic;
            probe0, probe1, probe2, probe3, probe4 : in std_logic_vector(0 downto 0);
            probe5 : in std_logic_vector(15 downto 0);
            probe6 : in std_logic_vector(0 downto 0);
            probe7 : in std_logic_vector(31 downto 0);
            probe8, probe9, probe10, probe11 : in std_logic_vector(0 downto 0)
        );
    end component;

    signal clk, clock_locked, rst : std_logic;
    signal reset_release : std_logic_vector(1 downto 0) := (others => '1');
    signal cfg_reset, cfg_write, cfg_mode, cfg_start : std_logic_vector(0 downto 0);
    signal cfg_addr : std_logic_vector(9 downto 0);
    signal cfg_weight, cfg_x0, cfg_x1, cfg_x2, cfg_x3 : std_logic_vector(15 downto 0);
    signal cfg_batches : std_logic_vector(23 downto 0);
    signal run_busy, run_done, core_start, core_write, core_busy, core_done : std_logic;
    signal sample_request, product_valid, source_read_enable, weight_register_load, active_mode : std_logic;
    signal completed_batches, product_count, read_count, load_count, cycle_count : unsigned(31 downto 0);
    signal checksum : signed(63 downto 0);
    signal last_product : signed(31 downto 0);
    signal core_x : signed(15 downto 0);
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of reset_release : signal is "TRUE";
begin
    clock_generator : energy_clock
        port map (clk_in1 => sys_clk, clk_out1 => clk, locked => clock_locked);
    process (clk)
    begin
        if rising_edge(clk) then
            reset_release <= reset_release(0) & not clock_locked;
        end if;
    end process;
    rst <= reset_release(1) or cfg_reset(0);

    control_vio : energy_vio
        port map (
            clk => clk, probe_in0(0) => run_busy, probe_in1(0) => clock_locked,
            probe_in2(0) => run_done, probe_in3 => std_logic_vector(completed_batches),
            probe_in4 => std_logic_vector(product_count), probe_in5 => std_logic_vector(read_count),
            probe_in6 => std_logic_vector(load_count), probe_in7 => std_logic_vector(cycle_count),
            probe_in8 => std_logic_vector(checksum), probe_in9 => std_logic_vector(last_product),
            probe_out0 => cfg_reset, probe_out1 => cfg_addr, probe_out2 => cfg_weight,
            probe_out3 => cfg_write, probe_out4 => cfg_mode, probe_out5 => cfg_start,
            probe_out6 => cfg_x0, probe_out7 => cfg_x1, probe_out8 => cfg_x2,
            probe_out9 => cfg_x3, probe_out10 => cfg_batches
        );

    repeater : entity work.batch_repeater
        port map (
            clk => clk, rst => rst, write_request => cfg_write(0), start_request => cfg_start(0),
            mode => cfg_mode(0), weight_addr => unsigned(cfg_addr), weight_data => signed(cfg_weight),
            batch_count => unsigned(cfg_batches), input0 => signed(cfg_x0), input1 => signed(cfg_x1),
            input2 => signed(cfg_x2), input3 => signed(cfg_x3),
            run_busy => run_busy, run_done => run_done, completed_batches => completed_batches,
            product_count => product_count, read_count => read_count, load_count => load_count,
            cycle_count => cycle_count, checksum => checksum, last_product => last_product,
            core_start => core_start, core_write => core_write, core_busy => core_busy, core_done => core_done,
            sample_request => sample_request, product_valid => product_valid,
            source_read_enable => source_read_enable, weight_register_load => weight_register_load,
            core_x => core_x, active_mode => active_mode
        );

    -- Same per-batch probe meanings as the original demo. Leave ILA unarmed
    -- throughout a measurement run; VIO reads stable counters after run_done.
    capture_ila : energy_ila
        port map (
            clk => clk, probe0(0) => core_start, probe1(0) => active_mode,
            probe2(0) => source_read_enable, probe3(0) => weight_register_load,
            probe4(0) => sample_request, probe5 => std_logic_vector(core_x),
            probe6(0) => product_valid, probe7 => std_logic_vector(last_product),
            probe8(0) => core_busy, probe9(0) => core_done,
            probe10(0) => core_write, probe11(0) => rst
        );
end architecture;
