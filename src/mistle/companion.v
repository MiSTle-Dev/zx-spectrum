//

module companion (
    input	 clk,
    input	 reset,

    // FPGA Companion
    input	 mcu_din,
    output	 mcu_dout,
    input	 mcu_clk,
    input	 mcu_ss,
    output	 mcu_intn,
    input	 mcu_spare,

    // SD card
    output	 sd_clk,
    inout	 sd_cmd,
    inout [3:0]	 sd_dat,

    // tape data
    output	 tap,
		  
    // OSD overlay
    input	 hs_n,
    input	 vs_n, 
    input [5:0]	 red,
    input [5:0]	 green,
    input [5:0]	 blue, 
    output [5:0] out_red,
    output [5:0] out_green,
    output [5:0] out_blue,

    // OSD controlled variables
    output	 osd_reset,
    output	 osd_joystick_type,

    output [7:0] joystick,
		  
    // keyboard interface
    output	 kbd_toggle,
    output [7:0] kbd_data
);

wire       mcu_data_strobe;   
wire	   mcu_data_start;   
wire [7:0] mcu_data_in;   
wire [7:0] mcu_data_out;   

wire       mcu_sys_strobe;        // mcu message byte valid for sysctrl
wire       mcu_hid_strobe;        // -"- hid
wire       mcu_osd_strobe;        // -"- osd
wire       mcu_sdc_strobe;        // -"- sdc

wire [7:0] sys_data_out;  
wire [7:0] hid_data_out;  
wire [7:0] osd_data_out = 8'h55;  // OSD actually has no data output
wire [7:0] sdc_data_out;  

mcu_spi mcu (
  .clk(clk),
  .reset(reset),

  // SPI interface to FPGA Companion
  .spi_io_ss (mcu_ss),
  .spi_io_clk(mcu_clk),
  .spi_io_din(mcu_din),
  .spi_io_dout(mcu_dout),

  // byte wide data in/out to the submodules
  .mcu_sys_strobe(mcu_sys_strobe),
  .mcu_hid_strobe(mcu_hid_strobe),
  .mcu_osd_strobe(mcu_osd_strobe),
  .mcu_sdc_strobe(mcu_sdc_strobe),
  .mcu_start(mcu_data_start),
  .mcu_dout(mcu_data_out),
  .mcu_sys_din(sys_data_out),
  .mcu_hid_din(hid_data_out),
  .mcu_osd_din(osd_data_out),
  .mcu_sdc_din(sdc_data_out)
);

hid hid (
  .clk(clk),
  .reset(reset),

  .data_in_strobe(mcu_hid_strobe),
  .data_in_start(mcu_data_start),
  .data_in(mcu_data_out),
  .data_out(hid_data_out),

  .joystick(joystick),

  .kbd_toggle(kbd_toggle),
  .kbd_data(kbd_data)
);

wire sdc_int;   
wire [7:0] int_ack;   
wire sdc_iack = int_ack[3];

