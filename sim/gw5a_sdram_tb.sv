`timescale 1ns/1ps
`define SYS_CLK_28MHZ
module gw5a_sdram_tb;
`ifdef NANO
  localparam integer COL_BITS = 8;
`else
  localparam integer COL_BITS = 9;
`endif
  localparam integer BANK_LSB = COL_BITS + `SDRAM_ROW_WIDTH + 1;
  reg clk = 0;
  always #17.647 clk = ~clk;
  reg init_n = 0;
  reg req = 0, we = 0;
  reg [23:1] addr = 0;
  wire ack, ready, cke;
  wire [`SDRAM_ROW_WIDTH-1:0] a;
  wire [1:0] ba;
  wire cs, ras, cas, wen;
  wire [15:0] dq, q;
  // Single-word SDRAM read: CL3, then release DQ after one memory cycle.
  reg [2:0] read_pipe = 0;
  reg ram_drive = 0;
  assign dq = ram_drive ? 16'h5aa5 : 16'hzzzz;
  always @(negedge clk) begin
    read_pipe <= {read_pipe[1:0], ({cs,ras,cas,wen} == 4'b0101)};
    ram_drive <= read_pipe[2];
  end
  sdram #(
    .ROW_WIDTH(`SDRAM_ROW_WIDTH), .COLUMN_BITS(COL_BITS),
    .RASCAS_DELAY(3'd2), .REFRESH_CYCLES(200), .STARTUP_CYCLES(5667)
  ) dut (
    .clk(clk), .init_n(init_n), .ready(ready), .clkref(1'b0),
    .SDRAM_CKE(cke), .SDRAM_DQ(dq), .SDRAM_A(a), .SDRAM_BA(ba),
    .SDRAM_nCS(cs), .SDRAM_nRAS(ras), .SDRAM_nCAS(cas), .SDRAM_nWE(wen),
    .port1_req(req), .port1_ack(ack), .port1_we(we),
    .port1_a(addr), .port1_ds(2'b11), .port1_d(16'hcafe), .port1_q(q),
    .port2_req(1'b0), .port2_we(1'b0), .port2_a(23'd0),
    .port2_ds(2'b0), .port2_d(16'b0)
  );
  integer init_step = 0, last_init_command = 0, mode_cycle = 0;
  integer cycles = 0, last_refresh = 0, refreshes = 0;
  reg checking_refresh = 0, checking_access = 0;
  always @(negedge clk) begin
    cycles = cycles + 1;
    if (!cs && {ras,cas,wen} != 3'b111 && cycles < 5667)
      $fatal(1, "SDRAM command before 200 us power-up wait");
    if (dut.init && !cs && {ras,cas,wen} != 3'b111) begin
      case (init_step)
        0: if ({ras,cas,wen} != 3'b010 || !a[10])
             $fatal(1, "Initialization must start with PRECHARGE ALL");
        1,2: if ({ras,cas,wen} != 3'b001)
             $fatal(1, "Initialization requires two AUTO REFRESH commands");
        3: begin
          if ({ras,cas,wen} != 3'b000 || ba != 0 || a != 'h230)
            $fatal(1, "Incorrect mode register (single word, CL3, single writes)");
          mode_cycle = cycles;
        end
        default: $fatal(1, "Unexpected extra initialization command");
      endcase
      if (init_step > 0 && cycles-last_init_command < 2)
        $fatal(1, "Insufficient precharge/refresh command spacing");
      init_step = init_step + 1;
      last_init_command = cycles;
    end
    if (ready && (init_step != 4 || cycles-mode_cycle < 2))
      $fatal(1, "RAM ready before mode register recovery completed");
    if (checking_refresh && {cs,ras,cas,wen} == 4'b0001) begin
      if (last_refresh && cycles - last_refresh > 216)
        $fatal(1, "Refresh interval exceeds 7.8 us");
      last_refresh = cycles;
      refreshes = refreshes + 1;
    end
    if (checking_access && {cs,ras,cas,wen} == 4'b0011) begin
      if (a !== addr[COL_BITS+1 +: `SDRAM_ROW_WIDTH] || ba !== addr[BANK_LSB +: 2])
        $fatal(1, "Incorrect row or bank mapping");
    end
    if (checking_access && {cs,ras,cas} == 3'b010) begin
      if (a !== ((1 << 10) | (addr[COL_BITS:1])))
        $fatal(1, "Incorrect column or auto-precharge mapping");
      if (!wen && dq !== 16'hcafe) $fatal(1, "Write bus not driven");
    end
  end
  initial begin
    // Model the Gowin configuration-time register reset.
    dut.t = 0;
    dut.refresh_cnt = 0;
    dut.state = 0;
    #1;
    repeat (2) @(negedge clk);
    if (cke !== 1'b0) $fatal(1, "CKE must be low during SDRAM reset");
    init_n = 1;
    #1;
    if (cke !== 1'b0) $fatal(1, "CKE must wait for a rising clock edge");
    @(posedge clk); #1;
    if (cke !== 1'b1) $fatal(1, "CKE did not enable after reset release");
    wait (ready);
    @(negedge clk);
    checking_refresh = 1;
    repeat (1000) @(negedge clk);
    if (refreshes < 4) $fatal(1, "Missing periodic refresh");
    checking_refresh = 0;
    checking_access = 1;
    we = 1;
    addr = 23'h4567ab;
    req = 1;
    wait (ack === req);
    @(negedge clk);
    checking_access = 0;
    repeat (16) @(negedge clk);
    we = 0;
    addr = 23'h123456;
    checking_access = 1;
    req = 0;
    wait (ack === req);
    #1;
    if (q !== 16'h5aa5) $fatal(1, "Read bus data not captured");
    @(negedge clk); init_n = 0;
    #1;
    if (cke !== 1'b0) $fatal(1, "CKE did not clear asynchronously on SDRAM reset");
    $display("PASS: initialization sequence and ready, refresh, address mapping, timed read/write bus");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "Timeout");
  end
endmodule
