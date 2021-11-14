---------------------------------------------------------------------------------
-- Bagman - Dar - Feb 2014
-- See README for explanation about sram loading or vhdl rom files.
---------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all,ieee.numeric_std.all;

entity bagman is
port(
	clock_12mhz  : in std_logic;
	clock_1mhz   : in std_logic;
	reset        : in std_logic;

	video_r      : out std_logic_vector(2 downto 0);
	video_g      : out std_logic_vector(2 downto 0);
	video_b      : out std_logic_vector(1 downto 0);
	video_clk    : out std_logic;
	video_hs     : out std_logic;
	video_vs     : out std_logic;
	hblank       : out std_logic;
	vblank       : out std_logic;
  hoffset      : in std_logic_vector(3 downto 0);
  voffset      : in std_logic_vector(3 downto 0);
	vce          : out std_logic;

	mod_pick     : in std_logic;

	joy_p1       : in std_logic_vector(7 downto 0);
	joy_p2       : in std_logic_vector(7 downto 0);
	dipsw        : in std_logic_vector(7 downto 0);

	sound_string : out unsigned(12 downto 0);

	dn_addr      : in  std_logic_vector(16 downto 0);
	dn_data      : in  std_logic_vector(7 downto 0);
	dn_wr				 : in	 std_logic;

	paused			 : in	 std_logic;

	hs_address	 : in	 std_logic_vector(15 downto 0);
	hs_data_out	 : out std_logic_vector(7 downto 0);
	hs_data_in	 : in	 std_logic_vector(7 downto 0);
	hs_write_enable	 : in std_logic;
	hs_write_intent	 : in std_logic;
	hs_read_intent	 : in std_logic
);
end bagman;

architecture struct of bagman is

-- video syncs
signal hsync       : std_logic;
signal vsync       : std_logic;

-- global synchronisation
signal addr_state : std_logic_vector(3 downto 0);
signal is_sprite  : std_logic;
signal sprite     : std_logic_vector(2 downto 0);
signal x_tile     : std_logic_vector(4 downto 0);
signal y_tile     : std_logic_vector(4 downto 0);
signal x_pixel    : std_logic_vector(2 downto 0);
signal y_pixel    : std_logic_vector(2 downto 0);
signal y_line     : std_logic_vector(7 downto 0);

-- background and sprite tiles and graphics
signal tile_code   : std_logic_vector(12 downto 0);
signal tile_color  : std_logic_vector(3 downto 0);
signal tile_graph1 : std_logic_vector(7 downto 0);
signal tile_graph2 : std_logic_vector(7 downto 0);
signal x_sprite    : std_logic_vector(7 downto 0);
signal y_sprite    : std_logic_vector(7 downto 0);
signal inv_sprite  : std_logic_vector(1 downto 0);
signal keep_sprite : std_logic;

signal tile_color_r  : std_logic_vector(3 downto 0);
signal tile_graph1_r : std_logic_vector(7 downto 0);
signal tile_graph2_r : std_logic_vector(7 downto 0);

signal pixel_color   : std_logic_vector(5 downto 0);
signal pixel_color_r : std_logic_vector(5 downto 0);

signal y_diff_sprite      : std_logic_vector (7 downto 0);
signal sprite_pixel_color : std_logic_vector(5 downto 0);
signal do_palette         : std_logic_vector(7 downto 0);

signal addr_ram_sprite : std_logic_vector(8 downto 0);
signal is_sprite_r     : std_logic;

type ram_256x6 is array(0 to 255) of std_logic_vector(5 downto 0);
signal ram_sprite : ram_256x6;

-- Z80 interface
signal cpu_clock  : std_logic;
signal cpu_wr_n   : std_logic;
signal cpu_addr   : std_logic_vector(15 downto 0);
signal cpu_data   : std_logic_vector(7 downto 0);
signal cpu_di     : std_logic_vector(7 downto 0);
signal cpu_mreq_n : std_logic;
signal cpu_int_n  : std_logic;
signal cpu_iorq_n : std_logic;

