library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyboard_scan_code is
	port(
		ext_clk, reset: in std_logic;
		ps2d, ps2c: in std_logic;
		tx: out std_logic
	);
end keyboard_scan_code;

architecture behavioral of keyboard_scan_code is
	component dcm_32_to_96
		port(
			clkin_in : in std_logic;          
			clkfx_out : out std_logic;
			clkin_ibufg_out : out std_logic;
			clk0_out : out std_logic
		);
	end component;
	
	component uart_tx is
		port(
			data_in : in std_logic_vector(7 downto 0);
         write_buffer : in std_logic;
         reset_buffer : in std_logic;
         en_16_x_baud : in std_logic;
         serial_out : out std_logic;
         buffer_full : out std_logic;
         buffer_half_full : out std_logic;
         clk : in std_logic
		);
	end component;
	
	constant SP: std_logic_vector(7 downto 0) := "00100000";
	type statetype is (idle, send1, send0, sendb);
	signal state_reg, state_next: statetype;
	signal scan_data, w_data: std_logic_vector(7 downto 0);
	signal scan_done_tick, wr_uart: std_logic;
	signal ascii_code: std_logic_vector(7 downto 0);
	signal hex_in: std_logic_vector(3 downto 0);
	signal clk, en_16_x_baud: std_logic;
	signal baud_count : integer range 0 to 1 :=0;
begin
	-- UART clock
	Inst_dcm_32_to_96: dcm_32_to_96
		port map(
			clkin_in => ext_clk,
			clkfx_out => clk,
			clkin_ibufg_out => open,
			clk0_out => open
		);

	process(clk, baud_count)
	begin
		if clk'event and clk = '1' then
			if baud_count = 1 then
				baud_count <= 0;
				en_16_x_baud <= '1';
			else
				baud_count <= baud_count + 1;
				en_16_x_baud <= '0';
			end if;
		end if;
	end process;

	-- PS2 receiver
	ps2_rx_unit: entity work.ps2_rx(arch)
		port map(
			clk => clk,
			reset => reset,
			ps2d => ps2d,
			ps2c => ps2c,
			rx_en => '1',
			rx_done_tick => scan_done_tick,
			dout => scan_data
		);

	-- UART tx
	inst_uart_tx : uart_tx
		port map (
			data_in => w_data,
			write_buffer => wr_uart,
			reset_buffer => reset,
			en_16_x_baud => en_16_x_baud,
			clk => clk,
			serial_out => tx,
			buffer_half_full => open,
			buffer_full => open
		);
	
	-- send 3 ascii characters
	-- state registers
	process(clk, reset)
	begin
		if reset = '1' then
			state_reg <= idle;
		elsif clk'event and clk = '1' then
			state_reg <= state_next;
		end if;
	end process;

	-- next-state logic
	process(state_reg, scan_done_tick, ascii_code)
	begin
		wr_uart <= '0';
		w_data <= SP;
		state_next <= state_reg;
		case state_reg is
			when idle =>
				if scan_done_tick = '1' then
					state_next <= send1;
				end if;
			when send1 =>
				w_data <= ascii_code;
				wr_uart <= '1';
				state_next <= send0;
			when send0 =>
				w_data <= ascii_code;
				wr_uart <= '1';
				state_next <= sendb;
			when sendb =>
				w_data <= SP;
				wr_uart <= '1';
				state_next <= idle;
		end case;
	end process;
	
	-- convert scan code to ascii characters
	-- split scan code into 2 nibbles
	hex_in <= scan_data(7 downto 4) when state_reg = send1 else scan_data(3 downto 0);
	
	-- hex to ascii
	with hex_in select
		ascii_code <=
			"00110000" when "0000", -- 0
			"00110001" when "0001", -- 1
			"00110010" when "0010", -- 2
			"00110011" when "0011", -- 3
			"00110100" when "0100", -- 4
			"00110101" when "0101", -- 5
			"00110110" when "0110", -- 6
			"00110111" when "0111", -- 7
			"00111000" when "1000", -- 8
			"00111001" when "1001", -- 9
			"01000001" when "1010", -- A
			"01000010" when "1011", -- B
			"01000011" when "1100", -- C
			"01000100" when "1101", -- D
			"01000101" when "1110", -- E
			"01000110" when "1111", -- F
			"01000110" when others; -- F
end behavioral;

