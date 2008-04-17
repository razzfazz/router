# ----------------------------------------------------------------------
#
#  First Encounter Setup Script
#
# ----------------------------------------------------------------------

# Enable cell function detection because footprints are not provided
set dbgGPSAutoCellFunction 1

# Paths
set tsmc_home /home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME
set lef_dir   $tsmc_home/digital/Back_End/lef/tcb013ghp_211a/lef
set tech_dir  $tsmc_home/digital/Back_End/lef/tcb013ghp_211a/techfiles

# Technology Files and Cell Definition
set rda_Input(ui_timelib,min) "/home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME/digital/Front_End/timing_power/tcb013ghp_211a/tcb013ghpbc.lib"
set rda_Input(ui_timelib,max) "/home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME/digital/Front_End/timing_power/tcb013ghp_211a/tcb013ghpwc.lib"
set rda_Input(ui_timelib)     "/home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME/digital/Front_End/timing_power/tcb013ghp_211a/tcb013ghptc.lib"
set rda_Input(ui_leffile)     "$lef_dir/tsmc013gFsg_8lm.lef $lef_dir/tcb013ghp.lef"
set rda_Input(ui_captbl_file) "$tech_dir/t013s8mg_fsg_v2.0b.cap"

# Default power and group connections
set rda_Input(ui_pg_connections) [list {PIN:VDD:} {PIN:VSS:} ]
set rda_Input(PIN:VDD:) {vdd}
set rda_Input(PIN:VSS:) {gnd}

set rda_Input(ui_pwrnet) {vdd}
set rda_Input(ui_gndnet) {gnd}

# Replace Verilog assign statements with buffers
set rda_Input(assign_buffer) {1}

# Defaults from First Encounter
set rda_Input(flip_first) {1}
set rda_Input(double_back) {1}
set rda_Input(ui_delay_limit) {1000}
set rda_Input(ui_net_delay) {1000.0ps}
set rda_Input(ui_net_load) {0.5pf}
set rda_Input(ui_in_tran_delay) {0.1ps}
set rda_Input(ui_defcap_scale) {1.0}
set rda_Input(ui_detcap_scale) {1.0}
set rda_Input(ui_xcap_scale) {1.0}
set rda_Input(ui_res_scale) {1.0}
set rda_Input(ui_shr_scale) {1.0}
set rda_Input(ui_time_unit) {none}
set rda_Input(ui_core_cntl) {aspect}
set rda_Input(ui_aspect_ratio) {1.0}
set rda_Input(ui_core_util) {0.60}
set rda_Input(ui_core_height) {180}
set rda_Input(ui_core_width) {120}
set rda_Input(ui_row_height) {3.69}
set rda_Input(ui_isHorTrackHalfPitch) {0}
set rda_Input(ui_isVerTrackHalfPitch) {1}