signal misc_we_n   : std_logic;
signal raz_int_n   : std_logic;
signal sound_cs_n  : std_logic;
signal speech_we_n : std_logic;
signal sound2_cs_n : std_logic;

-- data bus from sram when read by cpu
signal sram_data_to_cpu : std_logic_vector(7 downto 0);

-- data bus from AY-3-8910
signal ym_8910_data : std_logic_vector(7 downto 0);

-- audio
signal ym_8910_audio : std_logic_vector(7 downto 0);
signal music         : unsigned(12 downto 0);
signal speech_sample : integer range -512 to 511;
signal ym_8910_audio2: std_logic_vector(7 downto 0);
--

-- random generator
signal pal16r6_data : std_logic_vector(5 downto 0);

signal sram_addr    : std_logic_vector(16 downto 0);
signal sram_we      : std_logic;
signal sram_di      : std_logic_vector(7 downto 0);
signal sram_do      : std_logic_vector(7 downto 0);

signal rom_cs,pal_cs : std_logic;

signal port_a_addr  : std_logic_vector(16 downto 0);
signal port_a_data  : std_logic_vector(7 downto 0);
signal port_a_write : std_logic;

begin

------------------
-- video output
------------------
video_r     <= do_palette(2 downto 0);
video_g     <= do_palette(5 downto 3);
video_b     <= do_palette(7 downto 6);
video_clk   <= clock_12mhz;
video_hs    <= hsync;
video_vs    <= vsync;

-----------------------
-- cpu write addressing
-----------------------
speech_we_n <= '0' when cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr(15 downto 11) = "10101" else '1';
misc_we_n   <= '0' when cpu_mreq_n = '0' and cpu_wr_n = '0' and cpu_addr(15 downto 11) = "10100" else '1';

-------------------------------
-- latch interrupt at last line 
-------------------------------
process(clock_12mhz, raz_int_n)
begin
	if raz_int_n = '0' then
		cpu_int_n <= '1';
	else
		if rising_edge(clock_12mhz) then
			if y_tile = "11100" and y_pixel = "000" then
				cpu_int_n <= '0';
			end if;
		end if;
	end if;
end process;

---------------------------
-- enable/disable interrupt
-- chip select sound
---------------------------
process (cpu_clock)
begin
	if falling_edge(cpu_clock) then
		if misc_we_n = '0' then
		
			if cpu_addr(2 downto 0) = "000" then
				raz_int_n <= cpu_data(0);
			end if;

			if cpu_addr(2 downto 0) = "111" then
				sound_cs_n <= cpu_data(0);
			end if;
			-- I don't think this can ever be true since misc_we_n is only low if
			-- cpu_addr(15 downto 11) = "10100"
			if cpu_addr(15 downto 11) = "10110" then
				sound2_cs_n <= cpu_data(0);
			end if;

		end if;
	end if;
end process;

------------------------------------
-- mux cpu data read 
------------------------------------
cpu_di <= ym_8910_data        when cpu_iorq_n = '0'                                    else
          dipsw               when cpu_addr(15 downto 11) = "10110" and mod_pick = '0' else
          dipsw               when cpu_addr(15 downto 11) = "10101" and mod_pick = '1' else
          "00" & pal16r6_data when cpu_addr(15 downto 11) = "10100" and mod_pick = '0' else
          sram_data_to_cpu;

-----------------------
-- mux sound and music
-----------------------
sound_string <= ("000" & unsigned(ym_8910_audio) & "00") + (to_unsigned((speech_sample+512),10) & "000") when mod_pick = '0' else
                 ("000" & unsigned(ym_8910_audio) & "00") + ("000" & unsigned(ym_8910_audio2) & "00");

