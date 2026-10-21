//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.9 Beta-4
//Created Time: 2023-09-22 09:53:28
create_clock -name clk_hdmi -period 7.1 -waveform {0 3.55} [get_nets {clk_pixel_x5}] -add
// create_clock -name clk_sys -period 8.8 -waveform {0 4.4} [get_nets {clk_sys}] -add
