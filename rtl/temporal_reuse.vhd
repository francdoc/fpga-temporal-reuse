library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity temporal_reuse is
    generic (
        N : positive := 4
    );
    port (
        clk                  : in  std_logic;
        rst                  : in  std_logic;
        start                : in  std_logic;
        mode                 : in  std_logic;
        weight_write         : in  std_logic;
        weight_addr          : in  unsigned(9 downto 0);
        weight_data          : in  signed(15 downto 0);
        x                    : in  signed(15 downto 0);
        sample_request       : out std_logic;
        product_valid        : out std_logic;
        busy                 : out std_logic;
        done                 : out std_logic;
        source_read_enable   : out std_logic;
        weight_register_load : out std_logic;
        y                    : out signed(31 downto 0)
    );
end entity temporal_reuse;

architecture rtl of temporal_reuse is
    type state_t is (IDLE, READ, LOAD, MUL);
    signal state          : state_t;
    signal input_index    : natural range 0 to N - 1;
    signal mode_latched   : std_logic;
    signal source_address : unsigned(9 downto 0);
    signal mem_q          : signed(15 downto 0);
    signal w_reg          : signed(15 downto 0);
    signal x_reg          : signed(15 downto 0);
    signal need_weight    : std_logic;
    signal read_enable    : std_logic;
    signal load_enable    : std_logic;
    signal write_enable   : std_logic;
begin
    need_weight <= '1' when mode_latched = '0' or input_index = 0 else '0';
    read_enable <= '1' when rst = '0' and state = READ and need_weight = '1' else '0';
    load_enable <= '1' when rst = '0' and state = LOAD and need_weight = '1' else '0';
    write_enable <= '1' when rst = '0' and state = IDLE and start = '0' and weight_write = '1' else '0';

    -- Expose the actual enables consumed by the RAM and operand register.
    source_read_enable <= read_enable;
    weight_register_load <= load_enable;
    sample_request <= '1' when rst = '0' and state = READ else '0';
    busy <= '1' when state /= IDLE else '0';

    source_memory : entity work.source_bram
        port map (
            clk          => clk,
            write_enable => write_enable,
            read_enable  => read_enable,
            write_addr   => weight_addr,
            read_addr    => source_address,
            write_data   => weight_data,
            read_data    => mem_q
        );

    process (clk)
    begin
        if rising_edge(clk) then
            product_valid <= '0';
            done <= '0';

            if rst = '1' then
                state <= IDLE;
                input_index <= 0;
                mode_latched <= '0';
                source_address <= (others => '0');
                x_reg <= (others => '0');
                w_reg <= (others => '0');
                y <= (others => '0');
            else
                if load_enable = '1' then
                    w_reg <= mem_q;
                end if;

                case state is
                    when IDLE =>
                        if start = '1' and weight_write = '0' then
                            mode_latched <= mode;
                            source_address <= weight_addr;
                            input_index <= 0;
                            state <= READ;
                        end if;

                    when READ =>
                        -- The BRAM updates mem_q after this edge.
                        x_reg <= x;
                        state <= LOAD;

                    when LOAD =>
                        -- load_enable captures the previous READ's returned data.
                        state <= MUL;

                    when MUL =>
                        -- One signed multiplier serves both runtime policies.
                        y <= x_reg * w_reg;
                        product_valid <= '1';
                        if input_index = N - 1 then
                            done <= '1';
                            state <= IDLE;
                        else
                            input_index <= input_index + 1;
                            state <= READ;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- Compare at the next edge, after the preceding register update has settled.
    -- synthesis translate_off
    check_weight_retention : process (clk)
        variable previous_weight : signed(15 downto 0);
        variable previous_load   : std_logic := '0';
        variable previous_reset  : std_logic := '1';
        variable have_previous   : boolean := false;
    begin
        if rising_edge(clk) then
            if have_previous and previous_reset = '0' and previous_load = '0' then
                assert w_reg = previous_weight
                    report "Weight register changed without a load or reset"
                    severity failure;
            end if;
            previous_weight := w_reg;
            previous_load := load_enable;
            previous_reset := rst;
            have_previous := true;
        end if;
    end process;
    -- synthesis translate_on
end architecture rtl;
