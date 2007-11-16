source prolog.tcl

set top router_syn_wrapper

set src_files [list\
 $rtl_dir/rr_arbiter.v\
 $rtl_dir/matrix_arbiter.v\
 $rtl_dir/router.v\
 $rtl_dir/dff.v\
 wrappers/router_syn_wrapper.v   ]

source epilog.tcl
