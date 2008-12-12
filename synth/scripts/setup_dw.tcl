set synopsys_home  /home/shared/system/cad/tools/synopsys/syn/syn_vA-2007.12-SP1
set dw_lib         ${synopsys_home}/libraries/syn/

set link_library    "${link_library} dw_foundation.sldb dw01.sldb dw02.sldb dw03.sldb dw04.sldb dw05.sldb dw06.sldb"
set symbol_library  "${symbol_library} dw_foundation.sldb"

lappend ${search_path} ${dw_lib}