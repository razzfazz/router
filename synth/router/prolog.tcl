set script_dir ../scripts

source ${script_dir}/setup_pre.tcl

set proj router

set top ${proj}

set src_files [list \
		   add_nto1.v \
		   arbiter.v \
		   checker.v \
		   clkgate.v \
		   credit_tracker.v \
		   crossbar.v \
		   decoder.v \
		   dff.v \
		   encoder.v \
		   extractor.v \
		   fifo_ctrl.v \
		   interleaver.v \
		   ip_ctrl.v \
		   ivc_ctrl.v \
		   matrix_arbiter.v \
		   mod_ctr.v \
		   mux_nto1.v \
		   op_ctrl.v \
		   or_nto1.v \
		   port_decoder_dim_order.v \
		   regfile.v \
		   replicator.v \
		   rotator.v \
		   router.v \
		   routing_logic.v \
		   rr_arbiter.v \
		   select_1ofn.v \
		   shift_register.v \
		   spreader.v \
		   sw_alloc_core_sep_if.v \
		   sw_alloc_core_sep_of.v \
		   sw_alloc_core_wf.v \
		   sw_alloc.v \
		   tree_arbiter.v \
		   vc_alloc_core_sep_if.v \
		   vc_alloc_core_sep_of.v \
		   vc_alloc.v \
		   wf_alloc_core_dpa.v \
		   wf_alloc_core_mux.v \
		   wf_alloc_core_rep.v \
		   wf_alloc_core_rot.v \
		   wf_alloc.v ]

read_verilog -rtl ${src_files}
current_design    ${top}

# Clocks
set clk_name   clk
set clk_period 3.5

set reset_name reset
set_ideal_network ${reset_name}

source ${script_dir}/setup_post.tcl

# report_port                ${all_output_ports}

# report_timing_requirements

set_ungroup decoder
set_ungroup dff
set_ungroup encoder
set_ungroup interleaver
set_ungroup mux_nto1
set_ungroup or_nto1
set_ungroup replicator
set_ungroup rotator
set_ungroup select_1ofn
set_ungroup spreader
