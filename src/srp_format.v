//there variable are identical to all packets
localparam lar_start 	       = 0;
localparam dest_start 	       = lar_start+lar_info_width;
localparam packet_len_start    = dest_start+dest_info_width;
localparam default_end 	       = packet_len_start + payload_length_width;

localparam nonspec_data_start  = default_end;

localparam spec_src_start      = default_end;
localparam spec_ttw_start      = spec_src_start + dest_info_width;

localparam spec_id_start       = spec_ttw_start+time_to_wait_width;
localparam spec_data_start     = spec_id_start+ spec_buffer_width;

localparam res_src_start       = default_end;
localparam res_size_start      = res_src_start + dest_info_width;
localparam res_data_start      = res_size_start +reservation_size_width;

localparam grant_data_start    = default_end+2;
localparam grant_time_start    = flit_data_width-32;

localparam ack_id_start        = default_end+2;
localparam ack_data_start      = ack_id_start + spec_buffer_width;

localparam nack_id_start       = default_end+2;
localparam nack_data_start     = nack_id_start + spec_buffer_width;
