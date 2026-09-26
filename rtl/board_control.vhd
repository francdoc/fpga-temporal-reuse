library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity board_control is
    port (
        clk            : in  std_logic;
        rst            : in  std_logic;
        write_request  : in  std_logic;
        start_request  : in  std_logic;
        input0         : in  signed(15 downto 0);
        input1         : in  signed(15 downto 0);
        input2         : in  signed(15 downto 0);
        input3         : in  signed(15 downto 0);
        busy           : in  std_logic;
        sample_request : in  std_logic;
        core_start     : out std_logic;
        core_write     : out std_logic;
        x              : out signed(15 downto 0)
    );
end entity board_control;

architecture rtl of board_control is
    type inputs_t is array (0 to 3) of signed(15 downto 0);
    signal inputs_latched : inputs_t;
    signal input_index   : natural range 0 to 3;
    signal previous_start : std_logic;
    signal previous_write : std_logic;
    signal accepted_start : std_logic;
    signal accepted_write : std_logic;
begin
    accepted_start <= '1' when rst = '0' and busy = '0' and start_request = '1' and previous_start = '0' and write_request = '0' else '0';
    accepted_write <= '1' when rst = '0' and busy = '0' and write_request = '1' and previous_write = '0' and start_request = '0' else '0';
    core_start <= accepted_start;
    core_write <= accepted_write;
    x <= inputs_latched(input_index);

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                previous_start <= '0';
                previous_write <= '0';
                inputs_latched <= (others => (others => '0'));
                input_index <= 0;
            else
                -- Record rejected requests too, so they cannot queue while busy.
                previous_start <= start_request;
                previous_write <= write_request;

                if accepted_start = '1' then
                    inputs_latched(0) <= input0;
                    inputs_latched(1) <= input1;
                    inputs_latched(2) <= input2;
                    inputs_latched(3) <= input3;
                    input_index <= 0;
                elsif sample_request = '1' and input_index < 3 then
                    -- The core captures the current x on this same clock edge.
                    input_index <= input_index + 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
