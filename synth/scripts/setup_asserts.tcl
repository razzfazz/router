set port_load [eval load_of $cell_lib/BUFFD4/I ]
set_load        $port_load $all_output_ports
set_fanout_load 1          $all_output_ports
