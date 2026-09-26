library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity board_top is
    port (sys_clk : in std_logic);
end entity;

architecture rtl of board_top is
    component reuse_clock is
        port (clk_in1 : in std_logic; clk_out1 : out std_logic; locked : out std_logic);
    end component;

    component reuse_vio is
        port (
            clk : in std_logic;
            probe_in0, probe_in1 : in std_logic_vector(0 downto 0);
            probe_out0 : out std_logic_vector(0 downto 0);
            probe_out1 : out std_logic_vector(9 downto 0);
            probe_out2 : out std_logic_vector(15 downto 0);
            probe_out3, probe_out4, probe_out5 : out std_logic_vector(0 downto 0);
            probe_out6, probe_out7, probe_out8, probe_out9 : out std_logic_vector(15 downto 0)
        );
    end component;

    component reuse_ila is
        port (
            clk : in std_logic;
            probe0, probe1, probe2, probe3, probe4 : in std_logic_vector(0 downto 0);
            probe5 : in std_logic_vector(15 downto 0);
            probe6 : in std_logic_vector(0 downto 0);
            probe7 : in std_logic_vector(31 downto 0);
            probe8, probe9, probe10, probe11 : in std_logic_vector(0 downto 0)
        );
    end component;

    signal clk, clock_locked : std_logic;
    signal reset_release : std_logic_vector(1 downto 0) := (others => '1');
    signal rst : std_logic;
    signal cfg_reset, cfg_write, cfg_mode, cfg_start : std_logic_vector(0 downto 0);
    signal cfg_addr : std_logic_vector(9 downto 0);
    signal cfg_weight, cfg_x0, cfg_x1, cfg_x2, cfg_x3 : std_logic_vector(15 downto 0);
    signal core_start, core_write, sample_request, product_valid, busy, done : std_logic;
    signal source_read_enable, weight_register_load : std_logic;
    signal active_mode : std_logic := '0';
    signal core_x : signed(15 downto 0);
    signal product : signed(31 downto 0);
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of reset_release : signal is "TRUE";
begin
    clock_generator : reuse_clock
        port map (clk_in1 => sys_clk, clk_out1 => clk, locked => clock_locked);

    -- Debug clock stays running during experiment reset. Synchronize lock
    -- status before it controls synchronous RAM/datapath enables.
    process (clk)
    begin
        if rising_edge(clk) then
            reset_release <= reset_release(0) & not clock_locked;
        end if;
    end process;
    rst <= reset_release(1) or cfg_reset(0);

    control_vio : reuse_vio
        port map (
            clk => clk, probe_in0(0) => busy, probe_in1(0) => clock_locked,
            probe_out0 => cfg_reset, probe_out1 => cfg_addr, probe_out2 => cfg_weight,
            probe_out3 => cfg_write, probe_out4 => cfg_mode, probe_out5 => cfg_start,
            probe_out6 => cfg_x0, probe_out7 => cfg_x1,
            probe_out8 => cfg_x2, probe_out9 => cfg_x3
        );

    commands : entity work.board_control
        port map (
            clk => clk, rst => rst, write_request => cfg_write(0), start_request => cfg_start(0),
            input0 => signed(cfg_x0), input1 => signed(cfg_x1),
            input2 => signed(cfg_x2), input3 => signed(cfg_x3),
            busy => busy, sample_request => sample_request,
            core_start => core_start, core_write => core_write, x => core_x
        );

    core : entity work.temporal_reuse
        generic map (N => 4)
        port map (
            clk => clk, rst => rst, start => core_start, mode => cfg_mode(0),
            weight_write => core_write, weight_addr => unsigned(cfg_addr),
            weight_data => signed(cfg_weight), x => core_x,
            sample_request => sample_request, product_valid => product_valid,
            busy => busy, done => done, source_read_enable => source_read_enable,
            weight_register_load => weight_register_load, y => product
        );

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                active_mode <= '0';
            elsif core_start = '1' then
                active_mode <= cfg_mode(0);
            end if;
        end if;
    end process;

    -- Probe indices are the stable capture contract used by run_hardware.tcl.
    capture_ila : reuse_ila
        port map (
            clk => clk, probe0(0) => core_start, probe1(0) => active_mode,
            probe2(0) => source_read_enable, probe3(0) => weight_register_load,
            probe4(0) => sample_request, probe5 => std_logic_vector(core_x),
            probe6(0) => product_valid, probe7 => std_logic_vector(product),
            probe8(0) => busy, probe9(0) => done,
            probe10(0) => core_write, probe11(0) => rst
        );
end architecture;
