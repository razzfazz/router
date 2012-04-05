localparam packet_len_start    = lar_info_width+dest_info_width;

localparam spec_ttw_start      = header_info_width+2;
localparam spec_src_start      = spec_ttw_start+time_to_wait_width;
localparam spec_id_start       = spec_src_start +dest_info_width;
localparam spec_data_start     = spec_id_start+ spec_buffer_width;

localparam res_size_start      = header_info_width+2;
localparam res_src_start       = res_size_start +reservation_size_width;
localparam res_data_start      = res_src_start+dest_info_width;

localparam grant_time_start    = flit_data_width-32;
localparam grant_data_start    = header_info_width+2;

localparam nonspec_data_start  = header_info_width+2;

localparam ack_id_start        = header_info_width+2;
localparam ack_data_start      = ack_id_start + spec_buffer_width;

localparam nack_id_start       = header_info_width+2;
localparam nack_data_start     = nack_id_start + spec_buffer_width;