------------------------------------
-- sram addressing scheme : 16 slots
------------------------------------
process(clock_12mhz)
begin
	if rising_edge(clock_12mhz) then
		sram_addr <= (others => '1');
		sram_we <= '0';
		sram_do <= (others => '0');
		------------------------------------------------- x sprite
		if addr_state = "0000" then
				sram_addr <= "0" & X"98" & "000" & sprite & "11";
		------------------------------------------------- y sprite
		elsif addr_state ="0001" then
				sram_addr <= "0" & X"98" & "000" & sprite & "10";
		------------------------------------------------- cpu
		elsif addr_state ="0010" then
			sram_addr <= "0" & cpu_addr;
			if cpu_wr_n = '0' and cpu_mreq_n = '0' then
				sram_do <= cpu_data;
				sram_we <= '1';
			end if;
		------------------------------------------------- background/sprite tile code
		elsif addr_state ="0011" then
			if is_sprite = '1' then
				sram_addr <= "0" & X"98" & "000" & sprite & "00";
			elsif mod_pick = '1' then
				sram_addr <= "0" & X"8" & "10" & y_tile & x_tile;
			else
				sram_addr <= "0" & X"9" & "00" & y_tile & x_tile;
			end if;
		------------------------------------------------- background/sprite color
		elsif addr_state ="0100" then
			if is_sprite = '1' then
				sram_addr <= "0" & X"98" & "000" & sprite & "01";
			else
				sram_addr <= "0" & X"9" & "10" & y_tile & x_tile;
			end if;
		------------------------------------------------- cpu
		elsif addr_state ="0110" then
			sram_addr <= "0" & cpu_addr;
			if cpu_wr_n = '0' and cpu_mreq_n = '0' then
				sram_do <= cpu_data;
				sram_we <= '1';
			end if;
		------------------------------------------------- background/sprite graph 1
		elsif addr_state ="0111" then
			sram_addr <= "1000" & tile_code;
		------------------------------------------------- background/sprite graph 2
		elsif addr_state ="1000" then
			sram_addr <= "1001" & tile_code;
		------------------------------------------------- cpu
		elsif addr_state ="1010" then
			sram_addr <= "0" & cpu_addr;
			if cpu_wr_n = '0' and cpu_mreq_n = '0' then
				sram_do <= cpu_data;
				sram_we <= '1';
			end if;
		------------------------------------------------- cpu
		elsif addr_state ="1110" then
			sram_addr <= "0" & cpu_addr;
			if cpu_wr_n = '0' and cpu_mreq_n = '0' then
				sram_do <= cpu_data;
				sram_we <= '1';
			end if;
		end if;
	end if;
end process;

--------------------------------------
-- sram reading background/sprite data
--------------------------------------
process(clock_12mhz)
begin
	if rising_edge(clock_12mhz) then
		if    addr_state = "0001" then
			if x_tile(0) = '0' then
				x_sprite <= sram_di;
			end if;
		elsif addr_state = "0010" then
			y_sprite <= sram_di;
		elsif addr_state = "0011" then
			sram_data_to_cpu <= sram_di;
		elsif addr_state = "0100" then
			if is_sprite = '1' then
				tile_code(10 downto 0) <= sram_di(5 downto 0) & 
												 ((y_diff_sprite(3) & x_tile(0)) xor sram_di(7 downto 6)) &
												 (y_diff_sprite(2 downto 0) xor (sram_di(7) & sram_di(7) & sram_di(7)));
				inv_sprite <= sram_di(7 downto 6);
			else
				tile_code(10 downto 0) <= sram_di & y_pixel;
			end if;
		elsif addr_state = "0101" then
			tile_code(12 downto 11) <= sram_di(4 ) & sram_di(5);
			tile_color <= sram_di(3 downto 0);
		elsif addr_state = "0111" then
			sram_data_to_cpu <= sram_di;
		elsif addr_state = "1000" then
			tile_graph1 <= sram_di;
		elsif addr_state = "1001" then
			tile_graph2 <= sram_di;
		elsif addr_state = "1011" then
			sram_data_to_cpu <= sram_di;
		elsif addr_state = "1111" then
			sram_data_to_cpu <= sram_di;
			tile_color_r <= tile_color;
			tile_graph1_r <= tile_graph1;
			tile_graph2_r <= tile_graph2;
			is_sprite_r <= is_sprite;

			if is_sprite = '1' and inv_sprite(0) = '1' then 
				for i in 0 to 7 loop
					tile_graph1_r(i) <= tile_graph1(7-i);
					tile_graph2_r(i) <= tile_graph2(7-i);
				end loop;
			end if;
			
			keep_sprite <= '0';
			if (y_diff_sprite(7 downto 4) = "1111") and (x_sprite > "00000000") and (y_sprite > "00000000") then
					keep_sprite <= '1';
			end if;
		end if;
	end if;
