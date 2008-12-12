#set_operating_conditions \
    -max WCCOM -max_library ${slow_db} \
    -min BCCOM -min_library ${fast_db}

# set_dont_use [ list slow/DFFS* slow/DFFT*]

set all_input_ports  [ get_ports "*" -filter {@port_direction == in} ]
set all_output_ports [ get_ports "*" -filter {@port_direction == out} ]

source ${script_dir}/setup_clk.tcl

source ${script_dir}/setup_asserts.tcl
