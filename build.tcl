if {$argc == 0} {
    puts "Usage: $argv0 <device> [<controller>]"
    puts "          device: nano20k"
    exit 1
}

set dev [lindex $argv 0]

# process $dev
if {$dev eq "nano20k"} {
    set_device GW2AR-LV18QN88C8/I7 -device_version C
    add_file "src/nano20k/config.vh"
    add_file -type verilog "src/zxspectrum.sv"
    add_file -type cst "src/nano20k/zxspectrum.cst"
    add_file -type sdc "src/nano20k/zxspectrum.sdc"
    set_option -output_base_name zxspectrum_${dev}
} else {
    error "Unknown device $dev"
}

add_file -type vhdl "src/T80/T80pa.vhd"
add_file -type vhdl "src/T80/T80.vhd"
add_file -type vhdl "src/T80/T80_MCode.vhd"
add_file -type vhdl "src/T80/T80_Reg.vhd"
add_file -type vhdl "src/T80/T80_ALU.vhd"
add_file -type vhdl "src/T80/T80_Pack.vhd"

add_file -type verilog "src/sdram.sv"
add_file -type verilog "src/ula.sv"
add_file -type verilog "src/keyboard.sv"
add_file -type verilog "src/scandoubler.v"
add_file -type verilog "src/video_analyzer.v"

add_file -type verilog "src/mistle/companion.v"
add_file -type verilog "src/mistle/mcu_spi.v"
add_file -type verilog "src/mistle/hid.v"
add_file -type verilog "src/mistle/sysctrl.v"
add_file -type verilog "src/mistle/osd_u8g2.v"
add_file -type verilog "src/mistle/sd_card.v"
add_file -type verilog "src/mistle/sd_rw.v"
add_file -type verilog "src/mistle/sdcmd_ctrl.v"

add_file -type verilog "src/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi/audio_info_frame.sv"
add_file -type verilog "src/hdmi/audio_sample_packet.sv"
add_file -type verilog "src/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi/hdmi.sv"
add_file -type verilog "src/hdmi/packet_assembler.sv"
add_file -type verilog "src/hdmi/packet_picker.sv"
add_file -type verilog "src/hdmi/serializer.sv"
add_file -type verilog "src/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi/tmds_channel.sv"

set_option -synthesis_tool gowinsynthesis
set_option -top_module zxspectrum
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -place_option 2
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 0
set_option -use_done_as_gpio 0
set_option -use_i2c_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -multi_boot 1

run all
