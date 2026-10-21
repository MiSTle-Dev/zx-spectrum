//============================================================================
//  Sinclair ZX Spectrum host board
// 
//  Port to MIST board. 
//  Copyright (C) 2015 Sorgelig
//
//  Based on sample ZX Spectrum code by Goran Devic
//  Ported 2026 to MiSTle (http://github.com/MiSTle-dev)
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

//
// TODO/Remarks:
// - RAM on Nano os 2M*32, we currently use only 16bits. The zxspectrum actually
//   only uses 2M*16 for various RAM variants. It uses other parts for zx rom,
//   tape and gs roms. These are not fully ported to the nano and will not work
//   in the current state. TODO: Use all 32 bits and properly handle sdram row
//   and address widths
//


module zxspectrum
(
   input	 CLOCK_27,	// Input clock 27 MHz

   output [5:0]	 leds_n,
   input [1:0]	 s,

`ifdef NANO
   // "Magic" port names that the gowin compiler connects to the on-chip SDRAM
   output	 O_sdram_clk,
   output	 O_sdram_cke,
   output	 O_sdram_cs_n,	// chip select
   output	 O_sdram_cas_n,	// columns address select
   output	 O_sdram_ras_n,	// row address select
   output	 O_sdram_wen_n,	// write enable
   inout [31:0]	 IO_sdram_dq,	// 32 bit bidirectional data bus
   output [10:0] O_sdram_addr,	// 11 bit multiplexed address bus
   output [1:0]	 O_sdram_ba,	// two banks
   output [3:0]	 O_sdram_dqm,	// 32/4
`else
   output [12:0] SDRAM_A,
   inout [15:0]	 SDRAM_DQ, 
   output	 SDRAM_DQML,
   output	 SDRAM_DQMH,
   output	 SDRAM_nWE,
   output	 SDRAM_nCAS,
   output	 SDRAM_nRAS,
   output	 SDRAM_nCS,
   output [1:0]	 SDRAM_BA,
   output	 SDRAM_CLK,
   output	 SDRAM_CKE,
`endif

   // FPGA Companion
   input	 mcu_din,
   output	 mcu_dout,
   input	 mcu_clk,
   input	 mcu_ss,
   output	 mcu_intn,
   input	 mcu_spare,

   // SD card slot
   output	 sd_clk,
   inout	 sd_cmd,	// MOSI
   inout [3:0]	 sd_dat,	// 0: MISO
           
 
   // hdmi/tdms
   output	 tmds_clk_n,
   output	 tmds_clk_p,
   output [2:0]	 tmds_d_n,
   output [2:0]	 tmds_d_p
);
// `default_nettype none

wire [5:0] leds;
assign leds_n = ~leds;   
   
`ifdef NANO
wire [`SDRAM_ROW_WIDTH-1:0] SDRAM_A;
assign O_sdram_addr = SDRAM_A;
wire [15:0] SDRAM_DQ;   
assign IO_sdram_dq = { 16'h0000, SDRAM_DQ };
wire	 SDRAM_DQML, SDRAM_DQMH;
assign O_sdram_dqm = { 2'b00, SDRAM_DQMH, SDRAM_DQML };
wire	 SDRAM_nWE;
assign O_sdram_wen_n = SDRAM_nWE;
wire	 SDRAM_nCAS;
assign O_sdram_cas_n = SDRAM_nCAS;
wire	 SDRAM_nRAS;
assign O_sdram_ras_n = SDRAM_nRAS;
wire	 SDRAM_nCS;
assign O_sdram_cs_n = SDRAM_nCS;
wire [1:0] SDRAM_BA;
assign O_sdram_ba = SDRAM_BA;
wire	 SDRAM_CLK;
assign O_sdram_clk = SDRAM_CLK;
wire	 SDRAM_CKE;
assign O_sdram_cke = SDRAM_CKE;
`endif
   
localparam CONF_BDI   = "(BDI)";
localparam CONF_PLUSD = "(+D) ";

`ifdef DISABLED   
`include "build_id.v"
localparam CONF_STR = {
	"SPECTRUM;;",
	"S1,TRDIMGDSKMGT,Load Disk;",
	"F,TAPCSWTZX,Load Tape;",
	"O6,Fast tape load,On,Off;",
	"O7,Joystick swap,Off,On;",
	"O89,Video timings,ULA-48,ULA-128,Pentagon;",
	"OFG,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"OAC,Memory,Standard 128K,Pentagon 1024K,Profi 1024K,Standard 48K,+2A/+3;",
	"ODE,Features,ULA+ & Timex,ULA+,Timex,None;",
	"OHI,MMC Card,Off,divMMC,ZXMMC;",
	"OKL,General Sound,512KB,1MB,2MB,Disabled;",
	"T0,Reset;",
	"V,v3.40.",`BUILD_DATE
};
`endif

`ifdef VERILATOR
import "DPI-C" function void display_simtime();
`endif
   
////////////////////   CLOCKS   ///////////////////
wire locked;
wire clk_sys;
wire clk_pixel;      

// clk sys   = 113.5/56/28 MHz (= SDRAM_CLK)
// clk hdmi  = 141.875
// clk pixel =  28.375
   
`ifdef VERILATOR
// ------------------- clock simulation --------------------
assign clk_sys = CLOCK_27;
assign SDRAM_CLK = CLOCK_27;   

reg [5:0] lock_cnt;
 always @(posedge clk_sys)
  if(lock_cnt != 6'd63)
    lock_cnt <= lock_cnt + 6'd1;   

assign locked = lock_cnt == 6'd63;   

`ifdef SYS_CLK_28MHZ
   assign clk_pixel = clk_sys;   // 28
`else   
 `ifdef SYS_CLK_56MHZ
   reg pcnt;
   always @(posedge clk_sys)
     pcnt <= !pcnt;
   
   assign clk_pixel = pcnt;      // 56/2
 `else   
   reg [1:0] pcnt;
   always @(posedge clk_sys)
     pcnt <= pcnt + 2'd1;
   
   assign clk_pixel = pcnt[1];   // 113/4
 `endif
`endif
`else // !`ifdef SYS_CLK_28MHZ
   
// ------------------- hardware plls --------------------
wire  clk_pixel_x5;

// This currently only supports the GW2AR-LV18 (e.g. Tang Nano 20k)
// The HDMI is clocked at 141 MHz (28 * 5) and the system clock
// is 28 MHz. No turbo or extended RAM/ROM modes are supported/enabled
`ifndef SYS_CLK_28MHZ
   Error HW is currently only supported at 28Mhz
`endif

rPLL rpll_inst (
    .CLKOUT(clk_pixel_x5),
    .LOCK(locked),
    .CLKOUTP(),
    .CLKOUTD(),
    .CLKOUTD3(),
    .RESET(1'b0),
    .RESET_P(1'b0),
    .CLKIN(CLOCK_27),
    .CLKFB(1'b0),
    .FBDSEL(6'b000000),
    .IDSEL(6'b000000),
    .ODSEL(6'b000000),
    .PSDA(4'b0000),
    .DUTYDA(4'b0000),
    .FDLY(4'b0000)
);

defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.IDIV_SEL = 3;
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.FBDIV_SEL = 20;
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.ODIV_SEL = 8;
defparam rpll_inst.PSDA_SEL = "1000";
defparam rpll_inst.DYN_DA_EN = "true";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

CLKDIV clkdiv_inst (
    .CLKOUT(clk_sys),
    .HCLKIN(clk_pixel_x5),
    .RESETN(locked),
    .CALIB(1'b0)
);

defparam clkdiv_inst.DIV_MODE = "5";
defparam clkdiv_inst.GSREN = "false";

assign clk_pixel = clk_sys;
assign SDRAM_CLK = !clk_sys; 
   
`endif // !`ifdef VERILATOR   

wire kbd_toggle;
wire [7:0] kbd_data;      
     
reg [4:0] turbo = 5'b11111, turbo_key = 5'b11111;

reg  ce_psg;  //1.75MHz
reg  ce_7mp;
reg  ce_7mn;
reg  ce_14m;

reg  pause;
reg  cpu_en = 1;
reg  ce_cpu_tp;
reg  ce_cpu_tn;

wire ce_cpu_sn;
wire ce_cpu_sp;

wire cpu_p = ~&turbo ? ce_cpu_tp : ce_cpu_sp;
wire cpu_n = ~&turbo ? ce_cpu_tn : ce_cpu_sn;

wire ce_cpu_p = cpu_en & cpu_p;
wire ce_cpu_n = cpu_en & cpu_n;
wire ce_cpu   = cpu_en & ce_cpu_tp;
wire ce_wd1793 = ce_cpu;
wire ce_u765 = ce_cpu;
wire ce_tape = ce_cpu;

// ------------ main clock generator ----------------

// TOOD: scale turbo array to match clock range
   
`ifdef SYS_CLK_28MHZ
reg [3:0] counter = 0;
always @(posedge clk_sys) begin
	counter <=  counter + 1'd1;

	ce_14m  <= !counter[0];
	ce_7mp  <= !counter[1] & !counter[0];
	ce_7mn  <=  counter[1] & !counter[0];
	ce_psg  <= !counter[3:0] & ~pause;

	ce_cpu_tp <= !(counter & turbo);
	ce_cpu_tn <= !((counter & turbo) ^ turbo ^ turbo[4:1]);
end
`else // !`ifdef SYS_CLK_56MHZ
`ifdef SYS_CLK_56MHZ
reg [4:0] counter = 0;
always @(posedge clk_sys) begin
	counter <=  counter + 1'd1;

	ce_14m  <= !counter[1:0];
	ce_7mp  <= !counter[2] & !counter[1:0];
	ce_7mn  <=  counter[2] & !counter[1:0];
	ce_psg  <= !counter[4:0] & ~pause;

	ce_cpu_tp <= !(counter & turbo);
	ce_cpu_tn <= !((counter & turbo) ^ turbo ^ turbo[4:1]);
end
`else // !`ifdef SYS_CLK_56MHZ
reg [5:0] counter = 0;
always @(posedge clk_sys) begin
	counter <=  counter + 1'd1;

	ce_14m  <= !counter[2:0];
	ce_7mp  <= !counter[3] & !counter[2:0];
	ce_7mn  <=  counter[3] & !counter[2:0];
	ce_psg  <= !counter[5:0] & ~pause;

	ce_cpu_tp <= !(counter & turbo);
	ce_cpu_tn <= !((counter & turbo) ^ turbo ^ turbo[4:1]);
end
`endif
`endif

wire [31:0] status = 32'd0;

always @(posedge clk_sys) begin
	reg [9:4] old_Fn;
	old_Fn <= Fn[9:4];

	if(reset) pause <= 0;

	if(!mod) begin
		if(~old_Fn[4] & Fn[4]) turbo_key <= 5'b11111; //3.5 MHz
		if(~old_Fn[5] & Fn[5]) turbo_key <= 5'b01111; //  7 Mhz
		if(~old_Fn[6] & Fn[6]) turbo_key <= 5'b00111; // 14 MHz
		if(~old_Fn[7] & Fn[7]) turbo_key <= 5'b00011; // 28 MHz
		if(~old_Fn[8] & Fn[8]) turbo_key <= 5'b00001; // 56 MHz
		if(~old_Fn[9] & Fn[9]) pause <= ~pause;
	end
end

wire [4:0] turbo_req = turbo_key;
always @(posedge clk_sys) begin
	reg [1:0] timeout;

	if(cpu_n) begin
		if(timeout) timeout <= timeout + 1'd1;
		if(turbo != turbo_req) begin
			cpu_en  <= 0;
			timeout <= 1;
			turbo   <= turbo_req;
		end else if(!cpu_en & !timeout & ram_ready) begin
			cpu_en  <= ~pause;
		end else if(!turbo[4:3] & !ram_ready) begin // SDRAM wait for 14MHz/28MHz/56MHz turbo
			cpu_en  <= 0;
		end else if(cpu_en & pause) begin
			cpu_en  <= 0;
		end
	end
end


//////////////////   MIST ARM I/O   ///////////////////
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire  [7:0] joystick;    // digital joystick data sent from companion

`ifdef DISABLED
wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire  [7:0] joy0 = status[7] ? joystick_1 : joystick_0; // Kempston
wire  [7:0] joy1 = status[7] ? joystick_0 : joystick_1; // Sinclair
`else
wire  [7:0] joy0 = 8'h00;    // Kempston
wire  [7:0] joy1 = joystick; // Sinclair
`endif
   
wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire        ypbpr;

wire 			sd_rd_plus3;
wire 			sd_wr_plus3;
wire [31:0] sd_lba_plus3;
wire [7:0]  sd_buff_din_plus3;

wire 			sd_rd_wd;
wire 			sd_wr_wd;
wire [31:0] sd_lba_wd;
wire [7:0]  sd_buff_din_wd;

wire        sd_busy_mmc;
wire        sd_rd_mmc;
wire        sd_wr_mmc;
wire [31:0] sd_lba_mmc;
wire  [7:0] sd_buff_din_mmc;

wire [31:0] sd_lba = sd_busy_mmc ? sd_lba_mmc : (plus3_fdd_ready ? sd_lba_plus3 : sd_lba_wd);
wire  [1:0] sd_rd = { sd_rd_plus3 | sd_rd_wd, sd_rd_mmc };
wire  [1:0] sd_wr = { sd_wr_plus3 | sd_wr_wd, sd_wr_mmc };

wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din = sd_busy_mmc ? sd_buff_din_mmc : (plus3_fdd_ready ? sd_buff_din_plus3 : sd_buff_din_wd);
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [31:0] img_size;

wire        sd_ack_conf;
wire        sd_conf;
wire        sd_sdhc;

///////////////////   CPU   ///////////////////
wire [15:0] addr;
logic [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        nM1;
wire        nMREQ;
wire        nIORQ;
wire        nRD;
wire        nWR;
wire        nRFSH;
wire        nBUSACK;
wire        nINT;

wire        io_wr = ~nIORQ & ~nWR & nM1;
wire        io_rd = ~nIORQ & ~nRD & nM1;
wire        m1    = ~nM1 & ~nMREQ;

// for edge detection
reg         old_wr;
reg         old_rd;
reg         old_m1;

wire[211:0]	cpu_reg;  // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
wire [15:0] reg_DE  = cpu_reg[111:96];
wire  [7:0] reg_A   = cpu_reg[7:0];

assign leds[1] = reset;

T80pa cpu
(
	.RESET_n(~reset),
	.CLK(clk_sys),
	.CEN_p(ce_cpu_p),
	.CEN_n(ce_cpu_n),
	.WAIT_n(1),
	.INT_n(nINT),
	.NMI_n(~NMI),
	.BUSRQ_n(1'b1),
	.M1_n(nM1),
	.MREQ_n(nMREQ),
	.IORQ_n(nIORQ),
	.RD_n(nRD),
	.WR_n(nWR),
	.RFSH_n(nRFSH),
	.HALT_n(),
	.BUSAK_n(nBUSACK),
	.A(addr),
	.DO(cpu_dout),
	.DI(cpu_din),

        .DIR(212'd0),
	.REG(cpu_reg)
);

`ifndef ENABLE_GS
wire gs_sel = 1'b0;
`endif   
   
always_comb begin
	casex({nMREQ, ~nM1 | nIORQ | nRD, fdd_sel | fdd_sel2 | plus3_fdd, mf3_port, addr[7:0]==8'h1F, portBF, gs_sel, psg_enable, ulap_sel, addr[0]})
		'b0XXXXXXXXX: cpu_din = ram_dout;
		'b101XXXXXXX: cpu_din = fdd_dout;
		'b1001XXXXXX: cpu_din = (addr[14:13] == 2'b11 ? page_reg : page_reg_plus3);
`ifdef ENABLE_MOUSE
		'b10001XXXXX: cpu_din = mouse_sel ? mouse_data : {2'b00, joy0[5:0]};
`else
		'b10001XXXXX: cpu_din = {2'b00, joy0[5:0]};
`endif
		'b100001XXXX: cpu_din = {page_scr_copy, 7'b1111111};
`ifdef ENABLE_GS
		'b1000001XXX: cpu_din = gs_dout;
`endif
		'b10000001XX: cpu_din = (addr[14] ? sound_data : 8'hFF);
		'b100000001X: cpu_din = ulap_dout;
		'b1000000001: cpu_din = port_ff;
		'b1000000000: cpu_din = {1'b1, ~tape_in, 1'b1, key_data[4:0] & ({5{addr[12]}} | ~{joy1[1:0], joy1[2], joy1[3], joy1[4]})};
		default:      cpu_din = 8'hFF;
	endcase
end

wire init_reset = !locked || s[1];

reg  NMI;
reg  reset;
wire osd_reset;   
reg  cold_reset_btn;
reg  warm_reset_btn;
reg  shdw_reset_btn;
wire cold_reset = cold_reset_btn | init_reset;
wire warm_reset = warm_reset_btn;
wire shdw_reset = shdw_reset_btn & ~plus3;

// F10          = reset
// F11          = NMI
// Alt+F11      = cold reset
// Ctrl+F11     = warm reset
// Alt+Ctrl+F11 = shadow rom reset
always @(posedge clk_sys) begin
	reg old_F11;

	old_F11 <= Fn[11];

	reset <= buttons[1] | status[0] | cold_reset | warm_reset | shdw_reset | Fn[10] | osd_reset;

	if(reset | ~Fn[11]) NMI <= 0;
	else if(~old_F11 & Fn[11] & (mod[2:1] == 0)) NMI <= 1;

	cold_reset_btn <= (mod[2:1] == 1) & Fn[11];
	warm_reset_btn <= (mod[2:1] == 2) & Fn[11];
	shdw_reset_btn <= (mod[2:1] == 3) & Fn[11];
end

always @(posedge clk_sys) begin
	old_rd <= io_rd;
	old_wr <= io_wr;
	old_m1 <= m1;
end

//////////////////   MEMORY   //////////////////
reg  [20:0] ram_addr;
reg   [7:0] ram_din;
reg         ram_we;
reg         ram_rd;
wire  [7:0] ram_dout;
wire        ram_ready;

always_comb begin
	casex({page_special, addr[15:14]})
	        // rom is currently mapped directly to block rom and not used via external sdram
		'b0_00: ram_addr = { 3'b101, page_rom, addr[13:0] }; //ROM
		'b0_01: ram_addr = {   4'd0, 3'd5,     addr[13:0] }; //Non-special page modes
		'b0_10: ram_addr = {   4'd0, 3'd2,     addr[13:0] };
		'b0_11: ram_addr = {   1'b0, page_ram, addr[13:0] };
		'b1_00: ram_addr = {   4'd0,                       |page_reg_plus3[2:1], 2'b00, addr[13:0] }; //Special page modes
		'b1_01: ram_addr = {   4'd0, |page_reg_plus3[2:1], &page_reg_plus3[2:1],  1'b1, addr[13:0] };
		'b1_10: ram_addr = {   4'd0,                       |page_reg_plus3[2:1], 2'b10, addr[13:0] };
		'b1_11: ram_addr = {   4'd0,     ~page_reg_plus3[2] & page_reg_plus3[1], 2'b11, addr[13:0] };
	endcase

        ram_din <= cpu_dout;
	ram_rd = ~nMREQ & ~nRD & (addr[15] || addr[14]);  // exclude rom access
	ram_we = (page_special | addr[15] | addr[14] | ((plusd_mem | mf128_mem) & addr[13])) & ~nMREQ & ~nWR;
end

// 16k embedded rom
reg [7:0] bsrom[16*1024];
initial $readmemh("roms/48_rom.hex", bsrom);

reg [7:0] bsrom_dout;
always @(posedge clk_sys)
   bsrom_dout <= bsrom[addr[13:0]];

// On MiST and MiSTer rom was placed in SDRAM. Here it's in bsram and is thus
// mapped into the sdram output
wire [15:0] sdram_dout_int;
assign sdram_dout = (addr[15:14] == 2'b00)?
		    { bsrom_dout, bsrom_dout }:
		    sdram_dout_int;   

sdram ram
(
	.*,
	.init_n(locked),
	.clk(clk_sys),
`ifdef SYS_CLK_28MHZ
	.clkref(ce_cpu_n),
`else
  `ifdef SYS_CLK_56MHZ
	.clkref(ce_7mn),
  `else
	.clkref(ce_14m),
  `endif
`endif

	// port1 is CPU/tape
	.port1_req(sdram_req),
	.port1_a(sdram_addr[23:1]),
	.port1_ds(sdram_we ? {sdram_addr[0], ~sdram_addr[0]} : 2'b11),
	.port1_d({sdram_din, sdram_din}),
	.port1_q(sdram_dout_int),
	.port1_we(sdram_we),
	.port1_ack(sdram_ack),
 `ifdef ENABLE_GS
	// port 2 is General Sound CPU
	.port2_req(gs_sdram_req),
	.port2_a(gs_sdram_addr[23:1]),
	.port2_ds(gs_sdram_we ? {gs_sdram_addr[0], ~gs_sdram_addr[0]} : 2'b11),
	.port2_q(gs_sdram_dout),
	.port2_d({gs_sdram_din, gs_sdram_din}),
	.port2_we(gs_sdram_we),
	.port2_ack(gs_sdram_ack)
`else
	// port 2 is unused
	.port2_req(1'b0),
	.port2_a(23'd0),
	.port2_ds(2'b00),
	.port2_q(),
	.port2_d(16'h0000),
	.port2_we(1'b0),
	.port2_ack() 
`endif
);

assign SDRAM_CKE = 1;
   
// CPU/tape port control
reg  [24:0] sdram_addr;
wire [15:0] sdram_dout;
reg   [7:0] sdram_din;
wire        sdram_ack;
reg         sdram_req;
reg         sdram_we;

reg         ram_rd_old;
reg         ram_rd_old2; // use the delayed signal to wait for mf128_mem, plusd_mem, etc...
reg         ram_we_old;
wire        new_ram_req = (~ram_rd_old2 & ram_rd_old) || (~ram_we_old & ram_we);

always @(posedge clk_sys) begin

	ram_rd_old  <= ram_rd;
	ram_rd_old2 <= ram_rd_old;
	ram_we_old <= ram_we;

	if (new_ram_req) begin

		sdram_req <= ~sdram_req;
		sdram_we <= ram_we;
		sdram_din <= ram_din;
		sdram_addr <= ram_addr;
	end
end

assign ram_dout = sdram_addr[0] ? sdram_dout[15:8] : sdram_dout[7:0];
assign ram_ready = (sdram_ack == sdram_req) & ~new_ram_req;

`ifdef ENABLE_GS
// GS port control
wire [20:0] gs_mem_addr;
wire  [7:0] gs_mem_dout;
wire  [7:0] gs_mem_din;
wire        gs_mem_rd;
wire        gs_mem_wr;
wire        gs_mem_ready;
reg   [7:0] gs_mem_mask;

always_comb begin
	gs_mem_mask = 0;
	case(status[21:20])
		0: if(gs_mem_addr[20:19]) gs_mem_mask = 8'hFF; // 512K
		1: if(gs_mem_addr[20])    gs_mem_mask = 8'hFF; // 1024K
		2,3:                      gs_mem_mask = 0;
	endcase
end

reg  [24:0] gs_sdram_addr;
wire [15:0] gs_sdram_dout;
reg   [7:0] gs_sdram_din;
wire        gs_sdram_ack;
reg         gs_sdram_req;
reg         gs_sdram_we;

wire	    gs_rom_we = 1'b0;    // was ioctl wr
reg         gs_mem_rd_old;
reg         gs_mem_wr_old;
wire        new_gs_mem_req = (~gs_mem_rd_old & gs_mem_rd) || (~gs_mem_wr_old & gs_mem_wr) || gs_rom_we;

always @(posedge clk_sys) begin

	gs_mem_rd_old <= gs_mem_rd;
	gs_mem_wr_old <= gs_mem_wr;

	if (new_gs_mem_req) begin
		// don't issue a new request if a read followed by a read and the current word address is the same as the previous
		if (gs_sdram_we | gs_rom_we | gs_mem_wr | gs_sdram_addr[20:1] != gs_mem_addr[20:1]) begin
		   gs_sdram_req <= ~gs_sdram_req;
		   gs_sdram_we <= gs_rom_we | gs_mem_wr;
		   gs_sdram_din <= gs_mem_din;  // gs_rom_we ? ioctl_dout : gs_mem_din;
		end
	        // rom/ioctl write address was mapped here
		gs_sdram_addr <= gs_mem_addr;
	end
end

assign gs_mem_dout = gs_sdram_addr[0] ? gs_sdram_dout[15:8] : gs_sdram_dout[7:0];
assign gs_mem_ready = (gs_sdram_ack == gs_sdram_req) & ~new_gs_mem_req;
`endif
   
// VRAM
wire vram_sel = (ram_addr[20:16] == 1) & ram_addr[14];
`ifdef DISABLED
vram vram
(
    .clock(clk_sys),

    .wraddress({ram_addr[15], ram_addr[13:0]}),
    .data(ram_din),
    .wren(ram_we & vram_sel),

    .rdaddress(vram_addr),
    .q(vram_dout)
);
`else
// on a standard spectrum the VRAM is from $4000 to $57ff and
// attribute ram is from $5800 to $5aff. Thus a total of 8k VRAM
// is sufficient for a standard spectrum. Extended video modes of
// later and/or upgraded models require up to 32k VRAM
reg [7:0] vram_dout_L;   
`ifdef EXTENDED_VIDEO
reg [7:0] vram [32768];
always @(posedge clk_sys) begin
   if(ram_we & vram_sel)
     vram[{addr[15], addr[13:0]}] <= ram_din;
   
   vram_dout_L <= vram[vram_addr];   
end   
`else
reg [7:0] vram [8192];
always @(posedge clk_sys) begin
   // limit write access to $4000-$5fff
   if(ram_we & vram_sel && addr[15:13] == 3'b010)
     vram[addr[12:0]] <= ram_din;
   
   vram_dout_L <= vram[vram_addr[12:0]];   
end   
`endif
   
assign vram_dout = vram_dout_L;   
   
`endif
   
reg	zx48;
reg	p1024;
reg	pf1024;
reg	plus3;
reg        page_scr_copy;
reg        shadow_rom;
reg  [7:0] page_reg;
reg  [7:0] page_reg_plus3;
reg  [7:0] page_reg_p1024;
wire       page_disable = zx48 | (~p1024 & page_reg[5]) | (p1024 & page_reg_p1024[2] & page_reg[5]);
wire       page_scr     = page_reg[3];
wire [5:0] page_ram     = {page_128k, page_reg[2:0]};
wire       page_write   = ~addr[15] & ~addr[1] & (addr[14] | ~plus3) & ~page_disable; //7ffd
wire       page_write_plus3 = ~addr[1] & addr[12] & ~addr[13] & ~addr[14] & ~addr[15] & plus3 & ~page_disable; //1ffd
wire       page_special = page_reg_plus3[0];
wire       motor_plus3 = page_reg_plus3[3];
wire       page_p1024 = addr[15] & addr[14] & addr[13] & ~addr[12] & ~addr[3]; //eff7
reg  [2:0] page_128k;

reg  [3:0] page_rom;
wire       active_48_rom = zx48 | (page_reg[4] & ~plus3) | (plus3 & page_reg[4] & page_reg_plus3[2] & ~page_special);

always_comb begin
	casex({shadow_rom, trdos_en, plusd_mem, mf128_mem, plus3})
		'b1XXXX: page_rom <= 4'b0100; //shadow
		'b01XXX: page_rom <= 4'b0101; //trdos
		'b001XX: page_rom <= 4'b1100; //plusd
		'b0001X: page_rom <= { 2'b11, plus3, ~plus3 }; //MF128/+3
		'b00001: page_rom <= { 2'b10, page_reg_plus3[2], page_reg[4] }; //+3
		'b00000: page_rom <= { zx48, 2'b11, zx48 | page_reg[4] }; //up to +2
	endcase
end

always @(posedge clk_sys) begin
	reg old_reset;
	reg [2:0] rmod;

	old_reset <= reset;
	if(~old_reset & reset) rmod <= mod;

	if(reset) begin
		page_scr_copy <= 0;
		page_reg    <= 0;
		page_reg_plus3 <= 0; 
		page_reg_p1024 <= 0;
		page_128k   <= 0;
		page_reg[4] <= Fn[10];
		page_reg_plus3[2] <= Fn[10];
		shadow_rom <= shdw_reset & ~plusd_en;
		if(Fn[10] && (rmod == 1)) begin
			p1024  <= 0;
			pf1024 <= 0;
			zx48   <= ~plus3;
		end else begin
			p1024 <= (status[12:10] == 1);
			pf1024<= (status[12:10] == 2);
			zx48  <= (status[12:10] == 3);
			plus3 <= (status[12:10] == 4);
		end
	end else begin
		if(m1 && ~old_m1 && addr[15:14]) shadow_rom <= 0;
		if(m1 && ~old_m1 && ~plusd_en && ~mod[0] && (addr == 'h66) && ~plus3) shadow_rom <= 1; 

		if(io_wr & ~old_wr) begin
			if(page_write) begin
				page_reg  <= cpu_dout;
				if(p1024 & ~page_reg_p1024[2])	page_128k[2:0] <= { cpu_dout[5], cpu_dout[7:6] };
				if(~plusd_mem) page_scr_copy <= cpu_dout[3];
			end else if (page_write_plus3) begin
				page_reg_plus3 <= cpu_dout; 
			end
			if(pf1024 & (addr == 'hDFFD)) page_128k <= cpu_dout[2:0];
			if(p1024 & page_p1024) page_reg_p1024 <= cpu_dout;
		end
	end
end


////////////////////  ULA PORT  ///////////////////
reg [2:0] border_color;
reg       ear_out;
reg       mic_out;

always @(posedge clk_sys) begin

	if(reset) {ear_out, mic_out} <= 2'b00;
	else if(~ula_nWR) begin
		border_color <= cpu_dout[2:0];
		ear_out <= cpu_dout[4]; 
		mic_out <= cpu_dout[3];
	end
end


////////////////////   AUDIO   ///////////////////
wire [7:0] sound_data;
wire [7:0] psg_ch_a;
wire [7:0] psg_ch_b;
wire [7:0] psg_ch_c;
wire       psg_enable = addr[0] & addr[15] & ~addr[1];
wire       psg_we     = psg_enable & ~nIORQ & ~nWR & nM1;
reg        psg_reset;

`ifdef DISABLED
// Turbosound card (Dual AY/YM chips)
turbosound turbosound
(
	.CLK(clk_sys),
	.CE(ce_psg),
	.RESET(reset | psg_reset),
	.BDIR(psg_we),
	.BC(addr[14]),
	.DI(cpu_dout),
	.DO(sound_data),
	.CHANNEL_A(psg_ch_a),
	.CHANNEL_B(psg_ch_b),
	.CHANNEL_C(psg_ch_c),
	.SEL(0),
	.MODE(0),

	.IOA_in(0),
	.IOB_in(0)
);
`endif
   
`ifdef ENABLE_GS
wire  [7:0] gs_dout;
wire [14:0] gs_l, gs_r;
wire gs_sel = (addr[7:0] ==? 'b1011?011) & ~&status[21:20];

reg [3:0] gs_ce_count;

always @(posedge clk_sys) begin
	reg gs_no_wait;

	if(reset) begin
		gs_ce_count <= 0;
		gs_no_wait <= 1;
	end else begin
		if (gs_ce_p) gs_no_wait <= 0;
		if (gs_mem_ready) gs_no_wait <= 1;
		if (gs_ce_count == 4'd7) begin
			if (gs_mem_ready | gs_no_wait) gs_ce_count <= 0;
		end else
			gs_ce_count <= gs_ce_count + 1'd1;

	end
end

// 14 MHz (112MHz/8) clock enable for GS card
wire gs_ce_p = gs_ce_count == 0;
wire gs_ce_n = gs_ce_count == 4;

// General Sound
gs #(.INT_DIV(373)) gs
(
	.RESET(reset),
	.CLK(clk_sys),
	.CE_N(gs_ce_n),
	.CE_P(gs_ce_p),

	.A(addr[3]),
	.DI(cpu_dout),
	.DO(gs_dout),
	.CS_n(~nM1 | nIORQ | ~gs_sel),
	.WR_n(nWR),
	.RD_n(nRD),

	.MEM_ADDR(gs_mem_addr),
	.MEM_DI(gs_mem_din),
	.MEM_DO(gs_mem_dout | gs_mem_mask),
	.MEM_RD(gs_mem_rd),
	.MEM_WR(gs_mem_wr),
	.MEM_WAIT(~gs_mem_ready),

	.OUTL(gs_l),
	.OUTR(gs_r)
);

sigma_delta_dac #(14) dac_l
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({~gs_l[14], gs_l[13:0]} + {2'b00, psg_ch_a, 5'd0} + {3'b000, psg_ch_b, 4'd0} + {2'b00, ear_out, mic_out, tape_in, 10'd0}),
	.DACout(AUDIO_L)
);

sigma_delta_dac #(14) dac_r
(
	.CLK(clk_sys),
	.RESET(reset),
	.DACin({~gs_r[14], gs_r[13:0]} + {2'b00, psg_ch_c, 5'd0} + {3'b000, psg_ch_b, 4'd0} + {2'b00, ear_out, mic_out, tape_in, 10'd0}),
	.DACout(AUDIO_R)
);
`endif

////////////////////   VIDEO   ///////////////////
wire [14:0] vram_addr;
wire  [7:0] vram_dout;
wire  [7:0] port_ff;
wire        ulap_sel;
wire  [7:0] ulap_dout;

reg mZX, m128;
always_comb begin
	case(status[9:8])
		      0: {mZX, m128} <= 2'b10;
		      1: {mZX, m128} <= 2'b11;
		default: {mZX, m128} <= 2'b00;
	endcase
end

wire [1:0] scale = status[16:15];
wire [2:0] Rx, Gx, Bx;
wire       HSync, VSync, HBlank;
wire       ulap_ena, ulap_mono, mode512;
wire       ulap_avail = ~status[14] & ~trdos_en;
wire       tmx_avail = ~status[13] & ~trdos_en;
wire       snow_ena = &turbo & ~plus3;
wire       ula_nWR;

ULA ULA(.*, .nPortRD(), .nPortWR(ula_nWR), .din(cpu_dout), .page_ram(page_ram[2:0]));

`ifdef DISABLED
video_mixer #(.LINE_LENGTH(896), .HALF_DEPTH(1)) video_mixer
(
	.*,
	.ce_pix(ce_7mp | ce_7mn),
	.ce_pix_actual(ce_7mp | (mode512 & ce_7mn)),
	.hq2x(scale == 1),
	.scanlines(scandoubler_disable ? 2'b00 : {scale==3, scale==2}),

	.line_start(0),
	.ypbpr_full(1),

	.R(Rx),
	.G(Gx),
	.B(Bx),
	.mono(ulap_ena & ulap_mono)
);
`endif

wire [4:0] sd_out_r;
wire [4:0] sd_out_g;
wire [4:0] sd_out_b;
wire	   sd_out_hs /* verilator public */;
wire	   sd_out_vs /* verilator public */;   

// run video through scan doubler and HDMI encoder
scandoubler scandoubler (
     .clk_sys(clk_pixel),
			 
     // scanlines (00-none 01-25% 10-50% 11-75%)
     .scanlines(2'b00),

     // shifter video interface
     .hs_in(HSync),
     .vs_in(VSync),
     .r_in(Rx),
     .g_in(Gx),
     .b_in(Bx),

     // output interface
     .hs_out(sd_out_hs),
     .vs_out(sd_out_vs),
     .r_out(sd_out_r),
     .g_out(sd_out_g),
     .b_out(sd_out_b)
);		 

wire [4:0] osd_out_r /* verilator public */;
wire [4:0] osd_out_g /* verilator public */;
wire [4:0] osd_out_b /* verilator public */;

companion companion (
    .clk(clk_sys), 
    .reset(!locked),

    // Companion SPI interface
    .mcu_din(mcu_din),
    .mcu_dout(mcu_dout),
    .mcu_clk(mcu_clk),
    .mcu_ss(mcu_ss),
    .mcu_intn(mcu_intn),
    .mcu_spare(mcu_spare),

    .sd_clk(sd_clk),
    .sd_cmd(sd_cmd),
    .sd_dat(sd_dat),

    .tap(tape_in),
   
    .osd_reset(osd_reset),
		     
    .hs_n(!sd_out_hs),
    .vs_n(!sd_out_vs),
    .red(sd_out_r),
    .green(sd_out_g),
    .blue(sd_out_b),
    .out_red(osd_out_r),
    .out_green(osd_out_g),
    .out_blue(osd_out_b),

    .joystick(joystick),
		     
    .kbd_toggle(kbd_toggle),
    .kbd_data(kbd_data)
);
 
// analyze video signal to sync hdmi to it
wire vreset;   
video_analyzer video_analyzer (
     .clk(clk_pixel),
     .hs(sd_out_hs),
     .vs(sd_out_vs),

     .vreset(vreset)
);
 
`ifndef VERILATOR
parameter          PIXEL_CLOCK = 28_375_200;   

/* -------------------- HDMI video and audio -------------------- */

// generate 48khz audio clock
reg clk_audio;
reg [8:0] aclk_cnt;
always @(posedge clk_pixel) begin
    if(aclk_cnt < PIXEL_CLOCK / 48000 / 2 -1)
        aclk_cnt <= aclk_cnt + 9'd1;
    else begin
        aclk_cnt <= 9'd0;
        clk_audio <= ~clk_audio;
    end
end

wire [2:0] tmds;
wire tmds_clock;

wire [15:0] audio = { 5'd0, ear_out, mic_out, tape_in, 8'd0 };
   
   
hdmi #(
    .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
    .VENDOR_NAME( { "MiSTle", 16'd0} ),
    .PRODUCT_DESCRIPTION( {"Spectrum", 64'd0} )
) hdmi(
  .clk_pixel_x5(clk_pixel_x5),
  .clk_pixel(clk_pixel),
  .clk_audio(clk_audio),
  .audio_sample_word( { audio, audio } ),
  .tmds(tmds),
  .tmds_clock(tmds_clock),

  .reset(vreset),    // signal to synchronize HDMI to ULA

  .rgb( { osd_out_r, 3'b000, osd_out_g, 3'b000, osd_out_b, 3'b000 } )
);

// differential output
ELVDS_OBUF tmds_bufds [3:0] (
        .I({tmds_clock, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
);

`endif
  
////////////////////   HID   ////////////////////
wire [11:1] Fn;
wire  [2:0] mod;
wire  [4:0] key_data;
keyboard kbd( .* );
   
`ifdef ENABLE_MOUSE
reg         mouse_sel;
wire  [7:0] mouse_data;
mouse mouse( .*, .reset(cold_reset), .addr(addr[10:8]), .sel(), .dout(mouse_data));
   
always @(posedge clk_sys) begin
	reg old_status = 0;
	old_status <= ps2_mouse[24];

	if(joy0[5:0]) mouse_sel <= 0;
	if(old_status != ps2_mouse[24]) mouse_sel <= 1;
end
`endif

//////////////////   MF128   ///////////////////
reg         mf128_mem;
reg         mf128_en; // enable MF128 page-in from NMI till reset (or soft off)
wire        mf128_port = ~addr[6] & addr[5] & addr[4] & addr[1];
// read paging registers saved in MF3 (7f3f, 1f3f)
wire        mf3_port = mf128_port & ~addr[7] & (addr[12:8] == 'h1f) & plus3 & mf128_en;

always @(posedge clk_sys) begin

	if(reset) {mf128_mem, mf128_en} <= 0;
	else if(~old_rd & io_rd) begin
		//page in/out for port IN
		if(mf128_port) mf128_mem <= (addr[7] ^ plus3) & mf128_en;
	end else if(~old_wr & io_wr) begin
		//Soft hide
		if(mf128_port) mf128_en <= addr[7] & mf128_en;
	end

	if(~old_m1 & m1 & mod[0] & (addr == 'h66)) {mf128_mem, mf128_en} <= 2'b11;
end

//////////////////   MMC   //////////////////
wire        mmc_sel;
wire  [7:0] mmc_dout;

wire        spi_ss;
wire        spi_clk;
wire        spi_di;
wire        spi_do;

`ifdef DISABLED
divmmc divmmc
(
    .*,
    .enable(1),
    .mode(status[18:17]), //00-off, 01-divmmc, 10-zxmmc
    .din(cpu_dout),
    .dout(mmc_dout),
    .active_io(mmc_sel)
);

sd_card sd_card
(
    .*,
    .img_mounted(img_mounted[0]), //first slot for SD-card emulation
    .sd_busy(sd_busy_mmc),
    .sd_rd(sd_rd_mmc),
    .sd_wr(sd_wr_mmc),
    .sd_lba(sd_lba_mmc),
    .sd_buff_din(sd_buff_din_mmc),
    .allow_sdhc(1),
    .sd_cs(spi_ss),
    .sd_sck(spi_clk),
    .sd_sdi(spi_do),
    .sd_sdo(spi_di)
);
`endif
   
///////////////////   FDC   ///////////////////
reg         plusd_en;
reg         plusd_mem;
wire        plusd_ena = plusd_stealth ? plusd_mem : plusd_en;
wire        fdd_sel2 = plusd_ena & &addr[7:5] & ~addr[2] & &addr[1:0];

reg         trdos_en;
wire  [7:0] wd_dout;
wire        fdd_rd;
reg         fdd_ready;
reg         fdd_drive1;
reg         fdd_side;
reg         fdd_reset;
wire        fdd_intrq;
wire        fdd_drq;
wire        fdd_sel  = trdos_en & addr[2] & addr[1];
wire  [7:0] wdc_dout = (addr[7] & ~plusd_en) ? {fdd_intrq, fdd_drq, 6'h3F} : wd_dout;

reg         plus3_fdd_ready;
wire        plus3_fdd = ~addr[1] & addr[13] & ~addr[14] & ~addr[15] & plus3 & ~page_disable;
wire [7:0]  u765_dout;

wire  [7:0] fdd_dout = plus3_fdd ? u765_dout : wdc_dout;

//
// current +D implementation notes:
// 1) all +D ports (except page out port) are disabled if +D memory isn't paged in.
// 2) only possible way to page in is through hooks at h08, h3A, h66 addresses.
//
// This may break compatibility with some apps written specifically for +D using 
// direct port access (badly written apps), but won't introduce
// incompatibilities with +D unaware apps.
//
wire        plusd_stealth = 1;

// read video page.
// available for MF128 and PlusD(patched).
wire        portBF = mf128_port & addr[7] & (mf128_mem | plusd_mem);

always @(posedge clk_sys) begin
	reg old_mounted;

	if(cold_reset) {plus3_fdd_ready, fdd_ready, plusd_en} <= 0;
	if(reset)      {plusd_mem, trdos_en} <= 0;

	old_mounted <= img_mounted[1];
	if(~old_mounted & img_mounted[1]) begin
	   //Only TRDs on +3
		fdd_ready <= (1 /* !ioctl_index[7:6] */ & plus3) | ~plus3;
		plusd_en  <= 0 /* |ioctl_index[7:6] */ & ~plus3;
		//DSK only for +3
		plus3_fdd_ready <= plus3 & 0 /* (ioctl_index[7:6] == 2) */;
	end

	psg_reset <= 0;

	if(plusd_en) begin
		trdos_en <= 0;
		if(~old_wr & io_wr  & (addr[7:0] == 'hEF) & plusd_ena) {fdd_side, fdd_drive1} <= {cpu_dout[7], cpu_dout[1:0] != 2};
		if(~old_wr & io_wr  & (addr[7:0] == 'hE7)) plusd_mem <= 0;
		if(~old_rd & io_rd  & (addr[7:0] == 'hE7) & ~plusd_stealth) plusd_mem <= 1;
		if(~old_m1 & m1 & ((addr == 'h08) | (addr == 'h3A) | (~mod[0] & (addr == 'h66)))) {psg_reset,plusd_mem} <= {(addr == 'h66), 1'b1};
	end else begin
		plusd_mem <= 0;
		if(~old_wr & io_wr & fdd_sel & addr[7]) {fdd_side, fdd_reset, fdd_drive1} <= {~cpu_dout[4], ~cpu_dout[2], !cpu_dout[1:0]};
		if(m1 && ~old_m1) begin
			if(addr[15:14]) trdos_en <= 0;
				else if((addr[13:8] == 'h3D) & active_48_rom) trdos_en <= 1;
				//else if(~mod[0] & (addr == 'h66)) trdos_en <= 1;
		end
	end
end

`ifdef DISABLED
wd1793 #(1,0) fdd
(
	.clk_sys(clk_sys),
	.ce(ce_wd1793),
	.reset((fdd_reset & ~plusd_en) | reset),
	.io_en((fdd_sel2 | (fdd_sel & ~addr[7])) & ~nIORQ & nM1),
	.rd(~nRD),
	.wr(~nWR),
	.addr(plusd_en ? addr[4:3] : addr[6:5]),
	.din(cpu_dout),
	.dout(wd_dout),
	.drq(fdd_drq),
	.intrq(fdd_intrq),

	.img_mounted(img_mounted[1]),
	.img_size(img_size),
	.sd_lba(sd_lba_wd),
	.sd_rd(sd_rd_wd),
	.sd_wr(sd_wr_wd),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_wd),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(plusd_en ? 3'd4 : 3'd1),
	.layout(0 /* ioctl_index[7:6] == 1 */ ),
	.side(fdd_side),
	.ready(fdd_drive1 & fdd_ready),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);
`endif
   
`ifdef DISABLED
u765 #(20'd1800,1) u765
(
	.clk_sys(clk_sys),
	.ce(ce_u765),
	.reset(reset),
	.a0(addr[12]),
	.ready(plus3_fdd_ready),
	.motor(motor_plus3),
	.available(2'b01),
	.fast(1),
	.nRD(~plus3_fdd | nIORQ | ~nM1 | nRD),
	.nWR(~plus3_fdd | nIORQ | ~nM1 | nWR),
	.din(cpu_dout),
	.dout(u765_dout),

	.img_mounted(img_mounted[1]),
	.img_size(img_size),
	.img_wp(0),
	.sd_lba(sd_lba_plus3),
	.sd_rd(sd_rd_plus3),
	.sd_wr(sd_wr_plus3),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_plus3),
	.sd_buff_wr(sd_buff_wr)
);
`endif
   
endmodule
