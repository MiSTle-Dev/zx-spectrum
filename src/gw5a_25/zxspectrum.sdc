// 50 MHz board oscillator, not the stale 27 MHz constraint in NanoMig.
create_clock -name clk_osc -period 20 [get_ports {CLOCK_50}]
create_clock -name clk_companion -period 50 [get_ports {mcu_clk}]
create_generated_clock -name clk_hdmi -source [get_ports {CLOCK_50}] -multiply_by 17 -divide_by 6 [get_nets {clk_pixel_x5}]
create_generated_clock -name clk_sys -source [get_nets {clk_pixel_x5}] -divide_by 5 [get_pins {clkdiv_inst/CLKOUT}]
create_generated_clock -name clk_sdram -source [get_pins {clkdiv_inst/CLKOUT}] -divide_by 1 -invert [get_ports {SDRAM_CLK}]
// The fractional audio divider has a 48 kHz average frequency.
create_clock -name clk_audio -period 20833.333 [get_nets {clk_audio}]
// SPI is an external asynchronous interface; mcu_spi transfers completed bytes
// via a synchronized ready flag. HDMI uses a toggle handshake for audio samples.
set_clock_groups -asynchronous -group [get_clocks {clk_companion}] -group [get_clocks {clk_osc clk_hdmi clk_sys clk_sdram}] -group [get_clocks {clk_audio}]
// PLL_INIT lock enters the two asynchronous reset assertion paths.
// SDRAM-ready and both synchronized reset outputs retain normal timing checks.
set_false_path -from [get_clocks {clk_osc}] -to [get_regs {sdram_reset_sync* system_reset_sync*}]
