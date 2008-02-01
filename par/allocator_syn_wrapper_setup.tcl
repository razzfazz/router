# ----------------------------------------------------------------------
#                                             
#  Module Configuration File: allocator_syn_wrapper
#                                             
# ----------------------------------------------------------------------

global rda_Input
set cwd .

set rda_Input(import_mode) {-treatUndefinedCellAsBbox 0 -keepEmptyModule 1 -useLefDef56 1 }
set rda_Input(ui_netlist) "../synth/net/allocator_syn_wrapper.v"
set rda_Input(ui_netlisttype) {Verilog}
set rda_Input(ui_timingcon_file) "../synth/net/allocator_syn_wrapper.sdc"

set rda_Input(ui_topcell) {allocator_syn_wrapper}
set rda_Input(ui_settop) {1}
