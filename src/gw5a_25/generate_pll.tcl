# Generate matching PLL, startup wrapper and IPC with Gowin V1.9.12.04.
# Usage: gw_sh src/gw5a_25/generate_pll.tcl /tmp/zxspectrum-gw5a-pll
# Generation stays in the supplied output directory for review before copying.
if {$argc != 1} {
    error "Usage: gw_sh generate_pll.tcl <output-directory>"
}
set output_dir [file normalize [lindex $argv 0]]
create_project -name zx_pll -dir [file join $output_dir project] \
    -pn GW5A-LV25LQ144C1/I0 -device_version A -force
create_ipc -name clock_plladv -module_name pll_142m -file_name pll_142m \
    -dir [file join $output_dir ip] -force
# Set the mutually exclusive mode options together. Preserve 50*34/2/6 MHz;
# only CLKOUT0 is needed, since system/pixel clocks use the existing CLKDIV.
set_property -dict {
    CONFIG.General_Mode false
    CONFIG.Adcanced_Mode true
    CONFIG.CLKIN_FREQ 50.000
    CONFIG.CLKIN_DIV_VALUE 2
    CONFIG.CLKFB_INTERNAL true
    CONFIG.CLKFB_EXTERNAL false
    CONFIG.CLKFB_DIV_STATIC true
    CONFIG.CLKFB_DIV_VALUE 1
    CONFIG.CLKFBOUT_DIV_INT_VALUE 34
    CONFIG.CLKFBOUT_DIV_FRAC_VALUE 0
    CONFIG.CLKFBOUT_EN false
    CONFIG.CLKOUT0_DIV_INT_VALUE 6
    CONFIG.CLKOUT0_DIV_FRAC_VALUE 0
    CONFIG.CLKOUT0_PHASE_STATIC true
    CONFIG.CLKOUT0_PHASE_DYN false
    CONFIG.CLKOUT0_PHASE_STATIC_VALUE 0
    CONFIG.CLKOUT1_EN false
    CONFIG.CLKOUT2_EN false
    CONFIG.CLKOUT3_EN false
    CONFIG.CLKOUT4_EN false
    CONFIG.CLKOUT5_EN false
    CONFIG.CLKOUT6_EN false
    CONFIG.LOCK_EN true
    CONFIG.MDRP_CLK_FREQ 50
    CONFIG.MDRP_EN false
    CONFIG.PLL_Reset false
    CONFIG.PLL_Power_Down false
    CONFIG.CLKIN_DIV_RESET false
    CONFIG.CLKOUT_DIV_RESET false
    CONFIG.SSC_EN false
} [get_ips pll_142m]
generate_target [get_ips pll_142m]
set ip_dir [file join $output_dir ip pll_142m]
# Gowin places the shared startup sequencer in the temporary project's src.
file copy -force [file join $output_dir project zx_pll src pll_init.v] \
    [file join $ip_dir pll_init.v]
puts "Generated PLL, startup wrapper and IPC in $ip_dir"
