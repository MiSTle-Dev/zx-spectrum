// ROM boot regression with CL3, single-word SDRAM read bursts.
// Only the physical pages used by the 48K core are allocated in this model.
`timescale 1ns/1ps
module boot_tb;
  reg clk = 0;
  reg reset_button = 0;
  always #17.647 clk = ~clk;
  wire [11:0] a;
  wire [1:0] ba;
  tri [15:0] dq;
  wire cs, ras, cas, wen, dqml, dqmh;
  zxspectrum dut(.CLOCK_50(clk), .reset_btn(reset_button), .user_n(1'b1),
    .SDRAM_A(a), .SDRAM_BA(ba), .SDRAM_DQ(dq), .SDRAM_nCS(cs),
    .SDRAM_nRAS(ras), .SDRAM_nCAS(cas), .SDRAM_nWE(wen),
    .SDRAM_DQML(dqml), .SDRAM_DQMH(dqmh),
    .mcu_din(1'b0), .mcu_clk(1'b0), .mcu_ss(1'b1), .mcu_spare(1'b1));
  reg [15:0] mem[0:65535];
  reg [11:0] rows[0:3];
  reg [2:0] rd_valid = 0;
  reg [15:0] rd_data[0:2];
  reg [1:0] dqm_pipe[0:1];
  reg [15:0] ram_data;
  reg ram_drive = 0;
  reg [1:0] ram_mask;
  assign dq[7:0] = ram_drive && !ram_mask[0] ? ram_data[7:0] : 8'hzz;
  assign dq[15:8] = ram_drive && !ram_mask[1] ? ram_data[15:8] : 8'hzz;
  integer index;
  always @(negedge clk) begin
    rd_valid <= {rd_valid[1:0], 1'b0};
    rd_data[1] <= rd_data[0];
    rd_data[2] <= rd_data[1];
    ram_drive <= rd_valid[2];
    ram_data <= rd_data[2];
    ram_mask <= dqm_pipe[1];
    dqm_pipe[1] <= dqm_pipe[0];
    dqm_pipe[0] <= {dqmh,dqml};
    if ({cs,ras,cas,wen} == 4'b0011) rows[ba] <= a;
    if (!cs && ras && !cas) begin
      index = (int'(ba) << 21) | (int'(rows[ba]) << 9) | int'(a[8:0]);
      if (index >= 65536) $fatal(1,"Unexpected RAM address %h", index);
      if (!wen) begin
        if (!dqml) mem[index][7:0] <= dq[7:0];
        if (!dqmh) mem[index][15:8] <= dq[15:8];
      end else begin
        rd_valid[0] <= 1;
        rd_data[0] <= mem[index];
      end
    end
  end
  bit checking_initial_boot = 1;
  always @(posedge clk)
    if (checking_initial_boot && dut.sdram_reset_n && !dut.sdram_ready && dut.system_reset_n)
      $fatal(1, "CPU released before SDRAM initialization completed");
  integer read_checks = 0;
  integer expected_word;
  reg [7:0] expected_byte;
  always @(posedge clk) begin
    if (!dut.reset && dut.ce_cpu_n && dut.cpu.cen_pol && dut.cpu.tstate == 3
        && !dut.nMREQ && !dut.nRD && dut.addr >= 16'h4000) begin
      expected_word = int'(dut.ram_addr >> 1);
      expected_byte = dut.ram_addr[0] ? mem[expected_word][15:8] : mem[expected_word][7:0];
      read_checks = read_checks + 1;
      if (dut.cpu_din != expected_byte)
        $fatal(1,"CPU read mismatch addr=%h PC=%h actual=%h expected=%h ready=%b t=%d", dut.addr,dut.cpu_reg[79:64],dut.cpu_din,expected_byte,dut.ram_ready,dut.ram.t);
    end
  end
  reg raw_video = 0, doubled_video = 0, output_video = 0;
  always @(posedge clk) begin
    if (|{dut.Rx,dut.Gx,dut.Bx}) raw_video <= 1;
    if (|{dut.sd_out_r,dut.sd_out_g,dut.sd_out_b}) doubled_video <= 1;
    if (|{dut.osd_out_r,dut.osd_out_g,dut.osd_out_b}) output_video <= 1;
  end
  integer attributes = 0;
  reg old_write = 0;
  reg white_border = 0;
  always @(posedge clk) begin
    old_write <= dut.io_wr;
    if (dut.io_wr && !old_write && !dut.addr[0] && dut.cpu_dout[2:0]==7)
      white_border <= 1;
    if (!dut.nMREQ && !dut.nWR && dut.addr >= 16'h5800 && dut.addr < 16'h5b00)
      attributes <= attributes + 1;
  end
  bit boot_ok = 0;
  initial begin : boot_sequence
    wait(dut.pll_locked);
    // Emulate an immediately-ready companion; SDRAM ready must hold CPU reset.
    force dut.companion.sysctrl.main_reset = 0;
    for (int elapsed_ms = 0; elapsed_ms < 5000 && !boot_ok; elapsed_ms++) begin
      #1000000;
      boot_ok = white_border && attributes > 768 && mem[16'hac00] == 16'h3838
                && raw_video && doubled_video && output_video;
    end
    if (!boot_ok) begin
      $display("BOOT state PC=%h reset=%b cpu_en=%b attributes=%d white=%b RAM=%h",
        dut.cpu_reg[79:64],dut.reset,dut.cpu_en,attributes,white_border,mem[16'hac00]);
      $fatal(1,"Boot timeout");
    end
    $display("PASS: ROM initialized white screen and produced video through OSD, PC=%h",dut.cpu_reg[79:64]);
    checking_initial_boot = 0;
    // Functional resets must leave SDRAM initialized and refreshing.
    @(negedge clk); reset_button = 1;
    repeat (16) @(negedge clk);
    if (!dut.reset || !dut.sdram_reset_n || !dut.sdram_ready)
      $fatal(1,"Button reset disturbed SDRAM initialization");
    reset_button = 0;
    repeat (16) @(negedge clk);
    force dut.companion.sysctrl.main_reset = 1;
    repeat (16) @(negedge clk);
    if (!dut.reset || !dut.sdram_reset_n || !dut.sdram_ready)
      $fatal(1,"OSD reset disturbed SDRAM initialization");
    force dut.companion.sysctrl.main_reset = 0;
    repeat (16) @(negedge clk);
    if (dut.reset) $fatal(1,"CPU did not leave functional reset");
    // Ready alone must only affect system reset on clock edges.
    #1; force dut.sdram_ready = 0;
    #1;
    if (!dut.system_reset_n || !dut.sdram_reset_n)
      $fatal(1,"SDRAM ready affected an asynchronous reset path");
    repeat (2) @(negedge clk);
    if (dut.system_reset_n || !dut.sdram_reset_n)
      $fatal(1,"Ready loss did not synchronously reset only the system");
    force dut.sdram_ready = 1;
    repeat (2) @(negedge clk);
    if (!dut.system_reset_n || !dut.sdram_reset_n)
      $fatal(1,"Ready recovery did not release the synchronized system reset");
    release dut.sdram_ready;
    // PLL loss must assert both reset outputs between clock edges.
    #1; force dut.pll_locked = 0;
    #1;
    if (dut.sdram_reset_n || dut.system_reset_n)
      $fatal(1,"PLL loss did not assert resets asynchronously");
    force dut.pll_locked = 1;
    @(posedge clk); #1;
    if (dut.sdram_reset_n || dut.system_reset_n)
      $fatal(1,"Reset released before synchronization");
    @(posedge clk); #1;
    if (!dut.sdram_reset_n || dut.system_reset_n)
      $fatal(1,"Incorrect SDRAM reset release or missing RAM-ready interlock");
    wait (dut.sdram_ready);
    @(posedge clk); #1;
    if (dut.system_reset_n) $fatal(1,"System reset released before ready synchronization");
    @(posedge clk); #1;
    if (!dut.system_reset_n) $fatal(1,"System reset did not follow synchronized ready");
    $display("PASS: button/OSD preserve SDRAM; PLL loss asserts both resets asynchronously; ready releases system synchronously");
    $finish;
  end
endmodule
