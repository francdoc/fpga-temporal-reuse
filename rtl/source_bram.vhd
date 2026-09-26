library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity source_bram is
    port (
        clk          : in  std_logic;
        write_enable : in  std_logic;
        read_enable  : in  std_logic;
        write_addr   : in  unsigned(9 downto 0);
        read_addr    : in  unsigned(9 downto 0);
        write_data   : in  signed(15 downto 0);
        read_data    : out signed(15 downto 0)
    );
end entity source_bram;

architecture rtl of source_bram is
    type memory_t is array (0 to 1023) of signed(15 downto 0);
    signal memory : memory_t;

    attribute ram_style : string;
    attribute ram_style of memory : signal is "block";
begin
    -- Neither the array nor its read output is reset. Write an entry before use.
    process (clk)
    begin
        if rising_edge(clk) then
            if write_enable = '1' then
                memory(to_integer(write_addr)) <= write_data;
            end if;

            -- The output holds its previous value when the read port is disabled.
            if read_enable = '1' then
                read_data <= memory(to_integer(read_addr));
            end if;
        end if;
    end process;
end architecture rtl;