end process;

--------------------------------
-- sprite y position
--------------------------------
y_line <= y_tile & y_pixel;
y_diff_sprite <= std_logic_vector(unsigned(y_line) + unsigned(y_sprite) + 1);

------------------------------------------
-- read/write sprite line-memory addresing
------------------------------------------
process (clock_12mhz)
begin 
	if rising_edge(clock_12mhz) then
	
		if addr_state(0) = '1' then
			addr_ram_sprite <= std_logic_vector(unsigned(addr_ram_sprite) + to_unsigned(1,8));
		else
			addr_ram_sprite <= addr_ram_sprite;
		end if;
		
		if is_sprite = '1' and addr_state = "1111" and x_tile(0) = '0' then
			addr_ram_sprite <= '0' & x_sprite;
		end if;

		if is_sprite = '0' and addr_state = "1111" and x_tile = "00000" then
			addr_ram_sprite <= "000000001";
		end if;
		
	end if;
end process;

-------------------------------------
-- read/write sprite line-memory data
-------------------------------------
process (clock_12mhz)
begin
	if rising_edge(clock_12mhz) then
		if addr_state(0) = '0' then
			sprite_pixel_color <= ram_sprite(to_integer(unsigned(addr_ram_sprite)));
		else
			if is_sprite_r = '1' then
				if (keep_sprite = '1') and (addr_ram_sprite(8) = '0') then
						ram_sprite(to_integer(unsigned(addr_ram_sprite))) <= pixel_color_r;
				end if;
			else
				ram_sprite(to_integer(unsigned(addr_ram_sprite))) <= (others => '0');
			end if;
		end if;
	end if;
end process;

-----------------------------------------------------------------
-- serialize background/sprite graph to pixel + concatenate color
-----------------------------------------------------------------
process (clock_12mhz)
begin
	if rising_edge(clock_12mhz) then
pixel_color <=	tile_color_r & 
								tile_graph1_r(to_integer(unsigned(not x_pixel))) &
								tile_graph2_r(to_integer(unsigned(not x_pixel)));
	end if;
end process;

-------------------------------------------------
-- mux sprite color with background/sprite color
-------------------------------------------------
with sprite_pixel_color(1 downto 0) select
pixel_color_r <= pixel_color when "00", sprite_pixel_color when others;

-------------------------------------------------
video : entity work.video_gen
port map (
	clock_12mhz => clock_12mhz,
	hsync   => hsync,
	vsync   => vsync,
	hblank  => hblank,
	vblank  => vblank,
  hoffset => hoffset,
  voffset => voffset,
	vce     => vce,

	addr_state => addr_state,
	is_sprite  => is_sprite,
	sprite     => sprite,
	x_tile     => x_tile,
	y_tile     => y_tile,
	x_pixel    => x_pixel,
	y_pixel    => y_pixel,

	cpu_clock  => cpu_clock
);

pal_cs <= '1' when dn_addr(16 downto 6) = '1' & x"60" & "00" else '0';

palette : work.dpram generic map (6,8)
port map
(
	clock_a   => clock_12mhz,
	wren_a    => dn_wr and pal_cs,
	address_a => dn_addr(5 downto 0),
	data_a    => dn_data,

	clock_b   => clock_12mhz,
	address_b => pixel_color_r,
	q_b       => do_palette
);

