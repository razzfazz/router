source ${script_dir}/setup_proj_paths.tcl

set hdlin_auto_save_templates true

set suppress_errors {VER-311 VER-314 VER-318 HDL-193 LINT-29 LINT-33, OPT-1055, OPT-1206, OPT-1207}

#set cache_dir_chmod_octal "777"
#set cache_file_chmod_octal "666"
#set cache_read "/tmp/synopsys_cache"
#set cache_write "/tmp/synopsys_cache"

#define_design_lib dc_work -path ./dc_work

set link_library "*"

source ${script_dir}/setup_tsmc.tcl

source ${script_dir}/setup_dw.tcl
