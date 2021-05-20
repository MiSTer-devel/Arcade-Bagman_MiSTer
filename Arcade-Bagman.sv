//============================================================================
//  Arcade: Bagman
//
//  Port to MiSTer
//  Copyright (C) 2017,2020 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign HDMI_ARX = status[1] ? 8'd16 : (status[2] | mod_squa) ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : (status[2] | mod_squa) ? 8'd3 : 8'd4;

`include "build_id.v" 
localparam CONF_STR = {
	"A.BAGMAN;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H1H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"DIP;",
	"-;",
	"h1O6,Control P1,Kbd/Joy,Spinner;",
	"h1O7,Control P2,Kbd/Joy,Spinner;",
	"h1-;",
	"R0,Reset;",
	"J1,Fire 1,Fire 2,Start 1P,Start 2P,Coin;",
	"jn,A,B,Start,Select,R;",
	"jp,B,A,Start,,Select;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys, clk_1m, clk_24m,clk_48m;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 12mhz
	.outclk_1(clk_1m),
	.outclk_2(clk_24m),
	.outclk_3(clk_48m),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_index;

wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy1 = mod_squa ? joystick_0 : (joystick_0 | joystick_1);
wire [15:0] joy2 = mod_squa ? joystick_1 : (joystick_0 | joystick_1); 
wire [15:0] joy  = joy1 | joy2;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask({mod_squa,direct_video}),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),


	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire1       <= pressed; // space
			'h014: btn_fire2       <= pressed; // ctrl

			'h005: btn_start_1     <= pressed; // F1
			'h006: btn_start_2     <= pressed; // F2
			// JPAC/IPAC/MAME Style Codes

			'h016: btn_start_1     <= pressed; // 1
			'h01E: btn_start_2     <= pressed; // 2
			'h02E: btn_coin_1      <= pressed; // 5
			'h036: btn_coin_2      <= pressed; // 6
			'h02D: btn_up_2        <= pressed; // R
			'h02B: btn_down_2      <= pressed; // F
			'h023: btn_left_2      <= pressed; // D
			'h034: btn_right_2     <= pressed; // G
			'h01C: btn_fire_2      <= pressed; // A
		endcase
	end
end

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_fire1 = 0;
reg btn_fire2 = 0;

reg btn_start_1=0;
reg btn_start_2=0;
reg btn_coin_1=0;
reg btn_coin_2=0;
reg btn_up_2=0;
reg btn_down_2=0;
reg btn_left_2=0;
reg btn_right_2=0;
reg btn_fire_2=0;

wire m_up     = btn_up      | joy1[3];
wire m_down   = btn_down    | joy1[2];
wire m_left   = btn_left    | joy1[1];
wire m_right  = btn_right   | joy1[0];
wire m_fire1  = btn_fire1   | joy1[4];
wire m_fire2  = btn_fire2   | joy1[5];

wire m_up_2   = btn_up_2    | joy2[3];
wire m_down_2 = btn_down_2  | joy2[2];
wire m_left_2 = btn_left_2  | joy2[1];
wire m_right_2= btn_right_2 | joy2[0];
wire m_fire1_2= btn_fire_2  | joy2[4];
wire m_fire2_2=               joy2[5];

wire m_start1 = btn_start_1 | joy[6];
wire m_start2 = btn_start_2 | joy[7];
wire m_coin   = btn_coin_1  | btn_coin_2 | joy[8];

reg [1:0] m_dial1;
always @(*) begin
  if (m_dial1 != 3 && !status[6])  m_dial1 <= 3;
  else if (m_down)   m_dial1 <= 1;
  else if (m_up)     m_dial1 <= 2;
  else               m_dial1 <= 3;
end

reg [1:0] m_dial2;
always @(*) begin
  if (m_dial2 != 3 && !status[7])  m_dial2 <= 3;
  else if (m_down_2) m_dial2 <= status[7] ? 2'd2 : 2'd1;
  else if (m_up_2)   m_dial2 <= status[7] ? 2'd1 : 1'd2;
  else               m_dial2 <= 3;
end

wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g;
wire [1:0] b;
wire ce_pix;

arcade_video #(256,224,8) arcade_video
(
	.*,

	.clk_video(clk_48m),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.no_rotate(status[2] | direct_video | mod_squa),
	.rotate_ccw(0),

	.fx(status[5:3])
);


wire [12:0] audio;
assign AUDIO_L = {audio, 3'b000};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;

reg mod_sbag = 0;
reg mod_pick = 0;
reg mod_squa = 0;

always @(posedge clk_sys) begin
	reg [7:0] mod = 0;
	if (ioctl_wr & (ioctl_index==1)) mod <= ioctl_dout;

	mod_sbag <= (mod == 1);
	mod_pick <= (mod == 2);
	mod_squa <= (mod == 3);
end

reg [7:0] sw[8];
always @(posedge clk_sys) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout; 

bagman bagman
(
	.clock_12mhz(clk_sys),
	.clock_1mhz(clk_1m),
	.reset(RESET | status[0] | buttons[1]),

	.vce(ce_pix),
	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_hs(hs),
	.video_vs(vs),
	.hblank(hblank),
	.vblank(vblank),

	.mod_pick(mod_pick|mod_squa),

	.joy_p1(~{m_fire1,   mod_squa ? m_dial1 : {m_down,   m_up  }, m_right,   m_left,   m_start1 | (mod_sbag & m_fire2),   1'b0, m_coin}),
	.joy_p2(~{m_fire1_2, mod_squa ? m_dial2 : {m_down_2, m_up_2}, m_right_2, m_left_2, m_start2 | (mod_sbag & m_fire2_2), 1'b0, 1'b0  }),
	.dipsw(sw[0]),

	.sound_string(audio),

	.dn_addr(ioctl_addr[16:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr & !ioctl_index)
);

endmodule