sysctrl sysctrl (
  .clk(clk),
  .reset(reset),

  // interface to send and receive generic system control
  .data_in_strobe(mcu_sys_strobe),
  .data_in_start(mcu_data_start),
  .data_in(mcu_data_out),
  .data_out(sys_data_out),
  
  // values controlled by the OSD
  .system_reset(osd_reset),
  .system_joystick_type(osd_joystick_type),
  
  .int_out_n(mcu_intn),
  .int_in({ 4'b0000, sdc_int, 3'b000 }),
  .int_ack( int_ack ),
  
  .buttons( 2'b00 ),
  .color()
);

osd_u8g2 osd_u8g2 (
  .clk(clk),
  .reset(reset),
  
  .data_in_strobe(mcu_osd_strobe),
  .data_in_start(mcu_data_start),
  .data_in(mcu_data_out),
  
  .hs(hs_n),
  .vs(vs_n),
  
  .r_in(red),
  .g_in(green),
  .b_in(blue),
  
  .r_out(out_red),
  .g_out(out_green),
  .b_out(out_blue)
);   

wire image_mounted;   
wire [23:0] image_size;   

reg	    sd_rd = 1'b0;
wire	    sd_busy;
reg [31:0]  sd_sector = 32'd0;   
wire	    sd_done;    

wire	    sd_data_en;
wire [8:0]  sd_data_addr;
wire [7:0]  sd_data_byte;
   
   
sd_card #(
    .CLK_DIV(3'd0)                  // for 28 Mhz clock
`ifdef VERILATOR
    , .SIMULATE(1)
`endif
) sd_card (
    .clk(clk),                      // clock
    .rstn(!reset),                  // rstn active-low, 1:working, 0:reset
  
    // SD card signals
    .sdclk(sd_clk),
    .sdcmd(sd_cmd),
    .sddat(sd_dat),

    // mcu interface
    .data_strobe(mcu_sdc_strobe),
    .data_start(mcu_data_start),
    .data_out(sdc_data_out),
    .data_in(mcu_data_out),

    .irq(sdc_int),
    .iack(sdc_iack),       
           
    .image_mounted(image_mounted),
    .image_size(image_size),           // length of image file

    // user read sector command interface (sync with clk32)
    .rstart(sd_rd), 
    .wstart(1'b0), 
    .rsector(sd_sector),
    .rbusy(sd_busy),
    .rdone(sd_done),

    // sector data output interface (sync with clk32)
    .inbyte(8'h00),
    .outen(sd_data_en),       // when outen=1, a byte of sector content is read out from outbyte
    .outaddr(sd_data_addr),   // outaddr from 0 to 511, because the sector size is 512
    .outbyte(sd_data_byte)    // a byte of sector content
);

// ------------------------------- TAP player -------------------------------

reg [7:0] tap_fifo_out_data;   
reg       tap_fifo_out_strobe;   
   
reg [7:0] tap_fifo [1024];
reg [9:0] tap_fifo_rd_ptr;
reg [9:0] tap_fifo_wr_ptr;

wire [9:0] tap_fifo_used = tap_fifo_wr_ptr - tap_fifo_rd_ptr;
wire [9:0] tap_fifo_free = 10'd1023 - tap_fifo_used;
wire       tap_fifo_data_available = tap_fifo_wr_ptr != tap_fifo_rd_ptr;

// https://github.com/alfishe/speccy-bootcamp/blob/main/03_io/storage/tape_interface.md
  
reg pulse_start_block;

reg [7:0] tap_chunk_flag;   // 0x00 or 0xff, TODO: use single bit only
reg [15:0] tap_chunk_len;   

// we need to read and parse the first three bytes of each chunk ahead
// of the transmission. So we buffer them to be able to send them afterwards
// TODO: get rid of this
reg [7:0] tap_chunk_pre_buffer [3];   
   
// ------------------- tape pulse generator --------------------
// generate a single pulse
   
localparam PULSE_TYPE_NONE  = 3'd0;   
localparam PULSE_TYPE_PILOT = 3'd1;   
localparam PULSE_TYPE_SYNC1 = 3'd2;   
localparam PULSE_TYPE_SYNC2 = 3'd3;   
localparam PULSE_TYPE_ZERO  = 3'd4;   
localparam PULSE_TYPE_ONE   = 3'd5;   
localparam PULSE_TYPE_FINAL = 3'd6;   
reg [2:0] pulse_type;

// pulse on t-states (1/3.5mhz)length of the different pulse types      
wire [15:0] pulse_reload =
	    (pulse_type == PULSE_TYPE_NONE)?0:
	    (pulse_type == PULSE_TYPE_PILOT)?2168:   // pilot tone pulse length
	    (pulse_type == PULSE_TYPE_SYNC1)?667:    // first sync pulse length
	    (pulse_type == PULSE_TYPE_SYNC2)?735:    // second sync pulse length
	    (pulse_type == PULSE_TYPE_ZERO)?855:     // data 0 bit
	    (pulse_type == PULSE_TYPE_ONE)?1710:     // data 1 bit
	    (pulse_type == PULSE_TYPE_FINAL)?955:    // single final pulse
	    0;   

reg	   tap_signal;
assign tap = tap_signal;

reg	    pulse_done;
   
always @(posedge clk) begin
   reg [19:0] pulse_t_state_cnt;
   pulse_done <= 1'b0;   

   if(pulse_type == PULSE_TYPE_NONE) begin
      tap_signal = 0;
      pulse_t_state_cnt <= 0;   
   end else if(pulse_t_state_cnt == { pulse_reload, 3'd0 }) begin
      // clk is 28MHz, a t-state is 3.5MHz, so total t-state counts need to
      // be 8 times

      pulse_t_state_cnt <= 0;   
      tap_signal <= !tap_signal;
      pulse_done <= 1'b1;    // pulse ends
   end else
     pulse_t_state_cnt <= pulse_t_state_cnt + 1;
end

// ------------------- tape pulse sequence generator --------------------   

// `define SIM_TEST
   
`ifdef SIM_TEST
// short values to keep simulation time down. These vaklues will not really
// be decodable by the speccy
localparam PULSE_COUNT_PILOT_HEADER = 6;
localparam PULSE_COUNT_PILOT_DATA   = 4;
`else
localparam PULSE_COUNT_PILOT_HEADER = 8063;
localparam PULSE_COUNT_PILOT_DATA   = 3223;
`endif
localparam PULSE_COUNT_SYNC         = 1;
localparam PULSE_COUNT_DATA_BIT     = 2;
localparam PULSE_COUNT_FINAL        = 1;

reg [15:0] pulse_data_pre_cnt;  // pre data byte counter (two length bytes and flag)
reg [15:0] pulse_data_cnt;      // data byte counter
reg [7:0] pulse_data_byte;
reg [2:0] pulse_data_bit;

reg	  tap_request_next_data_byte;

always @(posedge clk) begin
   reg [15:0] pulse_counter;
   reg start_requested;   

   // ejecting the image (size == 0) resets the entire tap player
   if(reset || (image_mounted && image_size == 24'd0)) begin
      pulse_counter <= 0;
      pulse_type <= PULSE_TYPE_NONE;
      tap_request_next_data_byte <= 1'b0;      
   end else begin
      tap_request_next_data_byte <= 1'b0;

      // trigger signal starts a new pulse sequence for a complete block
      if(pulse_start_block) begin

	 // this should never happen while we aren't idle
	 if(pulse_type != PULSE_TYPE_NONE)
	   $display("companion.v: TAP ERROR ================= not idle ================");	 
	 
	 // start with pilot pulses
	 if(tap_chunk_flag == 8'h00) begin
	    $display("companion.v: TAP sending header pilot %0d", PULSE_COUNT_PILOT_HEADER);	    
	    pulse_counter <= PULSE_COUNT_PILOT_HEADER-1;
	 end else begin
	    $display("companion.v: TAP sending data pilot %0d", PULSE_COUNT_PILOT_DATA);
            pulse_counter <= PULSE_COUNT_PILOT_DATA-1;
	 end
	 pulse_type <= PULSE_TYPE_PILOT;
      end
      
      // decrement pulse counter at end of each pulse
      if(pulse_done) begin
	 if(pulse_counter != 0)
	   pulse_counter <= pulse_counter - 1;
	 else begin
	    // a pulse sequence inside the block has ended
	    case(pulse_type)
	      PULSE_TYPE_PILOT: begin
		 $display("companion.v: TAP sending sync #1");
		 pulse_type <= PULSE_TYPE_SYNC1;
		 pulse_counter <= PULSE_COUNT_SYNC-1;
	      end
	      
	      PULSE_TYPE_SYNC1: begin
		 $display("companion.v: TAP sending sync #2");
		 pulse_type <= PULSE_TYPE_SYNC2;
		 pulse_counter <= PULSE_COUNT_SYNC-1;

		 // prepare for transmission of first data byte
		 // three bytes have already been taken from the fifo and
		 // need to be sent first		 
		 pulse_data_pre_cnt <= 16'd1;
		 pulse_data_cnt <= { tap_chunk_pre_buffer[1], tap_chunk_pre_buffer[0] }-1; 
		 pulse_data_byte <= tap_chunk_pre_buffer[2];  // first length byte
		 pulse_data_bit <= 3'd7;

		 tap_request_next_data_byte <= 1'b1;   // request next data byte from fifo
		 $display("companion.v: TAP sending byte pre $%0x", tap_chunk_pre_buffer[2]);
	      end

	      PULSE_TYPE_SYNC2, PULSE_TYPE_ZERO, PULSE_TYPE_ONE: begin
		 // last data bit within byte sent? 
		 if(pulse_data_bit != 7 || pulse_type == PULSE_TYPE_SYNC2 || 
		    pulse_data_pre_cnt != 16'd0 || pulse_data_cnt != 16'd0 ) begin
		    // send MSB first
		    if(pulse_data_byte[7]) pulse_type <= PULSE_TYPE_ONE;
		    else                   pulse_type <= PULSE_TYPE_ZERO;
		    pulse_counter <= PULSE_COUNT_DATA_BIT - 1;

		    pulse_data_byte <= { pulse_data_byte[6:0], 1'b0 };
		    pulse_data_bit <= pulse_data_bit - 1;		 
		 end else begin
		    pulse_type <= PULSE_TYPE_FINAL;
		    pulse_counter <= PULSE_COUNT_FINAL - 1;
		 end

		 // last bit of byte or sync2 has been sent, count to next byte
		 if(pulse_data_bit == 7) begin
		    // first decrement pre counter, then data counter
		    if(pulse_data_pre_cnt)
		      pulse_data_pre_cnt <= pulse_data_pre_cnt - 16'd1;
		    else if(pulse_data_cnt)
		      pulse_data_cnt <= pulse_data_cnt - 16'd1;
		 end
		 
		 // sent last bit into transmission, prepare for next byte
		 if(pulse_data_bit == 0 && 
		    (pulse_data_pre_cnt != 16'd0 || pulse_data_cnt != 16'd0)) begin

		    // todo: pre_cnt can be a single bit
		    $display("companion.v: TAP sending byte %0d $%0x",
			     pulse_data_cnt, tap_fifo_out_data);
		    pulse_data_byte <= tap_fifo_out_data;
		    
		    // do not request another byte after the last one
		    if(pulse_data_cnt > 1)		 
		      tap_request_next_data_byte <= 1'b1;   // request next data byte from fifo
		 end
	      end
	      
	      PULSE_TYPE_FINAL: begin
		 $display("companion.v: TAP ============== chunk done =================");
		 pulse_type <= PULSE_TYPE_NONE;
	      end
		 
	      default:
		pulse_type <= PULSE_TYPE_NONE;
	    endcase
	 end // else: !if(pulse_counter != 0)	 
      end // if (pulse_done)      
   end // else: !if(reset)
end

// ------------------- FIFO read engine --------------------   
reg [7:0] tap_fifo_rd_state;   
reg [7:0] tap_chunk_xor;   

always @(posedge clk) begin
   // ejecting the image (size == 0) resets the entire tap player
   if(reset || (image_mounted && image_size == 24'd0)) begin
      tap_fifo_rd_ptr <= 9'd0;
      tap_fifo_rd_state <= 8'd0;   
      pulse_start_block <= 1'b0;
   end else begin
      pulse_start_block <= 1'b0;
      
      // reset state on mount, to leave potential error state
      if(image_mounted && image_size != 24'd0) 
	tap_fifo_rd_state <= 0;
      
      // waiting for pulse engine to become idle?
      if(tap_fifo_rd_state == 4 && pulse_type <= PULSE_TYPE_NONE)
	 tap_fifo_rd_state <= 0;
	      
      // parse TAP byte
      if(tap_fifo_out_strobe) begin
	 case(tap_fifo_rd_state)
	   // The length field includes flag and crc bytes
	   // which we technically can ignore both as it's
	   // up to the speccy to deal with that. We thus do the
	   // checksum here to be visible in simulation.

	   0: begin // first byte of length field
	      tap_chunk_pre_buffer[0] <= tap_fifo_out_data;
	      tap_chunk_len[7:0] <= tap_fifo_out_data;
	      tap_chunk_xor <= 8'hff;
	      tap_fifo_rd_state <= 1;	      	      
	   end

	   1: begin // second byte of length field
	      tap_chunk_pre_buffer[1] <= tap_fifo_out_data;
	      tap_chunk_len[15:8] <= tap_fifo_out_data;
	      tap_chunk_xor <= 8'h00;	      
	      tap_fifo_rd_state <= 2;	      	      
	   end
	   
	   2: begin // flag (header 0x00, data 0xff)
	      tap_chunk_pre_buffer[2] <= tap_fifo_out_data;
	      tap_chunk_flag <= tap_fifo_out_data;
	      tap_chunk_xor <= tap_chunk_xor ^ tap_fifo_out_data;	      
	      tap_chunk_len <= tap_chunk_len - 16'd1;
	      tap_fifo_rd_state <= 3;
	      // start a new block of pulses
	      pulse_start_block <= 1'b1;	      

	      $display("companion.v: TAP ====== begin chunk len %0d, flag $%0x =======", 
		       tap_chunk_len, tap_fifo_out_data);	      
	   end

	   3: begin // read payload
	      tap_chunk_xor <= tap_chunk_xor ^ tap_fifo_out_data;	      
	      tap_chunk_len <= tap_chunk_len - 16'd1;

	      if(tap_chunk_len == 16'd1)
		 tap_fifo_rd_state <= 4;
	   end
	 endcase
      end

      // in tap_fifo_rd_state 0,1 and 2 the chunk header data is
      // just parsed, but not actually being sent. In state 3 the
      // data is sent and we need to wait for the transmission of
      // each byte to end

      tap_fifo_out_strobe <= 1'b0;
      if(!tap_fifo_out_strobe) begin
	 if(tap_fifo_data_available) begin
	    // the first three bytes of the chunk header are being read immediately
	    if(tap_fifo_rd_state < 3 || 
	       (tap_fifo_rd_state == 3 && tap_request_next_data_byte)) begin
	       //$display("companion.v: TAP read in state %0d from fifo: $%0x", 
	    	//	tap_fifo_rd_state, tap_fifo[tap_fifo_rd_ptr]);	    
	       
	       tap_fifo_out_data <= tap_fifo[tap_fifo_rd_ptr];	    
	       tap_fifo_rd_ptr <= tap_fifo_rd_ptr + 10'd1;	    
	       tap_fifo_out_strobe <= 1'b1;
	    end
	 end
      end
   end
end
   
// ------------------- FIFO write engine --------------------   
reg [7:0] tap_fifo_wr_state;
reg [31:0] tap_fifo_wr_delay;   
reg [23:0] tap_len;   

always @(posedge clk) begin
   // ejecting the image (size == 0) resets the entire tap player
   if(reset || (image_mounted && image_size == 24'd0)) begin
      tap_fifo_wr_state <= 8'd0;
      tap_fifo_wr_ptr <= 9'd0;
   end else begin
      case(tap_fifo_wr_state) 
	0: begin // wait for tap selection/insertion
	   if(image_mounted && image_size != 24'd0) begin
	      // user selected a tap file
	      tap_len <= image_size;
	      tap_fifo_wr_state <= 1;
	      tap_fifo_wr_delay <= 800;    // wait a little ...
	   end
	end
	
	1: begin // delay
	   if(tap_fifo_wr_delay)
	     tap_fifo_wr_delay <= tap_fifo_wr_delay - 1;
	   else begin
	      // prepare sector read
	      tap_fifo_wr_state <= 2;
	      sd_sector <= 32'd0;	
	   end
	end
	
	2: begin // wait for enough fifo space available and sd card ready
	   if(tap_fifo_free >= 10'd512 && !sd_busy) begin
	      $display("companion.v: TAP remaining %0d, read sector %0d", tap_len, sd_sector);
	      
	      // request sector
	      sd_rd <= 1'b1;
	      tap_fifo_wr_state <= 3;
	   end
	end
	      
	3: begin // wait for sd card ack
	   if(sd_busy) begin
	      sd_rd <= 1'b0;
	      tap_fifo_wr_state <= 4;	
	   end
	end
	
	4: begin // transfer data into fifo
	   if(sd_data_en) begin
	      if(sd_data_addr < tap_len) begin
		 tap_fifo[tap_fifo_wr_ptr] <= sd_data_byte;
		 tap_fifo_wr_ptr <= tap_fifo_wr_ptr + 10'd1;
	      end

	      if(sd_data_addr == 9'd511) begin
		 tap_fifo_wr_state <= 5;	      

		 // reduce tap byte counter
		 if(tap_len >= 24'd512) tap_len <= tap_len - 24'd512;	
		 else		        tap_len <= 24'd0;	
	      end
	   end
	end

	5: begin // sector transferred
	   if(tap_len) begin
	      tap_fifo_wr_state <= 2;
	      sd_sector <= sd_sector + 32'd1;
	   end else begin
	      $display("companion.v: TAP SD reading done");
	      tap_fifo_wr_state <= 0;
	   end
	end
	
      endcase // case (tap_fifo_wr_state)
   end // else: !if(reset)
end

   
endmodule
