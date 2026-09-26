library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One command repeats a four-input batch without host activity between batches.
-- K is limited to 24 bits: 14*K cycles and 4*K events fit in 32 bits, while
-- the signed sum of every 16x16 product fits in 64 bits.
entity batch_repeater is
    port (
        clk, rst : in std_logic;
        write_request, start_request, mode : in std_logic;
        weight_addr : in unsigned(9 downto 0);
        weight_data : in signed(15 downto 0);
        batch_count : in unsigned(23 downto 0);
        input0, input1, input2, input3 : in signed(15 downto 0);
        run_busy, run_done : out std_logic;
        completed_batches, product_count, read_count, load_count, cycle_count : out unsigned(31 downto 0);
        checksum : out signed(63 downto 0);
        last_product : out signed(31 downto 0);
        core_start, core_write, core_busy, core_done : out std_logic;
        sample_request, product_valid, source_read_enable, weight_register_load : out std_logic;
        core_x : out signed(15 downto 0);
        active_mode : out std_logic
    );
end entity;

architecture rtl of batch_repeater is
    type state_t is (IDLE, LAUNCH, ACTIVE);
    type inputs_t is array (0 to 3) of signed(15 downto 0);
    signal state : state_t;
    signal inputs_latched : inputs_t;
    signal input_index : natural range 0 to 3;
    signal mode_latched : std_logic;
    signal address_latched, core_address : unsigned(9 downto 0);
    signal batch_limit : unsigned(23 downto 0);
    signal previous_start, previous_write, accepted_start, accepted_write : std_logic;
    signal start_i, sample_i, valid_i, done_i, read_i, load_i : std_logic;
    signal x_i : signed(15 downto 0);
    signal product_i : signed(31 downto 0);
    signal completed_i, products_i, reads_i, loads_i, cycles_i : unsigned(31 downto 0);
    signal checksum_i : signed(63 downto 0);
begin
    accepted_start <= '1' when rst = '0' and state = IDLE and start_request = '1' and previous_start = '0' and write_request = '0' and batch_count /= 0 else '0';
    accepted_write <= '1' when rst = '0' and state = IDLE and write_request = '1' and previous_write = '0' and start_request = '0' else '0';
    start_i <= '1' when rst = '0' and state = LAUNCH else '0';
    core_address <= weight_addr when state = IDLE else address_latched;
    x_i <= inputs_latched(input_index);

    run_busy <= '1' when rst = '0' and state /= IDLE else '0';
    completed_batches <= completed_i;
    product_count <= products_i;
    read_count <= reads_i;
    load_count <= loads_i;
    cycle_count <= cycles_i;
    checksum <= checksum_i;
    last_product <= product_i;
    core_start <= start_i;
    core_write <= accepted_write;
    sample_request <= sample_i;
    product_valid <= valid_i;
    core_done <= done_i;
    source_read_enable <= read_i;
    weight_register_load <= load_i;
    core_x <= x_i;
    active_mode <= mode_latched;

    core : entity work.temporal_reuse
        generic map (N => 4)
        port map (
            clk => clk, rst => rst, start => start_i, mode => mode_latched,
            weight_write => accepted_write, weight_addr => core_address,
            weight_data => weight_data, x => x_i,
            sample_request => sample_i, product_valid => valid_i,
            busy => core_busy, done => done_i, source_read_enable => read_i,
            weight_register_load => load_i, y => product_i
        );

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                previous_start <= '0';
                previous_write <= '0';
                inputs_latched <= (others => (others => '0'));
                input_index <= 0;
                mode_latched <= '0';
                address_latched <= (others => '0');
                batch_limit <= (others => '0');
                completed_i <= (others => '0');
                products_i <= (others => '0');
                reads_i <= (others => '0');
                loads_i <= (others => '0');
                cycles_i <= (others => '0');
                checksum_i <= (others => '0');
                run_done <= '0';
            else
                -- Rejected edges are consumed, including requests held past done.
                previous_start <= start_request;
                previous_write <= write_request;

                if state /= IDLE then
                    cycles_i <= cycles_i + 1;
                    if read_i = '1' then
                        reads_i <= reads_i + 1;
                    end if;
                    if load_i = '1' then
                        loads_i <= loads_i + 1;
                    end if;
                    if valid_i = '1' then
                        products_i <= products_i + 1;
                        checksum_i <= checksum_i + resize(product_i, 64);
                    end if;
                end if;

                case state is
                    when IDLE =>
                        if accepted_start = '1' then
                            inputs_latched <= (input0, input1, input2, input3);
                            mode_latched <= mode;
                            address_latched <= weight_addr;
                            batch_limit <= batch_count;
                            input_index <= 0;
                            completed_i <= (others => '0');
                            products_i <= (others => '0');
                            reads_i <= (others => '0');
                            loads_i <= (others => '0');
                            cycles_i <= (others => '0');
                            checksum_i <= (others => '0');
                            run_done <= '0';
                            state <= LAUNCH;
                        end if;
                    when LAUNCH =>
                        -- A fresh core start resets its per-batch weight policy.
                        state <= ACTIVE;
                    when ACTIVE =>
                        if sample_i = '1' and input_index < 3 then
                            input_index <= input_index + 1;
                        end if;
                        if done_i = '1' then
                            completed_i <= completed_i + 1;
                            if completed_i = resize(batch_limit, 32) - 1 then
                                run_done <= '1';
                                state <= IDLE;
                            else
                                input_index <= 0;
                                state <= LAUNCH;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
