/*
    hid.v

    hid (keyboard, mouse etc) interface to the IO MCU
*/

module hid (
    input	     clk,
    input	     reset,

    input	     data_in_strobe,
    input	     data_in_start,
    input [7:0]	     data_in,
    output reg [7:0] data_out,

    output reg [7:0] joystick,

    output reg	     kbd_toggle,
    output reg [7:0] kbd_data
);

  reg [3:0] state;
  reg [7:0] command;
  reg [7:0] device;   // used for joystick

  // process mouse events
  always @(posedge clk, posedge reset) begin
    if (reset) begin
      state <= 4'd0;
      kbd_toggle = 1'b0;
      kbd_data = 8'h00;
    end else begin
      if (data_in_strobe) begin
        if (data_in_start) begin
          state   <= 4'd0;
          command <= data_in;
        end else begin
          if (state != 4'd15) state <= state + 4'd1;

          // CMD 0: status data
          if (command == 8'd0) begin
            // return some dummy data for now ...
            if (state == 4'd0) data_out <= 8'h01;  // hid version 1
            if (state == 4'd1) data_out <= 8'h00;  // subversion 0
          end

          // CMD 1: keyboard data
          if (command == 8'd1) begin
             if (state == 4'd0) begin
		kbd_data <= data_in;
		kbd_toggle <= !kbd_toggle;		
             end
	  end
	   
           // CMD 3: receive digital joystick data
           if(command == 8'd3) begin
              if(state == 4'd0) device <= data_in;
              if(state == 4'd1 && device == 8'd0) 
                joystick <= data_in;
           end
        end
      end
    end
  end
   
endmodule
