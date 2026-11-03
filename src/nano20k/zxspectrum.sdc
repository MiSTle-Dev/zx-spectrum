// Nano20K: 27 MHz * 21 / 4 = 141.750 MHz; CLKDIV /5 = 28.350 MHz.
create_clock -name clk_osc -period 37.037037 [get_ports {CLOCK_27}]
// Either companion supplies the selected SPI clock, at up to 20 MHz.
create_clock -name clk_companion -period 50 [get_nets {spi_io_clk}]
create_generated_clock -name clk_hdmi -source [get_ports {CLOCK_27}] -multiply_by 21 -divide_by 4 [get_nets {clk_pixel_x5}]
create_generated_clock -name clk_sys -source [get_nets {clk_pixel_x5}] -divide_by 5 [get_pins {clkdiv_inst/CLKOUT}]
create_generated_clock -name clk_sdram -source [get_pins {clkdiv_inst/CLKOUT}] -divide_by 1 -invert [get_ports {O_sdram_clk}]
create_clock -name clk_audio -period 20833.333 [get_nets {clk_audio}]
// External SPI and fractional audio use the existing ready/toggle handshakes.
set_clock_groups -asynchronous -group [get_clocks {clk_companion}] -group [get_clocks {clk_osc clk_hdmi clk_sys clk_sdram}] -group [get_clocks {clk_audio}]
// Connection detection and the latched mux selection are not cycle-timed paths.
set_false_path -to [get_regs {spi_ext*}]
set_false_path -from [get_regs {spi_ext*}]
