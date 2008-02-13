set tsmc_home  /home/shared/system/cad/libraries/tsmc/inhouse/tcb013ghp/TSMCHOME
set tsmc_lib   $tsmc_home/digital/Front_End/timing_power/tcb013ghp_211a
set phys_lib   $tsmc_home/digital/Front_End/physical_compiler/tcb013ghp_211a
set slow_db    $tsmc_lib/tcb013ghpwc.db
set fast_db    $tsmc_lib/tcb013ghpbc.db
set sym_db     $tsmc_lib/tcb013ghp.sdb
set phys_db    $phys_lib/tcb013ghp_Fsg_8lm_6x6.pdb

set_min_library $slow_db -min_version $fast_db
 
set target_library  "$slow_db"
set link_library    "* $slow_db"
set symbol_library  "$symbol_library $sym_db"

set use_pdb_lib_format true
set physical_library  "$phys_db"

set cell_lib tcb013ghpwc

