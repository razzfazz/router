set script_dir ../scripts

source ${script_dir}/setup_pre.tcl

set proj complex_alloc_vc

set top ${proj}_syn_wrapper

set src_files [list \
		   arbiter.v \
		   clkgate.v \
		   complex_alloc_vc.v \
		   decoder.v \
		   dff.v \
		   encoder.v \
		   extractor.v \
		   interleaver.v \
		   matrix_arbiter.v \
		   mux_nto1.v \
		   or_nto1.v \
		   replicator.v \
		   rotator.v \
		   rr_arbiter.v \
		   select_1ofn.v \
		   spreader.v \
		   tree_arbiter.v \
		   vc_alloc_core_sep_if.v \
		   vc_alloc_core_sep_of.v \
		   vc_alloc.v \
		   ${proj}_syn_wrapper.v ]

read_verilog -rtl ${src_files}
current_design    ${top}

# Clocks
set clk_name   CLK
set clk_period 3

set reset_name RST
set_ideal_network ${reset_name}

source ${script_dir}/setup_post.tcl

# report_port                ${all_output_ports}

# report_timing_requirements

set_ungroup dff
set_ungroup interleaver
set_ungroup or_nto1
set_ungroup rotator
set_ungroup select_1ofn
