//
// scandoubler.v
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 

module scandoubler
(
	// system interface
	input            clk_sys,

	// scanlines (00-none 01-25% 10-50% 11-75%)
	input      [1:0] scanlines,

	// shifter video interface
	input            hs_in,
	input            vs_in,
	input      [2:0] r_in,
	input      [2:0] g_in,
	input      [2:0] b_in,

	// output interface
	output reg       hs_out,
	output reg       vs_out,
	output reg [4:0] r_out,
	output reg [4:0] g_out,
	output reg [4:0] b_out
);

parameter HCNT_WIDTH = 10;

// pixel clock divider
reg ce_in, ce_out = 1;

// clk_sys is 113 MHz
// input pixel clock is 14MHz, output pixel clock is 28MHz
// TODO: run input at 7MHz with half the buffer size
 
always @(posedge clk_sys) begin
	reg last_hs_in;
	last_hs_in <= hs_in;
	if(last_hs_in & !hs_in) begin
		ce_in <= 1'b0;
	end else begin
		ce_in <= !ce_in;
	end
end


// --------------------- create output signals -----------------
// latch everything once more to make it glitch free and apply scanline effect
reg scanline;
reg [2:0] r;
reg [2:0] g;
reg [2:0] b;

reg [3*3-1:0] sd_buffer_out;

always @(*) begin
   b = sd_buffer_out[2:0];
   g = sd_buffer_out[5:3];
   r = sd_buffer_out[8:6];
end

always @(posedge clk_sys) begin
	if(ce_out) begin
		hs_out <= hs_sd;
		vs_out <= vs_sd;

		// reset scanlines at every new screen
		if(vs_out != vs_in) scanline <= 0;

		// toggle scanlines at begin of every hsync
		if(hs_out && !hs_sd) scanline <= !scanline;

		// if no scanlines or not a scanline
		if(!scanline || !scanlines) begin
			r_out <= {r, 2'b00 };
			g_out <= {g, 2'b00 };
			b_out <= {b, 2'b00 };
		end else begin
			case(scanlines)
				1: begin // reduce 25% = 1/2 + 1/4
					r_out <= {1'b0, r, 1'b0} + {2'b00, r };
					g_out <= {1'b0, g, 1'b0} + {2'b00, g };
					b_out <= {1'b0, b, 1'b0} + {2'b00, b };
				end

				2: begin // reduce 50% = 1/2
					r_out <= {1'b0, r, 1'b0};
					g_out <= {1'b0, g, 1'b0};
					b_out <= {1'b0, b, 1'b0};
				end

				3: begin // reduce 75% = 1/4
					r_out <= {2'b00, r};
					g_out <= {2'b00, g};
					b_out <= {2'b00, b};
				end
			endcase
		end
	end
end

// ==================================================================
// ======================== the line buffers ========================
// ==================================================================

// 2 lines of 2**HCNT_WIDTH pixels 3*3 bit RGB
(* ramstyle = "no_rw_check" *) reg [8:0] sd_buffer[2*2**HCNT_WIDTH];

// use alternating sd_buffers when storing/reading data   
reg        line_toggle;

// total hsync time (in 16MHz cycles), hs_total reaches 1024
reg  [HCNT_WIDTH-1:0] hs_max;
reg  [HCNT_WIDTH-1:0] hs_rise;
reg  [HCNT_WIDTH-1:0] hcnt;

always @(posedge clk_sys) begin
	reg hsD, vsD;

	if(ce_in) begin
		hsD <= hs_in;

		// falling edge of hsync indicates start of line
		if(hsD && !hs_in) begin
			hs_max <= hcnt;
			hcnt <= 0;
		end else begin
			hcnt <= hcnt + 1'd1;
		end

		// save position of rising edge
		if(!hsD && hs_in) hs_rise <= hcnt;

		vsD <= vs_in;
		if(vsD != vs_in) line_toggle <= 0;

		// begin of incoming hsync
		if(hsD && !hs_in) line_toggle <= !line_toggle;

		sd_buffer[{line_toggle, hcnt}] <= {r_in, g_in, b_in};
	end
end

// ==================================================================
// ==================== output timing generation ====================
// ==================================================================

reg [HCNT_WIDTH-1:0] sd_hcnt;
reg        hs_sd, vs_sd;

always @(posedge clk_sys) begin
	reg hsD;

	if(ce_out) begin
		hsD <= hs_in;

		// output counter synchronous to input and at twice the rate
		sd_hcnt <= sd_hcnt + 1'd1;
		if(hsD && !hs_in)     sd_hcnt <= hs_max;
		if(sd_hcnt == hs_max) sd_hcnt <= 0;

		// replicate horizontal sync at twice the speed
		if(sd_hcnt == hs_max)  hs_sd <= 0;
		if(sd_hcnt == hs_rise) hs_sd <= 1;

		// read data from line sd_buffer
		sd_buffer_out <= sd_buffer[{~line_toggle, sd_hcnt}];
		vs_sd <= vs_in;
	end
end

endmodule
