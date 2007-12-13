source prolog.tcl

set top router_syn_wrapper

set src_files [list\
 $rtl_dir/wf_alloc.v\
 $rtl_dir/rr_arbiter.v\
 $rtl_dir/matrix_arbiter.v\
 $rtl_dir/router.v\
 $rtl_dir/dff.v\
 $rtl_dir/clkgate.v\
 $rtl_dir/select_1ofn.v\
 $rtl_dir/or_nto1.v\
 wrappers/router_syn_wrapper.v   ]

source epilog.tcl
