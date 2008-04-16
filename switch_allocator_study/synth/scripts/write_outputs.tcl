write_file -format verilog -hierarchy -output ${net_dir}/${top}.v ${top}
write_file -format ddc -output ${net_dir}/${top}.ddc
write_sdf ${net_dir}/${top}.sdf
write_parasitics -o ${net_dir}/${top}.par
write_sdc ${net_dir}/${top}.sdc