Z80 : entity work.T80s
generic map(Mode => 0, T2Write => 1, IOWait => 1)
port map(
	RESET_n => not reset,
	CLK_n   => cpu_clock,
	WAIT_n  => not paused,
	INT_n   => cpu_int_n,
	NMI_n   => '1',
	BUSRQ_n => '1',
	M1_n    => open,
	MREQ_n  => cpu_mreq_n,
	IORQ_n  => cpu_iorq_n,
	RD_n    => open,
	WR_n    => cpu_wr_n,
	RFSH_n  => open,
	HALT_n  => open,
	BUSAK_n => open,
	A       => cpu_addr,
	DI      => cpu_di,
	DO      => cpu_data
);

ym2149 : entity work.ym2149
port map (
-- data bus
	I_DA        => cpu_data,
	O_DA        => ym_8910_data,
	O_DA_OE_L   => open,
-- control
	I_A9_L      => sound_cs_n,
	I_A8        =>     cpu_iorq_n or cpu_addr(3),
	I_BDIR      => not(cpu_iorq_n or cpu_addr(2)),
	I_BC2       => not(cpu_iorq_n or cpu_addr(1)),
	I_BC1       => not(cpu_iorq_n or cpu_addr(0)),
	I_SEL_L     => '1',
	O_AUDIO     => ym_8910_audio,
-- port a
	I_IOA       => joy_p1,
	O_IOA       => open,
	O_IOA_OE_L  => open,
-- port b
	I_IOB       => joy_p2,
	O_IOB       => open,
	O_IOB_OE_L  => open,

	ENA         => '1',
	RESET_L     => not reset,
	CLK         => x_pixel(1) and not paused -- note 6 Mhz!
);

ym2149_2 : entity work.ym2149
port map (
-- data bus
	I_DA        => cpu_data,
	O_DA        => open,
	O_DA_OE_L   => open,
-- control
	I_A9_L      => sound2_cs_n,
	I_A8        =>     cpu_iorq_n or cpu_addr(3),
	I_BDIR      => not(cpu_iorq_n or cpu_addr(2)),
	I_BC2       => not(cpu_iorq_n or cpu_addr(1)),
	I_BC1       => not(cpu_iorq_n or cpu_addr(0)),
	I_SEL_L     => '1',
	O_AUDIO     => ym_8910_audio2,
-- port a
	I_IOA       => "00000000",
	O_IOA       => open,
	O_IOA_OE_L  => open,
-- port b
	I_IOB       => "00000000",
	O_IOB       => open,
	O_IOB_OE_L  => open,

	ENA         => '1',
	RESET_L     => not reset,
	CLK         => x_pixel(1) and not paused -- note 6 Mhz!
);

bagman_speech : entity work.bagman_speech
port map(
	clock_12mhz  => clock_12mhz,
	Clk1MHz      => clock_1mhz,
	hclkn        => cpu_clock,
	adrCpu       => cpu_addr(2 downto 0),
	doCpu        => cpu_data(0),
	weSelSpeech  => speech_we_n,
	SpeechSample => speech_sample,
	dn_addr      => dn_addr,
	dn_data      => dn_data,
	dn_wr        => dn_wr
);

pal16r6 : entity work.bagman_pal16r6
port map(
	clk  => vsync,
	addr => cpu_addr(6 downto 0),
	data => pal16r6_data
);

rom_cs <= '1' when dn_addr(16 downto 14) < "101" else '0';

-- Multiplex rom loading with hs save/load
port_a_write <= (dn_wr and rom_cs) or hs_write_enable;
port_a_addr  <= dn_addr(16 downto 0) when ((dn_wr and rom_cs) = '1') else "0" & hs_address(15 downto 0);
port_a_data  <= dn_data when ((dn_wr and rom_cs) = '1') else hs_data_in;

sram : work.dpram generic map (17,8)
port map
(
	clock_a   => clock_12mhz,
	wren_a    => port_a_write,
	address_a => port_a_addr,
	data_a    => port_a_data,
	q_a				=> hs_data_out,

	clock_b   => not clock_12mhz,
	wren_b    => sram_we,
	address_b => sram_addr,
	data_b    => sram_do,
	q_b       => sram_di
);

end architecture;
