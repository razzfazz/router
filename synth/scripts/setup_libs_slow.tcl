# ----------------------------------------------------------------------
#
#  File: setup_libs_slow.tcl
#
# ----------------------------------------------------------------------

set cache_dir_chmod_octal "777"
set cache_file_chmod_octal "666"
set cache_read {"/tmp/synopsys_cache"}
set cache_write "/tmp/synopsys_cache"

define_design_lib dc_work -path ./dc_work
set tsmc_home /home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME

set dw_lib     /home/dub/synopsys/A-2007.12-SP1/libraries/syn/
set tsmc_lib   $tsmc_home/digital/Front_End/timing_power/tcb013ghp_211a
set slow_db    tcb013ghpwc.db
set fast_db    tcb013ghpbc.db

set_min_library $tsmc_lib/$slow_db -min_version $tsmc_lib/$fast_db
 
set target_library  {    tcb013ghpwc.db  }
   set link_library    { *  tcb013ghpwc.db   dw_foundation.sldb dw01.sldb dw02.sldb dw03.sldb dw04.sldb dw05.sldb dw06.sldb }
set link_library    { *  tcb013ghpwc.db }
set symbol_library  { dw_foundation.sldb }

# ----
#  Use $cell_lib to refer to the current cell library
# --
set cell_lib tcb013ghpwc

set search_path [list ./ $tsmc_lib  $dw_lib ]
