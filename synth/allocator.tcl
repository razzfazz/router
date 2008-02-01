set net_dir  net
set rpt_dir  rpt
set rtl_dir  ../src
set wrp_dir  wrappers

set hdlin_auto_save_templates true

# set cache_dir_chmod_octal "777"
# set cache_file_chmod_octal "666"
# set cache_read "/tmp/synopsys_cache"
# set cache_write "/tmp/synopsys_cache"

# define_design_lib dc_work -path ./dc_work

set tsmc_home /home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME

#set dw_lib     /home/shared/system/cad/tools/synopsys/syn/syn_vX-2005.09-SP2/libraries/syn/
set dw_lib     /home/dub/synopsys/syn/A-2007.12-SP1/libraries/syn/
set tsmc_lib   $tsmc_home/digital/Front_End/timing_power/tcb013ghp_211a
set phys_lib   $tsmc_home/digital/Front_End/physical_compiler/tcb013ghp_211a
set slow_db    $tsmc_lib/tcb013ghpwc.db
set fast_db    $tsmc_lib/tcb013ghpbc.db
set sym_db     $tsmc_lib/tcb013ghp.sdb
set phys_db    $phys_lib/tcb013ghp_Fsg_8lm_6x6.pdb

set_min_library $slow_db -min_version $fast_db
 
set target_library  "$slow_db"
set link_library    "* $slow_db dw_foundation.sldb dw01.sldb dw02.sldb dw03.sldb dw04.sldb dw05.sldb dw06.sldb"
set symbol_library  "$sym_db dw_foundation.sldb"

set use_pdb_lib_format true
set physical_library  "$phys_db"

set cell_lib tcb013ghpwc

set search_path [list $rtl_dir $wrp_dir $dw_lib ]

set top allocator_syn_wrapper

set src_files [list \
 wf_alloc.v \
 rr_arbiter.v \
 matrix_arbiter.v \
 allocator.v \
 arbiter.v \
 interleaver.v \
 dff.v \
 clkgate.v \
 select_1ofn.v \
 or_nto1.v \
 allocator_syn_wrapper.v ]

read_verilog -rtl $src_files
current_design    $top

#set_operating_conditions \
    -max WCCOM -max_library tcb013ghpwc \
    -min BCCOM -min_library tcb013ghpbc 

# set_dont_use [ list slow/DFFS* slow/DFFT*]

# Clocks
set clk_name   CLK
set clk_period 2.5

set all_input_ports  [ get_ports "*" -filter {@port_direction == in} ]
set all_output_ports [ get_ports "*" -filter {@port_direction == out} ]

create_clock -period $clk_period  [get_ports $clk_name]

set all_inputs_no_clocks [remove_from_collection $all_input_ports $clk_name ]
set_clock_latency 0      [get_clocks $clk_name]

set port_load [eval load_of $cell_lib/BUFFD4/I ]
set_load        $port_load $all_output_ports
set_fanout_load 1          $all_output_ports

set reset_name RST
set_ideal_network $reset_name

# report_port                $all_output_ports

# report_timing_requirements

#compile_ultra -no_autoungroup
compile_ultra

report_design
report_resources
check_design

write_file -format verilog -hierarchy -output $net_dir/$top.v $top
write_file -format ddc -output $net_dir/$top.ddc
write_sdf $net_dir/$top.sdf
write_parasitics -o $net_dir/$top.par
write_sdc $net_dir/$top.sdc

report_timing -nworst 5 > $rpt_dir/$top.timing
report_area -physical  > $rpt_dir/$top.area
report_cell > $rpt_dir/$top.cell
report_design -verbose  > $rpt_dir/$top.design
report_power -verbose -hier > $rpt_dir/$top.power
