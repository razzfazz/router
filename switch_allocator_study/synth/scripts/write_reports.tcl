report_timing -nworst 5 > ${rpt_dir}/${top}.timing
report_area -physical  > ${rpt_dir}/${top}.area
report_cell > ${rpt_dir}/${top}.cell
report_design -verbose  > ${rpt_dir}/${top}.design
#report_power -verbose -hier -nosplit > ${rpt_dir}/${top}.power
report_power -verbose -hier > ${rpt_dir}/${top}.power
#report_cell -nosplit > ${rpt_dir}/${top}.cell
#report_cell -nosplit [get_cells -hierarchical * ] >> ${rpt_dir}/${top}.cell
#report_reference -nosplit > ${rpt_dir}/${top}.reference
