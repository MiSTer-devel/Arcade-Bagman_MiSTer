---------------------------------------------------------------------------------
-- Video generator - Dar - Feb 2014
---------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all,ieee.numeric_std.all;

entity video_gen is
port(
	clock_12mhz : in std_logic;
	hsync       : out std_logic;
	vsync       : out std_logic;
	hblank      : out std_logic;
	vblank      : out std_logic;
	hoffset     : in std_logic_vector(3 downto 0);
	voffset     : in std_logic_vector(3 downto 0);
	vce         : out std_logic;

	addr_state  : out std_logic_vector(3 downto 0);
	is_sprite   : out std_logic;
	sprite      : out std_logic_vector(2 downto 0);
	x_tile      : out std_logic_vector(4 downto 0);
	y_tile      : out std_logic_vector(4 downto 0);
	x_pixel     : out std_logic_vector(2 downto 0);
	y_pixel     : out std_logic_vector(2 downto 0);

	cpu_clock   : out std_logic
);
end video_gen;

architecture struct of video_gen is
signal hcnt    : unsigned (8 downto 0) := to_unsigned(511,9);
signal vcnt    : unsigned (8 downto 0) := to_unsigned(511,9);
signal vcnt_r  : unsigned (8 downto 0) := to_unsigned(511,9);

signal hoff    : integer range -8 to 7;
signal voff    : integer range -8 to 7;

signal enable_clk : std_logic := '0';

begin

addr_state <= std_logic_vector(hcnt(2 downto 0)) & enable_clk;
is_sprite  <= not hcnt(8);
sprite     <= std_logic_vector(hcnt(6 downto 4));
x_tile     <= std_logic_vector(hcnt(7 downto 3));
y_tile     <= std_logic_vector(vcnt_r(7 downto 3));
x_pixel    <= std_logic_vector(hcnt(2 downto 0));
y_pixel    <= std_logic_vector(vcnt_r(2 downto 0));

hoff       <= to_integer(signed(hoffset));
voff       <= to_integer(signed(voffset));

-- Compteur horizontal : 511-128+1=384 pixels
-- 128 à 175 :  48 pixels fin de ligne 
-- 176 à 255 :  80 pixels debut de ligne
-- 256 à 511 : 256 pixels affichés (32 tiles)

-- Compteur vertical   : 511-248+1=264 lignes
-- 496 à 511 :  16 lignes fin de trame 
-- 248 à 271 :  24 lignes debut de trame
-- 272 à 495 : 224 lignes affichées (28 tiles)

-- Synchro horizontale : hcnt=[176 à 207] (32 pixels)
-- Synchro verticale   : vcnt=[248 à 255] ( 8 lignes)

vce <= enable_clk;

process(clock_12mhz)
begin

	if rising_edge(clock_12mhz) then

		enable_clk <= not enable_clk;
		cpu_clock <= not hcnt(0);

		if enable_clk = '1' then

			if hcnt = 511 then 
				hcnt <= to_unsigned (128,9);
				vcnt_r <= vcnt;
			else
				hcnt <= hcnt + 1;
			end if; 

			if hcnt = to_unsigned((175+ hoff),9) then
				if vcnt = 511 then
					vcnt <= to_unsigned(248,9);
				else
					vcnt <= vcnt + 1;
				end if;
			end if;

			if    hcnt = to_unsigned((175+ hoff),9) then hsync <= '0';
			elsif hcnt = to_unsigned((175+ hoff+ 29),9) then hsync <= '1';
			end if;    

			-- Turn sync on - could be at the end of this frame or the start of the next
			if    vcnt = to_unsigned(511+ voff,9) then vsync <= '0';
			elsif vcnt = to_unsigned(247+ voff,9) then vsync <= '0';
			-- Similarly, turn it off. The offsets may underflow or overflow, but
			-- will be correct.
			elsif vcnt = to_unsigned(512+ voff,9) then vsync <= '1';
			elsif vcnt = to_unsigned(250+ voff,9) then vsync <= '1';
			end if;    

			if    hcnt = (127+8+1) then hblank <= '1'; -- +8 = retard du shift_register + 1 pixel
			elsif hcnt = (255+8+1) then hblank <= '0';
			end if;    

			if    vcnt = (495+1+1) then vblank <= '1';
			elsif vcnt = (271+1+1) then vblank <= '0';
			end if;   

		end if;
	end if;
end process;

end architecture;
