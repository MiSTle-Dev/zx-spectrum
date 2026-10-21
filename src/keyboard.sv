// ZX Spectrum for Altera DE1
//
// Copyright (c) 2009-2011 Mike Stirling
// Copyright (c) 2015-2017 Sorgelig
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without 
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

// PS/2 scancode to Spectrum matrix conversion
module keyboard
(
	input		  reset,
	input		  clk_sys,

	input		  kbd_toggle,
        input [7:0]	  kbd_data,
 
	input [15:0]	  addr,
	output [4:0]	  key_data,

	output reg [11:1] Fn = 0,
	output reg [2:0]  mod = 0
);

reg  [4:0] keys[7:0];

wire       release_btn = kbd_data[7];
wire [6:0] code = kbd_data[6:0];   

// Output addressed row to ULA
assign key_data = (!addr[8]  ? keys[0] : 5'b11111)
                 &(!addr[9]  ? keys[1] : 5'b11111)
                 &(!addr[10] ? keys[2] : 5'b11111)
                 &(!addr[11] ? keys[3] : 5'b11111)
                 &(!addr[12] ? keys[4] : 5'b11111)
                 &(!addr[13] ? keys[5] : 5'b11111)
                 &(!addr[14] ? keys[6] : 5'b11111)
                 &(!addr[15] ? keys[7] : 5'b11111);

`ifdef DISABLED
wire shift = mod[0];
`endif
   
reg old_reset = 0;
reg old_toggle = 0;
   
always @(posedge clk_sys) begin
	old_reset <= reset;
	old_toggle <= kbd_toggle;

	if(~old_reset & reset)begin
		keys[0] <= 5'b11111;
		keys[1] <= 5'b11111;
		keys[2] <= 5'b11111;
		keys[3] <= 5'b11111;
		keys[4] <= 5'b11111;
		keys[5] <= 5'b11111;
		keys[6] <= 5'b11111;
		keys[7] <= 5'b11111;
	end

	if(kbd_toggle != old_toggle) begin
`ifdef DISABLED
		case(code)
			7'h59: mod[0]<= ~release_btn; // right shift
			7'h11: mod[1]<= ~release_btn; // alt
			7'h14: mod[2]<= ~release_btn; // ctrl
			7'h05: Fn[1] <= ~release_btn; // F1
			7'h06: Fn[2] <= ~release_btn; // F2
			7'h04: Fn[3] <= ~release_btn; // F3
			7'h0C: Fn[4] <= ~release_btn; // F4
			7'h03: Fn[5] <= ~release_btn; // F5
			7'h0B: Fn[6] <= ~release_btn; // F6
			7'h83: Fn[7] <= ~release_btn; // F7
			7'h0A: Fn[8] <= ~release_btn; // F8
			7'h01: Fn[9] <= ~release_btn; // F9
			7'h09: Fn[10]<= ~release_btn; // F10
			7'h78: Fn[11]<= ~release_btn; // F11
		endcase
`endif
	   
		case(code)
			7'h69 : keys[0][0] <= release_btn; // Left shift (CAPS SHIFT)
			7'h6d : keys[0][0] <= release_btn; // Right shift (CAPS SHIFT)
			7'h1d : keys[0][1] <= release_btn; // Z
			7'h1b : keys[0][2] <= release_btn; // X
			7'h06 : keys[0][3] <= release_btn; // C
			7'h19 : keys[0][4] <= release_btn; // V

			7'h04 : keys[1][0] <= release_btn; // A
			7'h16 : keys[1][1] <= release_btn; // S
			7'h07 : keys[1][2] <= release_btn; // D
			7'h09 : keys[1][3] <= release_btn; // F
			7'h0a : keys[1][4] <= release_btn; // G

			7'h14 : keys[2][0] <= release_btn; // Q
			7'h1a : keys[2][1] <= release_btn; // W
			7'h08 : keys[2][2] <= release_btn; // E
			7'h15 : keys[2][3] <= release_btn; // R
			7'h17 : keys[2][4] <= release_btn; // T

			7'h1e : keys[3][0] <= release_btn; // 1
			7'h1f : keys[3][1] <= release_btn; // 2
			7'h20 : keys[3][2] <= release_btn; // 3
			7'h21 : keys[3][3] <= release_btn; // 4
			7'h22 : keys[3][4] <= release_btn; // 5

			7'h27 : keys[4][0] <= release_btn; // 0
			7'h26 : keys[4][1] <= release_btn; // 9
			7'h25 : keys[4][2] <= release_btn; // 8
			7'h24 : keys[4][3] <= release_btn; // 7
			7'h23 : keys[4][4] <= release_btn; // 6

			7'h13 : keys[5][0] <= release_btn; // P
			7'h12 : keys[5][1] <= release_btn; // O
			7'h0c : keys[5][2] <= release_btn; // I
			7'h18 : keys[5][3] <= release_btn; // U
			7'h1c : keys[5][4] <= release_btn; // Y

			7'h28 : keys[6][0] <= release_btn; // ENTER
			7'h0f : keys[6][1] <= release_btn; // L
			7'h0e : keys[6][2] <= release_btn; // K
			7'h0d : keys[6][3] <= release_btn; // J
			7'h0b : keys[6][4] <= release_btn; // H

			7'h2c : keys[7][0] <= release_btn; // SPACE
			7'h68 : keys[7][1] <= release_btn; // CTRL (Symbol Shift)
			7'h11 : keys[7][2] <= release_btn; // M
			7'h11 : keys[7][3] <= release_btn; // N
			7'h05 : keys[7][4] <= release_btn; // B
`ifdef DISABLED
			// Cursor keys - these are actually extended (E0 xx), but
			// the scancodes for the numeric keypad cursor keys are
			// are the same but without the extension, so we'll accept
			// the codes whether they are extended or not
			7'h6B : begin // Left (CAPS 5)
					keys[0][0] <= release_btn;
					keys[3][4] <= release_btn;
				end
			7'h72 : begin // Down (CAPS 6)
					keys[0][0] <= release_btn;
					keys[4][4] <= release_btn;
				end
			7'h75 : begin // Up (CAPS 7)
					keys[0][0] <= release_btn;
					keys[4][3] <= release_btn;
				end
			7'h74 : begin // Right (CAPS 8)
					keys[0][0] <= release_btn;
					keys[4][2] <= release_btn;
				end

			// Other special keys sent to the ULA as key combinations
			7'h66 : begin // Backspace (CAPS 0)
					keys[0][0] <= release_btn;
					keys[4][0] <= release_btn;
				end
			7'h58 : begin // Caps lock (CAPS 2)
					keys[0][0] <= release_btn;
					keys[3][1] <= release_btn;
				end
			7'h76 : begin // Escape (CAPS SPACE)
					keys[0][0] <= release_btn;
					keys[7][0] <= release_btn;
				end
			7'h49 : begin // . <
					keys[7][1] <= release_btn;
					keys[2][4] <= release_btn | ~shift;
					keys[7][2] <= release_btn |  shift;
				end
			7'h41 : begin // , >
					keys[7][1] <= release_btn;
					keys[2][3] <= release_btn | ~shift;
					keys[7][3] <= release_btn |  shift;
				end
			7'h4A : begin // / ?
					keys[7][1] <= release_btn;
					keys[0][3] <= release_btn | ~shift;
					keys[0][4] <= release_btn |  shift;
				end
			7'h4C : begin // ; :
					keys[7][1] <= release_btn;
					keys[0][1] <= release_btn | ~shift;
					keys[5][1] <= release_btn |  shift;
				end
			7'h52 : begin // " '
					keys[7][1] <= release_btn;
					keys[4][3] <= release_btn | ~shift;
					keys[5][0] <= release_btn |  shift;
				end
			7'h54 : begin // (
					keys[7][1] <= release_btn;
					keys[4][2] <= release_btn;
				end
			7'h5B : begin // )
					keys[7][1] <= release_btn;
					keys[4][1] <= release_btn;
				end
			7'h4E : begin // - _
					keys[7][1] <= release_btn;
					keys[4][0] <= release_btn | ~shift;
					keys[6][3] <= release_btn |  shift;
				end
			7'h55 : begin // = +
					keys[7][1] <= release_btn;
					keys[6][2] <= release_btn | ~shift;
					keys[6][1] <= release_btn |  shift;
				end
			7'h0E : begin // '
					keys[7][1] <= release_btn;
					keys[4][3] <= release_btn;
				end
			7'h5D : begin // *
					keys[7][1] <= release_btn;
					keys[7][4] <= release_btn;
				end
`endif
			default: ;
		endcase
	end
end

reg [8:0] auto[46] = '{
	255,

	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,

	{1'b1, 8'h59}, // right shift
	{1'b1, 8'h11}, // alt
	{1'b1, 8'h14}, // ctrl
	{1'b0, 8'h3b}, // J
	{1'b1, 8'h3b}, // J
	{1'b0, 8'h52}, // "
	{1'b1, 8'h52}, // "
	0,
	{1'b0, 8'h52}, // "
	{1'b1, 8'h52}, // "
	{1'b0, 8'h5a}, // enter
	{1'b1, 8'h5a}, // enter
	255
};

`ifdef DISABLED
// ps2_key[10]  toggle: event
// ps2_key[9]   1:press, 0:release
// ps2_key[8:0] keycode

always @(posedge clk_sys) begin
	integer div;
	reg [5:0] auto_pos = 0;
	reg old_reset = 0;
	reg old_state;

	input_strobe <= 0;
	old_reset <= reset;
	old_state <= ps2_key[10];

	if(~old_reset & reset)begin
		auto_pos <= 0;
	end else begin
		if(auto[auto_pos] == 255) begin
			div <=0;
			if(old_state != ps2_key[10]) begin
				release_btn <= ~ps2_key[9];
				code <= ps2_key[7:0];
				input_strobe <= 1;
				if((ps2_key[8:0] == 9) && ~ps2_key[9]) auto_pos <= 1; // F10
			end
		end else begin
			div <= div + 1;
			if(div == 7000000) begin 
				div <=0;
				if(auto[auto_pos]) {input_strobe, release_btn, code} <= {1'b1, auto[auto_pos]};
				auto_pos <= auto_pos + 1'd1;
			end
		end
	end
end
`endif //  `ifdef DISABLED
   
endmodule
