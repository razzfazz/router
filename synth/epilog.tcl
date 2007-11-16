
read_verilog -rtl $src_files
current_design    $top

# --------------------------------------------------
#
#  Standard Cell Library Management
#
# --------------------------------------------------
# set_dont_use [ list slow/DFFS* slow/DFFT*]

# --------------------------------------------------
#
#  Constraints
#
# --------------------------------------------------

set_wire_load_model -name "ZeroWireload" 

set_wire_load_mode           segmented
set auto_wire_load_selection true 

# Clocks
set clk_name   CLK
set clk_period 5.5

set all_input_ports  [ get_ports "*" -filter {@port_direction == in} ]
set all_output_ports [ get_ports "*" -filter {@port_direction == out} ]

create_clock -period [expr 0.9 * $clk_period]  [get_ports $clk_name]

set all_inputs_no_clocks [remove_from_collection $all_input_ports $clk_name ]
set_clock_latency 0      [get_clocks $clk_name]

set flop_input_delay  [expr $clk_period * 0.1]
set flop_output_delay [expr $clk_period * 0.1]

set comb_input_delay  [expr $clk_period * 0.1 ]
set comb_output_delay [expr $clk_period * 0.1 ]

set port_load [eval load_of $cell_lib/BUFFD4/I ]
set_load        $port_load $all_output_ports
set_fanout_load 1          $all_output_ports
report_port                $all_output_ports

report_timing_requirements

# --------------------------------------------------
#
#  Compile
#
# --------------------------------------------------
current_design $top
compile -map_effort high -area_effort high
report_design
report_resources
check_design

# --------------------------------------------------
#
#  Netlist and Constraints
#
# --------------------------------------------------
write_file -format verilog -hierarchy -output $net_dir/$top.v $top
write_file -format ddc -output $net_dir/$top.ddc
write_sdc $net_dir/$top.sdc

# --------------------------------------------------
#
#  Reports
#
# --------------------------------------------------
report_timing -nworst 5 > $rpt_dir/$top.timing
report_area -physical  > $rpt_dir/$top.area
report_cell > $rpt_dir/$top.cell
report_design -verbose  > $rpt_dir/$top.design
report_power -verbose -hier > $rpt_dir/$top.power

exit
