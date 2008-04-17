create_clock -period ${clk_period}  [get_ports ${clk_name}]

set all_inputs_no_clocks [remove_from_collection ${all_input_ports} ${clk_name} ]
set_clock_latency 0      [get_clocks ${clk_name}]

