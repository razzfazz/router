set script_dir ../scripts

source ${script_dir}/setup_pre.tcl

set proj complex_alloc_sw

set top ${proj}_syn_wrapper

set src_files [list \
		   arbiter.v \
		   clkgate.v \
		   complex_alloc_sw.v \
		   complex_alloc_vc.v \
		   dff.v \
		   interleaver.v \
		   matrix_arbiter.v \
		   or_nto1.v \
		   rr_arbiter.v \
		   select_1ofn.v \
		   simple_alloc.v \
		   sw_alloc.v \
		   sw_alloc_core_sep_if.v \
		   sw_alloc_core_sep_of.v \
		   sw_alloc_core_wf.v \
		   vc_alloc.v \
		   vc_alloc_core_sep_if.v \
		   wf_alloc.v \
		   ${proj}_syn_wrapper.v ]

read_verilog -rtl ${src_files}
current_design    ${top}

# Clocks
set clk_name   CLK
set clk_period 2

set reset_name RST
set_ideal_network ${reset_name}

source ${script_dir}/setup_post.tcl

# report_port                ${all_output_ports}

# report_timing_requirements

#compile_ultra -no_autoungroup
compile_ultra

report_design
report_resources
check_design

source ${script_dir}/write_outputs.tcl
source ${script_dir}/write_reports.tcl

exit
