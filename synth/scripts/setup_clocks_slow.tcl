# ----------------------------------------------------------------------
#
#  File: setup_clocks_slow.tcl
#
# ----------------------------------------------------------------------

set clk_name   CLK
set clk_period 5 

set all_input_ports  [ get_ports "*" -filter {@port_direction == in} ]
set all_output_ports [ get_ports "*" -filter {@port_direction == out} ]

# ----
#  Reduce clock period during synthesis to improve place and route
# --
create_clock -period [expr 0.9 * $clk_period] [get_ports $clk_name]

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

# ----
#  Mark paths originating at reset as false timing paths
# --
set_false_path -from [get_ports "reset"] 

# ----
#  Dump timing requirements inferred by tool
# --
report_timing_requirements
