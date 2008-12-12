source prolog.tcl

compile_ultra -no_autoungroup
#compile_ultra

report_design
report_resources
check_design

source ${script_dir}/write_outputs.tcl
source ${script_dir}/write_reports.tcl

exit
