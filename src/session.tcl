# DVE session, saved on Thu Oct 25 11:43:50 2007
gui_set_env SIMSETUP::SIMARGS {{}}
gui_set_env SIMSETUP::SIMEXE {./simv}

# Close design
if { [gui_sim_state -check active] } {
    gui_sim_terminate
    gui_sim_wait terminated
}
gui_close_db -all
gui_expr_clear_all

# Close all windows
gui_close_window -type Console
gui_close_window -type Wave
gui_close_window -type Source
gui_close_window -type Source_
gui_close_window -type Schematic
gui_close_window -type Data
gui_close_window -type List
gui_close_window -type Memory
gui_close_window -type Hier
gui_close_window -type Assertion
gui_close_window -type CovHier
gui_close_window -type CovHier
gui_close_window -type CoverageTable
gui_close_window -type CoverageMap
gui_close_window -type CovDetail

# Create and position top-level windows
if {![gui_exist_window -window TopLevel.1]} {
    set TopLevel.1 [ gui_create_window -type TopLevel \
       -icon $::env(DVE)/auxx/gui/images/toolbars/dvewin.xpm] 
} else { 
    set TopLevel.1 TopLevel.1
}
gui_show_window -window ${TopLevel.1} -show_state normal -rect {{1280 44} {3124 1199}}

gui_set_env TOPLEVELS::TARGET_FRAME(Source) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(Schematic) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(PathSchematic) ${TopLevel.1}
gui_set_env TOPLEVELS::TARGET_FRAME(Wave) none
gui_set_env TOPLEVELS::TARGET_FRAME(List) none
gui_set_env TOPLEVELS::TARGET_FRAME(Memory) ${TopLevel.1}

set Console.1 [ gui_create_window -type {Console} -parent ${TopLevel.1} -show_state normal -rect {{0 0} {1824 173}} -dock_state bottom -dock_on_new_line true ]

# Application preferences
gui_set_pref_value -key app_default_font -value {Helvetica,10,-1,5,50,0,0,0,0,0}
gui_src_preferences -tabstop 8 -maxbits 24 -windownumber 1

# Open design
gui_sim_run Ucli -exe simv -args {-ucligui } -dir ~/router/rtl -nosource
gui_sim_wait stopped -mstimeout -1 -log gui_sim_run
if { ![gui_sim_state -check active] } {error "Simulator did not start correctly" error}
gui_set_precision 1s
gui_use_schematics

# Create schematic window 'Schematic.1'
set Schematic.1 [gui_sch_show -toplevel TopLevel.1 -name {router}]
gui_show_pin_value_annotate [gui_window_hier_name -window ${Schematic.1}]
gui_show_window -window ${Schematic.1} -show_state maximized -rect {{0 0} {1844 874}}
gui_zoom -window ${Schematic.1} -full


set Source.1 [ gui_create_window -type {Source} -parent ${TopLevel.1} -show_state maximized -rect {{0 0} {1484 874}} ]
gui_src_value_annotate -id ${Source.1} -switch false
gui_set_env TOGGLE::VALUEANNOTATE 0
gui_open_source -id ${Source.1}  -replace -active {router} {~/router/rtl/router.v}
gui_sim_wait stopped
gui_src_set_reusable -id ${Source.1}
