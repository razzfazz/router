module testbench();
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
`include "parameters.v"
   
   parameter channel_delay 		= 2;
   parameter injection_rate 		= 1;
   
   parameter Tclk 			= 2;

   
   
   // width required to select individual resource class
   localparam resource_class_idx_width 	= clogb(num_resource_classes);
   // total number of packet classes
   localparam num_packet_classes 	= num_message_classes * num_resource_classes;
   // number of VCs
   localparam num_vcs 			= num_packet_classes * num_vcs_per_class;
   // width required to select individual VC
   localparam vc_idx_width 		= clogb(num_vcs);
   // total number of routers
   localparam num_routers
 					= (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   // number of routers in each dimension
   localparam num_routers_per_dim 	= croot(num_routers, num_dimensions);
   // width required to select individual router in a dimension
   localparam dim_addr_width 		= clogb(num_routers_per_dim);
   // width required to select individual router in entire network
   localparam router_addr_width 	= num_dimensions * dim_addr_width;
   // connectivity within each dimension
   localparam connectivity
 					= (topology == `TOPOLOGY_MESH) ?
       `CONNECTIVITY_LINE :
       (topology == `TOPOLOGY_TORUS) ?
       `CONNECTIVITY_RING :
       (topology == `TOPOLOGY_FBFLY) ?
       `CONNECTIVITY_FULL :
       -1;
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = ((connectivity == `CONNECTIVITY_LINE) ||
	(connectivity == `CONNECTIVITY_RING)) ?
       2 :
       (connectivity == `CONNECTIVITY_FULL) ?
       (num_routers_per_dim - 1) :
       -1;
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   // width required for lookahead routing information
   localparam lar_info_width = port_idx_width + resource_class_idx_width;
   // total number of bits required for storing routing information
   localparam dest_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + num_vcs) :
       -1;
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   // channel width
   localparam channel_width 	    = flit_ctrl_width + flit_data_width;
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   // total number of bits required for storing header information
   
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       route_info_width: 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       route_info_width: 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (route_info_width + payload_length_width) : 
       -1;
   parameter spec_buffer_capacity     = 8;
   parameter max_reservation_size     = 16;
   parameter time_to_wait_width       = 8;
   localparam reservation_size_width  = clogb(max_reservation_size);

   // measurement interval in cycles
   parameter run_time 		      = 10000;
   integer seed;
   


   
   
   reg clk;
   reg reset;
   reg clk_en;
   reg run;

   wire [0:router_addr_width-1] router_address 	= {router_addr_width{1'b1}};
   
   
   

   wire [0:channel_width-1] channel_bton;
   wire [0:channel_width-1] channel_bton_predly;
   wire [0:channel_width-1] channel_ntob;
   wire [0:channel_width-1] channel_ntob_predly;

   wire [0:flow_ctrl_width-1] fc_bton;
   wire [0:flow_ctrl_width-1] fc_bton_predly;
   wire [0:flow_ctrl_width-1] fc_ntob;
   wire [0:flow_ctrl_width-1] fc_ntob_predly;

   
 
   wire [0:flit_data_width-1] host_data_one;
   wire host_data_valid_one;
   wire host_data_tail_one;
   wire host_data_head_one;
   wire has_message_one;
   wire [0:dest_info_width-1] message_dest_one;
   wire [0:reservation_size_width-1] message_size_one;
   
   wire buffer_empty_one;
   wire host_next_flit_one;

   wire error_one;
   wire message_ready_one  = has_message_one & buffer_empty_one;
			      
   
   message_generator
     #(// Parameters
       .seed(2),
       .injection_rate			(injection_rate),
       .max_reservation_size		(max_reservation_size),
       .time_to_wait_width		(time_to_wait_width),
       .spec_buffer_capacity		(spec_buffer_capacity))
   msg_gen_one
     (// Outputs
      .message_size			(message_size_one),
      .message_dest			(message_dest_one),
      .has_message			(has_message_one),
      .host_data_head			(host_data_head_one),
      .host_data_tail			(host_data_tail_one),
      .host_data_valid			(host_data_valid_one),
      .host_data			(host_data_one),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .host_next_flit			(host_next_flit_one),
      .buffer_empty			(buffer_empty_one));
 
   wire [0:node_addr_width-1] node_address_one = {node_addr_width{1'b1}};
   
   test_nic
     #(// Parameters
       .topology			(topology),
       .num_flits_per_vc		(num_flits_per_vc),
       .num_message_classes		(num_message_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_nodes			(num_nodes),
       .num_dimensions			(num_dimensions),
       .num_nodes_per_router		(num_nodes_per_router),
       .packet_format			(packet_format),
       .flow_ctrl_type			(flow_ctrl_type),
       .flow_ctrl_bypass		(flow_ctrl_bypass),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .routing_type			(routing_type),
       .dim_order			(dim_order),
       .elig_mask			(elig_mask),
       .spec_buffer_capacity(spec_buffer_capacity),
       .max_reservation_size		(max_reservation_size),
       .time_to_wait_width		(time_to_wait_width),
       .reset_type			(reset_type))
   thenic_one
     (// Outputs
      .flow_ctrl_eject			(fc_ntob_predly),
      .channel_inject			(channel_ntob_predly),
      .error				(error_one),
      .host_next_flit			(host_next_flit_one),
      .buffer_empty			(buffer_empty_one),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .run				(run),
      .source_address			({router_address,node_address_one}),
      .channel_eject			(channel_bton),
      .message_ready			(message_ready_one),
      .message_size			(message_size_one),
      .message_dest			(message_dest_one),
      .host_data_valid			(host_data_valid_one),
      .host_data_head			(host_data_head_one),
      .host_data_tail			(host_data_tail_one),
      .host_data			(host_data_one),
      .flow_ctrl_inject			(fc_bton)
      );



   wire [0:flit_data_width-1] host_data_two;
   wire host_data_valid_two;
   wire host_data_tail_two;
   wire host_data_head_two;
   wire has_message_two;
   wire [0:dest_info_width-1] message_dest_two;
   wire [0:reservation_size_width-1] message_size_two;
   
   wire buffer_empty_two;
   wire host_next_flit_two;

   wire error_two;
   wire message_ready_two  = has_message_two & buffer_empty_two;
			      
   
   message_generator
     #(// Parameters
       .seed(1),
       .injection_rate			(injection_rate),
       .max_reservation_size		(max_reservation_size),
       .time_to_wait_width		(time_to_wait_width),
       .spec_buffer_capacity		(spec_buffer_capacity))
   msg_gen_two
     (// Outputs
      .message_size			(message_size_two),
      .message_dest			(message_dest_two),
      .has_message			(has_message_two),
      .host_data_head			(host_data_head_two),
      .host_data_tail			(host_data_tail_two),
      .host_data_valid			(host_data_valid_two),
      .host_data			(host_data_two),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .host_next_flit			(host_next_flit_two),
      .buffer_empty			(buffer_empty_two));
 
   wire [0:node_addr_width-1] node_address_two = {node_addr_width{1'b1}};
   
   test_nic
     #(// Parameters
       .topology			(topology),
       .num_flits_per_vc		(num_flits_per_vc),
       .num_message_classes		(num_message_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_nodes			(num_nodes),
       .num_dimensions			(num_dimensions),
       .num_nodes_per_router		(num_nodes_per_router),
       .packet_format			(packet_format),
       .flow_ctrl_type			(flow_ctrl_type),
       .flow_ctrl_bypass		(flow_ctrl_bypass),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .routing_type			(routing_type),
       .dim_order			(dim_order),
       .elig_mask			(elig_mask),
       .spec_buffer_capacity(spec_buffer_capacity),
       .max_reservation_size		(max_reservation_size),
       .time_to_wait_width		(time_to_wait_width),
       .reset_type			(reset_type))
   thenic_two
     (// Outputs
      .flow_ctrl_eject			(fc_bton_predly),
      .channel_inject			(channel_bton_predly),
      .error				(error_two),
      .host_next_flit			(host_next_flit_two),
      .buffer_empty			(buffer_empty_two),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .run				(run),
      .source_address			({router_address,node_address_two}),
      .channel_eject			(channel_ntob),
      .message_ready			(message_ready_two),
      .message_size			(message_size_two),
      .message_dest			(message_dest_two),
      .host_data_valid			(host_data_valid_two),
      .host_data_head			(host_data_head_two),
      .host_data_tail			(host_data_tail_two),
      .host_data			(host_data_two),
      .flow_ctrl_inject			(fc_ntob)
      );


   c_shift_reg
     #(.width(channel_width),
       .depth(channel_delay),
       .reset_type(reset_type))
   bton_dly
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .data_in(channel_bton_predly),
      .data_out(channel_bton));

   c_shift_reg
     #(.width(channel_width),
       .depth(channel_delay),
       .reset_type(reset_type))
   ntob_dly
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .data_in(channel_ntob_predly),
      .data_out(channel_ntob));
   
   c_shift_reg
     #(.width(flow_ctrl_width),
       .depth(channel_delay),
       .reset_type(reset_type))
   fc_bton_dly
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .data_in(fc_bton_predly),
      .data_out(fc_bton));

   c_shift_reg
     #(.width(flow_ctrl_width),
       .depth(channel_delay),
       .reset_type(reset_type))
   fc_ntob_dly
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .data_in(fc_ntob_predly),
      .data_out(fc_ntob));
   
   


   
   //clock
   always
     begin
	clk <= clk_en;
	#(Tclk/2);
	clk <= 1'b0;
	#(Tclk/2);
	end

   
   integer cycles;   
   initial
     begin
	seed 	    = 10;
	
   	reset 	    = 1'b0;
	clk_en 	    = 1'b0;
	run 	    = 1'b0;
	cycles 	    = 0;
	
	
	#(Tclk);
	#(Tclk/2);
	reset = 1'b1;
	#(Tclk);
	reset = 1'b0;
	#(Tclk);
	clk_en = 1'b1;
	#(Tclk/2);
	run 	= 1'b1;
	while(cycles < run_time)
	  begin
	     cycles 				= cycles + 1;
	     #(Tclk);
	  end
	$finish;      
     end
   
   
endmodule
