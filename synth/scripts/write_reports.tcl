# ----------------------------------------------------------------------
#
#  File: write_reports.tcl
#
# ----------------------------------------------------------------------
report_timing -nworst 5 > $rpt_dir/$top.timing
report_area -phys  > $rpt_dir/$top.area
report_cell -nosplit > $rpt_dir/$top.cell
report_cell -nosplit [get_cells -hierarchical * ] >> $rpt_dir/$top.cell
report_design -verbose  > $rpt_dir/$top.design
report_power -verbose -hier -nosplit > $rpt_dir/$top.power
report_reference -nosplit > $rpt_dir/$top.reference
