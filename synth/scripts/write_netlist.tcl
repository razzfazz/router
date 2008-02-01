# ----------------------------------------------------------------------
#
#  File: write_netlist.tcl
#
# ----------------------------------------------------------------------

create_clock -period [expr 1.0 * $clk_period] [get_ports $clk_name]
write_file -format verilog -hierarchy -output $net_dir/$top.v $top
write_sdc $net_dir/$top.sdc
