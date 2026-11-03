// Exercise both real SPI paths through the top and companion status command.
`timescale 1ns/1ps
module nano20k_spi_tb;
  reg clk = 0;
  always #17.637 clk = ~clk;
  reg external_clk = 0, external_cs = 1, external_data = 0;
  reg onboard_clk = 0, onboard_cs = 1, onboard_data = 0;
  reg [1:0] buttons = 0;
  wire external_reply, onboard_reply, external_irq, onboard_irq;
  zxspectrum dut (
    .CLOCK_27(clk), .s(buttons),
    .mcu_clk(external_clk), .mcu_ss(external_cs), .mcu_din(external_data),
    .mcu_dout(external_reply), .mcu_intn(external_irq), .mcu_spare(1'b1),
    .spi_sclk(onboard_clk), .spi_csn(onboard_cs), .spi_dat(onboard_data),
    .spi_dir(onboard_reply), .spi_irqn(onboard_irq)
  );

  task automatic transfer(input bit external_port, input byte tx, output byte rx);
    rx = 0;
    for (int bit_index = 7; bit_index >= 0; bit_index--) begin
      if (external_port) external_data = tx[bit_index];
      else onboard_data = tx[bit_index];
      #100;
      if (external_port) external_clk = 1;
      else onboard_clk = 1;
      #100;
      if (external_reply !== onboard_reply || external_irq !== onboard_irq)
        $fatal(1,"Replies and interrupts must be mirrored to both connections");
      rx[bit_index] = external_reply;
      if (external_port) external_clk = 0;
      else onboard_clk = 0;
    end
    #300; // allow the existing byte transfer into the system clock domain
  endtask

  task automatic check_status(input bit external_port);
    byte rx, marker0, marker1, core_id;
    if (external_port) external_cs = 0;
    else onboard_cs = 0;
    #300;
    transfer(external_port, 8'h00, rx); // system target
    transfer(external_port, 8'h00, rx); // status command
    transfer(external_port, 8'hff, rx); // first request primes the response
    transfer(external_port, 8'hff, marker0);
    transfer(external_port, 8'hff, marker1);
    transfer(external_port, 8'hff, core_id);
    if (marker0 !== 8'h5c || marker1 !== 8'h42 || core_id !== 8'h00)
      $fatal(1,"Bad status on external=%b: %h %h %h",external_port,marker0,marker1,core_id);
    if (external_port) external_cs = 1;
    else onboard_cs = 1;
    #300;
  endtask

  initial begin
    wait(dut.system_reset_n);
    repeat (4) @(negedge clk);
    if (dut.spi_ext !== 0) $fatal(1,"Must select on-board BL616 at startup");
    check_status(0);
    if (dut.spi_ext !== 0) $fatal(1,"On-board traffic changed selection");
    check_status(1);
    if (dut.spi_ext !== 1) $fatal(1,"External chip-select did not latch selection");
    // Once selected, on-board traffic must be ignored.
    onboard_cs = 0; onboard_clk = 1;
    #300;
    if (dut.spi_io_ss !== 1 || dut.spi_io_clk !== 0)
      $fatal(1,"On-board SPI still selected after external activity");
    onboard_cs = 1; onboard_clk = 0;
    // A normal core button reset must not switch the companion connection.
    buttons[1] = 1;
    repeat (4) @(negedge clk);
    buttons[1] = 0;
    repeat (4) @(negedge clk);
    if (!dut.spi_ext) $fatal(1,"Core button reset changed SPI selection");
    check_status(1);
    // System reset, unlike a core reset, returns selection to on-board.
    force dut.pll_locked = 0;
    #1;
    if (dut.spi_ext !== 0) $fatal(1,"System reset did not clear SPI selection");
    $display("PASS: on-board and external status, mirrored replies/IRQ, sticky selection, core/system resets");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1,"SPI test timeout");
  end
endmodule
