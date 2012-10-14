/*
TODO
 -Data correctness check
 
*/


module testbench();
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
`include "parameters.v"
   
   parameter channel_delay 		= 1;
   parameter victim_rate 		= 3;
   
   parameter injection_rate 		= 9999;//out of 9999
   
   parameter Tclk 			= 2.0;

   
   
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
   parameter spec_buffer_capacity     = 4;
   parameter max_reservation_size     = 16;
   parameter time_to_wait_width       = 8;
   localparam reservation_size_width  = clogb(max_reservation_size);
   localparam spec_buffer_width       = clogb(spec_buffer_capacity);

   //parameter over_head 	      = 1'b1;
   
`include "srp_format.v"
   
   
   // measurement interval in cycles
   parameter run_time 		      = 30000;
   parameter cool_time 		      = 0;
   parameter  seed = 90;
   

   reg clk;
   reg reset;
   reg clk_en;
   reg run;
   reg run_mesg_gen;
   
      
   
   wire [0:router_addr_width-1] router_zero_address 	= {router_addr_width{1'b0}};
   wire [0:router_addr_width-1] router_one_address 	= 1;

   wire [0:num_ports*flow_ctrl_width-1] r_zero_flow_ctrl_out_ip;
   wire [0:num_ports*channel_width-1]  r_zero_channel_out_op;
   wire [0:num_ports*flow_ctrl_width-1] r_one_flow_ctrl_out_ip;
   wire [0:num_ports*channel_width-1]  r_one_channel_out_op;
   wire r_zero_error;
   wire r_one_error;

   wire [0:num_ports*channel_width-1] r_zero_channel_in_ip;
   wire [0:num_ports*flow_ctrl_width-1] r_zero_flow_ctrl_in_op;
   wire [0:num_ports*channel_width-1] r_one_channel_in_ip;
   wire [0:num_ports*flow_ctrl_width-1] r_one_flow_ctrl_in_op;

   //destination correctly ness check
   wire [0:num_nodes_per_router-1] r_zero_dest_mismatch_error;
   wire [0:num_nodes_per_router-1] r_one_dest_mismatch_error;

   //extracted wires from the nodes
   wire [0:num_nodes_per_router-1] r_zero_rx_valid;
   wire [0:num_nodes_per_router-1] r_zero_rx_head;
   wire [0:vc_idx_width-1] r_zero_rx_vc [0:num_nodes_per_router-1];

   wire [0:num_nodes_per_router-1] r_zero_tx_valid;
   wire [0:num_nodes_per_router-1] r_zero_tx_head;
   wire [0:vc_idx_width-1] r_zero_tx_vc [0:num_nodes_per_router-1];

   wire [0:num_nodes_per_router-1] r_one_rx_valid;
   wire [0:num_nodes_per_router-1] r_one_rx_head;
   wire [0:vc_idx_width-1] r_one_rx_vc [0:num_nodes_per_router-1];

   wire [0:num_nodes_per_router-1] r_one_tx_valid;
   wire [0:num_nodes_per_router-1] r_one_tx_head;
   wire [0:vc_idx_width-1] r_one_tx_vc [0:num_nodes_per_router-1];
   

   //Router zero ports
   generate
      genvar port;
      for(port = 0; port<num_ports; port=port+1)
	begin:ports_zero
	   wire[0:channel_width-1] channel_ntor_predly;
	   wire[0:channel_width-1] channel_ntor;
	   wire[0:flow_ctrl_width-1] fc_ntor_predly;
	   wire[0:flow_ctrl_width-1] fc_ntor;
	   
	   wire[0:channel_width-1] channel_rton_predly;
	   wire[0:channel_width-1] channel_rton;
	   wire[0:flow_ctrl_width-1] fc_rton_predly;
	   wire[0:flow_ctrl_width-1] fc_rton;
	   //if(node<num_nodes_per_router)
	   localparam node  = port-(num_ports-num_nodes_per_router);
	   if((num_ports-num_nodes_per_router)<=port)
	     begin
		wire [0:flit_data_width-1] host_data;
		wire host_data_valid;
		wire host_data_tail;
		wire host_data_head;
		wire has_message;
		wire [0:dest_info_width-1] message_dest;
		wire [0:reservation_size_width-1] message_size;
		
		wire buffer_empty;
		wire host_next_flit;

		wire nic_error;
		wire message_ready  = has_message & buffer_empty;


		message_generator
		  #(// Parameters
		    .seed(seed+node),
		    .router_id(0),
		    .node_id(node),
		    //.injection_rate (injection_rate),
		    .injection_rate (node<2?0:injection_rate),//example
		    .use_target_dest(1),//example
		    .target_dest({dest_info_width{1'b0}}),//example
		    .max_reservation_size		(max_reservation_size),
		    .time_to_wait_width		(time_to_wait_width),
		    .spec_buffer_capacity		(spec_buffer_capacity),
		    .intra_router_only(0))
		msg_gen
		  (// Outputs
		   .message_size			(message_size),
		   .message_dest			(message_dest),
		   .has_message			(has_message),
		   .host_data_head			(host_data_head),
		   .host_data_tail			(host_data_tail),
		   .host_data_valid			(host_data_valid),
		   .host_data			(host_data),
		   // Inputs
		   .clk				(clk),
		   .reset				(reset),
		   .run(run_mesg_gen),
		   .host_next_flit			(host_next_flit),
		   .buffer_empty			(buffer_empty));

		wire [0:31] node_holder = node;
		wire [0:node_addr_width-1] node_address = node_holder[31-node_addr_width+1:31];


		assign r_zero_dest_mismatch_error[node]  = channel_rton[0] &
							   channel_rton[flit_ctrl_width-1] &
							   |({router_zero_address,node_address}^channel_rton[flit_ctrl_width+dest_start+:dest_info_width]);
		
		
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
		thenic
		  (// Outputs
		   .flow_ctrl_eject			(fc_ntor_predly),
		   .channel_inject			(channel_ntor_predly),
		   .error				(nic_error),
		   .host_next_flit			(host_next_flit),
		   .buffer_empty			(buffer_empty),
		   // Inputs
		   .clk				(clk),
		   .reset				(reset),
		   .run				(run),
		   .source_address			({router_zero_address,node_address}),
		   .channel_eject			(channel_rton),
		   .message_ready			(message_ready),
		   .message_size			(message_size),
		   .message_dest			(message_dest),
		   .host_data_valid			(host_data_valid),
		   .host_data_head			(host_data_head),
		   .host_data_tail			(host_data_tail),
		   .host_data			(host_data),
		   .flow_ctrl_inject			(fc_rton)
		   );

		c_shift_reg
		  #(.width(channel_width+flow_ctrl_width),
		    .depth(channel_delay),
		    .reset_type(reset_type))
		node_to_router_dly
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .data_in({fc_ntor_predly,channel_ntor_predly}),
		   .data_out({fc_ntor, channel_ntor}));
		c_shift_reg
		  #(.width(channel_width+flow_ctrl_width),
		    .depth(channel_delay),
		    .reset_type(reset_type))
		router_to_node_dly
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .data_in({fc_rton_predly,channel_rton_predly}),
		   .data_out({fc_rton, channel_rton}));

		
		assign r_zero_rx_valid[node]  = channel_rton_predly[0];
		assign r_zero_rx_head[node]   = channel_rton_predly[flit_ctrl_width-1];
		assign r_zero_rx_vc[node]     = channel_rton_predly[1+:vc_idx_width];
		
		assign r_zero_tx_valid[node]  = channel_ntor[0];
		assign r_zero_tx_head[node]   = channel_ntor[flit_ctrl_width-1];
		assign r_zero_tx_vc[node]     = channel_ntor[1+:vc_idx_width];
		
		
		assign fc_rton_predly 	      = r_zero_flow_ctrl_out_ip[port*flow_ctrl_width+:flow_ctrl_width];
		assign channel_rton_predly    = r_zero_channel_out_op[port*channel_width+:channel_width];
		
		assign r_zero_flow_ctrl_in_op[port*flow_ctrl_width+:flow_ctrl_width]      = fc_ntor;
		assign r_zero_channel_in_ip[port*channel_width+:channel_width]      = channel_ntor;
		
	     end // if ((num_ports-num_nodes_per_router)<=port)
	   else
	     begin
		//wire unconnected_valid 	= channel_out_op[port*channel_width];
	   	
	     end // else: !if((num_ports-num_nodes_per_router)<=port)
	end // block: ports
   endgenerate



   //Router one ports
   generate
      genvar port;
      for(port = 0; port<num_ports; port=port+1)
	begin:ports_one
	   wire[0:channel_width-1] channel_ntor_predly;
	   wire[0:channel_width-1] channel_ntor;
	   wire[0:flow_ctrl_width-1] fc_ntor_predly;
	   wire[0:flow_ctrl_width-1] fc_ntor;
	   
	   wire[0:channel_width-1] channel_rton_predly;
	   wire[0:channel_width-1] channel_rton;
	   wire[0:flow_ctrl_width-1] fc_rton_predly;
	   wire[0:flow_ctrl_width-1] fc_rton;
	   //if(node<num_nodes_per_router)
	   localparam node  = port-(num_ports-num_nodes_per_router);
	   if((num_ports-num_nodes_per_router)<=port)
	     begin
		wire [0:flit_data_width-1] host_data;
		wire host_data_valid;
		wire host_data_tail;
		wire host_data_head;
		wire has_message;
		wire [0:dest_info_width-1] message_dest;
		wire [0:reservation_size_width-1] message_size;
		
		wire buffer_empty;
		wire host_next_flit;

		wire nic_error;
		wire message_ready  = has_message & buffer_empty;


		message_generator
		  #(// Parameters
		    .seed(seed*2+node),
		    .router_id(1),
		    .node_id(node),
		    .injection_rate((node==0)?victim_rate :injection_rate),
		    .use_target_dest(1),//example
		    .target_dest((node==0)?{3'b001}:{dest_info_width{1'b0}}),//example
		    //.target_dest({dest_info_width{1'b0}}),//example
		    .max_reservation_size		(max_reservation_size),
		    .time_to_wait_width		(time_to_wait_width),
		    .spec_buffer_capacity		(spec_buffer_capacity),
		    .intra_router_only(0))
		msg_gen
		  (// Outputs
		   .message_size			(message_size),
		   .message_dest			(message_dest),
		   .has_message			(has_message),
		   .host_data_head			(host_data_head),
		   .host_data_tail			(host_data_tail),
		   .host_data_valid			(host_data_valid),
		   .host_data			(host_data),
		   // Inputs
		   .clk				(clk),
		   .reset				(reset),
		   .run(run_mesg_gen),
		   .host_next_flit			(host_next_flit),
		   .buffer_empty			(buffer_empty));

		wire [0:31] node_holder = node;
		wire [0:node_addr_width-1] node_address = node_holder[31-node_addr_width+1:31];
		
		assign r_one_dest_mismatch_error[node]  = channel_rton[0] &
							  channel_rton[flit_ctrl_width-1] &
							  |({router_one_address,node_address}^channel_rton[flit_ctrl_width+dest_start+:dest_info_width]);
		
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
		thenic
		  (// Outputs
		   .flow_ctrl_eject			(fc_ntor_predly),
		   .channel_inject			(channel_ntor_predly),
		   .error				(nic_error),
		   .host_next_flit			(host_next_flit),
		   .buffer_empty			(buffer_empty),
		   // Inputs
		   .clk				(clk),
		   .reset				(reset),
		   .run				(run),
		   .source_address			({router_one_address,node_address}),
		   .channel_eject			(channel_rton),
		   .message_ready			(message_ready),
		   .message_size			(message_size),
		   .message_dest			(message_dest),
		   .host_data_valid			(host_data_valid),
		   .host_data_head			(host_data_head),
		   .host_data_tail			(host_data_tail),
		   .host_data			(host_data),
		   .flow_ctrl_inject			(fc_rton)
		   );

		c_shift_reg
		  #(.width(channel_width+flow_ctrl_width),
		    .depth(channel_delay),
		    .reset_type(reset_type))
		node_to_router_dly
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .data_in({fc_ntor_predly,channel_ntor_predly}),
		   .data_out({fc_ntor, channel_ntor}));
		c_shift_reg
		  #(.width(channel_width+flow_ctrl_width),
		    .depth(channel_delay),
		    .reset_type(reset_type))
		router_to_node_dly
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .data_in({fc_rton_predly,channel_rton_predly}),
		   .data_out({fc_rton, channel_rton}));


		assign r_one_rx_valid[node]  = channel_rton_predly[0];
		assign r_one_rx_head[node]   = channel_rton_predly[flit_ctrl_width-1];
		assign r_one_rx_vc[node]     = channel_rton_predly[1+:vc_idx_width];
		assign r_one_tx_valid[node]  = channel_ntor[0];
		assign r_one_tx_head[node]   = channel_ntor[flit_ctrl_width-1];
		assign r_one_tx_vc[node] = channel_ntor[1+:vc_idx_width];
		
		assign fc_rton_predly 	    = r_one_flow_ctrl_out_ip[port*flow_ctrl_width+:flow_ctrl_width];
		assign channel_rton_predly  = r_one_channel_out_op[port*channel_width+:channel_width];
		
		assign r_one_flow_ctrl_in_op[port*flow_ctrl_width+:flow_ctrl_width]      = fc_ntor;
		assign r_one_channel_in_ip[port*channel_width+:channel_width]      = channel_ntor;
		
	     end // if ((num_ports-num_nodes_per_router)<=port)
	   else
	     begin
		//wire unconnected_valid 	= channel_out_op[port*channel_width];
	   	
	     end // else: !if((num_ports-num_nodes_per_router)<=port)
	end // block: ports
   endgenerate

   



   router_wrap
     #(.topology(topology),
       .num_flits_per_vc(num_flits_per_vc),
       .num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_nodes(num_nodes),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .packet_format(packet_format),
       .flow_ctrl_type(flow_ctrl_type),
       .flow_ctrl_bypass(flow_ctrl_bypass),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .router_type(router_type),
       .flit_data_width(flit_data_width),
       .error_capture_mode(error_capture_mode),
       .restrict_turns(restrict_turns),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .int_flow_ctrl_type(int_flow_ctrl_type),
       .input_stage_can_hold(input_stage_can_hold),
       .fb_regfile_type(fb_regfile_type),
       .explicit_pipeline_register(explicit_pipeline_register),
       .dual_path_alloc(dual_path_alloc),
       .precomp_ivc_sel(precomp_ivc_sel),
       .precomp_ip_sel(precomp_ip_sel),
       .elig_mask(elig_mask),
       .vc_alloc_type(vc_alloc_type),
       .vc_alloc_arbiter_type(vc_alloc_arbiter_type),
       .vc_alloc_prefer_empty(vc_alloc_prefer_empty),
       .sw_alloc_type(sw_alloc_type),
       .sw_alloc_arbiter_type(sw_alloc_arbiter_type),
       .sw_alloc_spec_type(sw_alloc_spec_type),
       .crossbar_type(crossbar_type),
       .time_to_wait_width(time_to_wait_width),
       .max_reservation_size(max_reservation_size),
       .spec_buffer_capacity(spec_buffer_capacity),
       .reset_type(reset_type))
   r_zero
     (// Outputs
      .flow_ctrl_out_ip		(r_zero_flow_ctrl_out_ip),
      .channel_out_op			(r_zero_channel_out_op),
      .error				(r_zero_error),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .router_address			(router_zero_address),
      .channel_in_ip			(r_zero_channel_in_ip),
      .flow_ctrl_in_op			(r_zero_flow_ctrl_in_op));
   





   
   router_wrap
     #(.topology(topology),
       .num_flits_per_vc(num_flits_per_vc),
       .num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_nodes(num_nodes),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .packet_format(packet_format),
       .flow_ctrl_type(flow_ctrl_type),
       .flow_ctrl_bypass(flow_ctrl_bypass),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .router_type(router_type),
       .flit_data_width(flit_data_width),
       .error_capture_mode(error_capture_mode),
       .restrict_turns(restrict_turns),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .int_flow_ctrl_type(int_flow_ctrl_type),
       .input_stage_can_hold(input_stage_can_hold),
       .fb_regfile_type(fb_regfile_type),
       .explicit_pipeline_register(explicit_pipeline_register),
       .dual_path_alloc(dual_path_alloc),
       .precomp_ivc_sel(precomp_ivc_sel),
       .precomp_ip_sel(precomp_ip_sel),
       .elig_mask(elig_mask),
       .vc_alloc_type(vc_alloc_type),
       .vc_alloc_arbiter_type(vc_alloc_arbiter_type),
       .vc_alloc_prefer_empty(vc_alloc_prefer_empty),
       .sw_alloc_type(sw_alloc_type),
       .sw_alloc_arbiter_type(sw_alloc_arbiter_type),
       .sw_alloc_spec_type(sw_alloc_spec_type),
       .crossbar_type(crossbar_type),
       .time_to_wait_width(time_to_wait_width),
       .max_reservation_size(max_reservation_size),
       .spec_buffer_capacity(spec_buffer_capacity),
       .reset_type(reset_type))
   r_one
     (// Outputs
      .flow_ctrl_out_ip		(r_one_flow_ctrl_out_ip),
      .channel_out_op			(r_one_channel_out_op),
      .error				(r_one_error),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .router_address			(router_one_address),
      .channel_in_ip			(r_one_channel_in_ip),
      .flow_ctrl_in_op			(r_one_flow_ctrl_in_op));

   




   //Inter channel wiring
   c_shift_reg
     #(.width((channel_width+flow_ctrl_width)*2),
       .depth(channel_delay),
       .reset_type(reset_type))
   inter_router_dly
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .data_in({r_zero_channel_out_op[1*channel_width+:channel_width],
		r_zero_flow_ctrl_out_ip[1*flow_ctrl_width+:flow_ctrl_width], 
		r_one_channel_out_op[0*channel_width+:channel_width],
		r_one_flow_ctrl_out_ip[0*flow_ctrl_width+:flow_ctrl_width]}),
      .data_out({r_one_channel_in_ip[0*channel_width+:channel_width],
		 r_one_flow_ctrl_in_op[0*flow_ctrl_width+:flow_ctrl_width],
		 r_zero_channel_in_ip[1*channel_width+:channel_width],
		 r_zero_flow_ctrl_in_op[1*flow_ctrl_width+:flow_ctrl_width]}));
   

   assign r_one_channel_in_ip[1*channel_width+:channel_width] = {channel_width{1'b0}};
   assign r_one_flow_ctrl_in_op[1*flow_ctrl_width+:flow_ctrl_width] = {flow_ctrl_width{1'b0}};
   assign r_zero_channel_in_ip[0*channel_width+:channel_width] = {channel_width{1'b0}};
   assign r_zero_flow_ctrl_in_op[0*flow_ctrl_width+:flow_ctrl_width]= {flow_ctrl_width{1'b0}};

   wire unused_error  = r_zero_channel_out_op[0*channel_width] | 
	r_one_channel_out_op[1*channel_width];





   ///////////////////////
   //Stat tracking
   ///////////////////////

   //TOTAL
   wire [0:31] total_receive_s [0:2*num_nodes_per_router-1];
   wire [0:31] total_receive   [0:2*num_nodes_per_router-1];
   generate
      genvar total_receive_port;
      for(total_receive_port = 0; total_receive_port<num_nodes_per_router; total_receive_port=total_receive_port+1)
	begin:total_receive_count_loop
	   assign total_receive_s[total_receive_port]  =
			      total_receive[total_receive_port]+
			      (r_zero_rx_valid[total_receive_port]);//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   total_receive_count_zero_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(total_receive_s[total_receive_port]),
	      .q(total_receive[total_receive_port]));
	   
	   assign total_receive_s[total_receive_port+num_nodes_per_router]  =
			       total_receive[total_receive_port+num_nodes_per_router]+
			       (r_one_rx_valid[total_receive_port]);//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   total_receive_count_one_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(total_receive_s[total_receive_port+num_nodes_per_router]),
	      .q(total_receive[total_receive_port+num_nodes_per_router]));				   
	end
   endgenerate



   wire [0:31] total_send_s [0:2*num_nodes_per_router-1];
   wire [0:31] total_send   [0:2*num_nodes_per_router-1];
   generate
      genvar total_send_port;
      for(total_send_port = 0; total_send_port<num_nodes_per_router; total_send_port=total_send_port+1)
	begin:total_send_count_loop
	   assign total_send_s[total_send_port]  =
			      total_send[total_send_port]+
			      (r_zero_tx_valid[total_send_port]);//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   total_send_count_zero_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(total_send_s[total_send_port]),
	      .q(total_send[total_send_port]));
	   
	   assign total_send_s[total_send_port+num_nodes_per_router]  =
			       total_send[total_send_port+num_nodes_per_router]+
			       (r_one_tx_valid[total_send_port]);//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   total_send_count_one_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(total_send_s[total_send_port+num_nodes_per_router]),
	      .q(total_send[total_send_port+num_nodes_per_router]));				   
	end
   endgenerate

   /////data only
   wire [0:31] data_receive_s [0:2*num_nodes_per_router-1];
   wire [0:31] data_receive   [0:2*num_nodes_per_router-1];
   generate
      genvar data_receive_port;
      for(data_receive_port = 0; data_receive_port<num_nodes_per_router; data_receive_port=data_receive_port+1)
	begin:data_receive_count_loop
	   assign data_receive_s[data_receive_port]  =
			      data_receive[data_receive_port]+
			      (r_zero_rx_valid[data_receive_port] &
			       (r_zero_rx_vc[data_receive_port]==2 || r_zero_rx_vc[data_receive_port]==3 ));//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   data_receive_count_zero_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(data_receive_s[data_receive_port]),
	      .q(data_receive[data_receive_port]));
	   
	   assign data_receive_s[data_receive_port+num_nodes_per_router]  =
			       data_receive[data_receive_port+num_nodes_per_router]+
			       (r_one_rx_valid[data_receive_port] &
				(r_one_rx_vc[data_receive_port]==2||r_one_rx_vc[data_receive_port]==3));//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   data_receive_count_one_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(data_receive_s[data_receive_port+num_nodes_per_router]),
	      .q(data_receive[data_receive_port+num_nodes_per_router]));				   
	end
   endgenerate



   wire [0:31] data_send_s [0:2*num_nodes_per_router-1];
   wire [0:31] data_send   [0:2*num_nodes_per_router-1];
   generate
      genvar data_send_port;
      for(data_send_port = 0; data_send_port<num_nodes_per_router; data_send_port=data_send_port+1)
	begin:data_send_count_loop
	   assign data_send_s[data_send_port]  =
			      data_send[data_send_port]+
			      (r_zero_tx_valid[data_send_port] &
			       (r_zero_tx_vc[data_send_port]==2||r_zero_tx_vc[data_send_port]==3));//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   data_send_count_zero_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(data_send_s[data_send_port]),
	      .q(data_send[data_send_port]));
	   
	   assign data_send_s[data_send_port+num_nodes_per_router]  =
			       data_send[data_send_port+num_nodes_per_router]+
			       (r_one_tx_valid[data_send_port] &
				(r_one_tx_vc[data_send_port]==2||r_one_tx_vc[data_send_port]==3));//vc 2 or 3
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   data_send_count_one_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(data_send_s[data_send_port+num_nodes_per_router]),
	      .q(data_send[data_send_port+num_nodes_per_router]));				   
	end
   endgenerate



   ///NACK
   
   wire [0:31] nack_s [0:2*num_nodes_per_router-1];
   wire [0:31] nack   [0:2*num_nodes_per_router-1];
   generate
      genvar nack_port;
      for(nack_port = 0; nack_port<num_nodes_per_router; nack_port=nack_port+1)
	begin:nack_count_loop
	   assign nack_s[nack_port]  =
		      nack[nack_port]+
		      (r_zero_rx_valid[nack_port] &
		       r_zero_rx_head [nack_port] &
		       (r_zero_rx_vc  [nack_port]==1)&
		       (r_zero_channel_out_op[(nack_port+2)*channel_width+flit_ctrl_width+default_end+:2]==2'b10));
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   nack_count_zero_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(nack_s[nack_port]),
	      .q(nack[nack_port]));
	   
	   assign nack_s[nack_port+num_nodes_per_router]  =
			       nack[nack_port+num_nodes_per_router]+
			       (r_one_rx_valid[nack_port] &
				r_one_rx_head [nack_port] &
				(r_one_rx_vc  [nack_port]==1)&
				(r_one_channel_out_op[(nack_port+2)*channel_width+flit_ctrl_width+default_end+:2]==2'b10));
				
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   nack_count_one_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(nack_s[nack_port+num_nodes_per_router]),
	      .q(nack[nack_port+num_nodes_per_router]));				   
	end
   endgenerate


   ///SPEC   
   wire [0:31] spec_s [0:2*num_nodes_per_router-1];
   wire [0:31] spec   [0:2*num_nodes_per_router-1];
   generate
      genvar spec_port;
      for(spec_port = 0; spec_port<num_nodes_per_router; spec_port=spec_port+1)
	begin:spec_count_loop
	   assign spec_s[spec_port]  =
		      spec[spec_port]+
		      (r_zero_tx_valid[spec_port] &
		       (r_zero_tx_vc  [spec_port]==3));
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   spec_count_zero_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(spec_s[spec_port]),
	      .q(spec[spec_port]));
	   
	   assign spec_s[spec_port+num_nodes_per_router]  =
			       spec[spec_port+num_nodes_per_router]+
			       (r_one_tx_valid[spec_port] &
				r_one_tx_head [spec_port] &
				(r_one_tx_vc  [spec_port]==3));
				
	   c_dff
	     #(.width(32),
	       .reset_type(reset_type))
	   spec_count_one_reg
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .d(spec_s[spec_port+num_nodes_per_router]),
	      .q(spec[spec_port+num_nodes_per_router]));				   
	end
   endgenerate


   integer srp_in, srp_out;
   integer in_index, out_index;
   integer in_end_index, out_end_index;
   integer srp_in_i,srp_out_i;
   //file IO  for SRP checking
   //assumes explicit length
   always@(negedge clk)
     if(run)
       begin
	  for(srp_in_i = 0; srp_in_i<num_nodes_per_router; srp_in_i=srp_in_i+1)
	    begin:in_ps
	       in_index  = (srp_in_i+2)*channel_width+38;
	       if(r_zero_tx_valid[srp_in_i] &&
		  r_zero_tx_head[srp_in_i] &&
		  (r_zero_tx_vc[srp_in_i]==2))		 
		 $fdisplay(srp_in,"%d %d %b",
			   cycles,
			   r_zero_channel_in_ip[in_index+:30],
			   r_zero_channel_in_ip[in_index+15+:15]);
	       
	       if(r_one_tx_valid[srp_in_i] &&
		  r_one_tx_head[srp_in_i] &&
		  (r_one_tx_vc[srp_in_i]==2))		 
		 $fdisplay(srp_in,"%d %d %b",
			   cycles,
			   r_one_channel_in_ip[in_index+:30],
			   r_one_channel_in_ip[in_index+15+:15]);
	    end
       end
   always@(negedge clk)
     if(run)
       begin
	  for(srp_out_i = 0; srp_out_i <num_nodes_per_router; srp_out_i = srp_out_i + 1)
	    begin:out_ps
	       out_index  = (srp_out_i+2)*channel_width+38;
	       if(r_zero_rx_valid[srp_out_i] &&
		  r_zero_rx_head[srp_out_i] &&
		  (r_zero_rx_vc[srp_out_i]==2))
		 $fdisplay(srp_out,"%d %d %b",
			   cycles,
			   r_zero_channel_out_op[out_index+:30],
			   r_zero_channel_out_op[out_index+15+:15]);
	       if(r_one_rx_valid[srp_out_i] &&
		  r_one_rx_head[srp_out_i] &&
		  (r_one_rx_vc[srp_out_i]==2))
		 $fdisplay(srp_out,"%d %d %b",
			   cycles,
			   r_one_channel_out_op[out_index+:30],
			   r_one_channel_out_op[out_index+15+:15]);
	    end
       end


   

   //Grant time dump
   generate
      genvar gnt_port;
      for(gnt_port = 0; gnt_port<num_nodes_per_router; gnt_port=gnt_port+1)
	begin:gnt_port_loop
	   always@(posedge clk)
	     begin
		//router zero
		if(r_zero_tx_valid[gnt_port] &&
		   r_zero_tx_head[gnt_port] &&
		   (r_zero_tx_vc[gnt_port] == 1) &&
		   (r_zero_channel_in_ip[(gnt_port+2)*channel_width+flit_ctrl_width+default_end+:2]==2'b00))
		  $display("Port %d_0 Grant T %d current %d",gnt_port,r_zero_channel_in_ip[(gnt_port+2)*channel_width+40:(gnt_port+2+1)*channel_width-1],
			   ports_zero[gnt_port+2].thenic.current_time_q);
		if(r_zero_rx_valid[gnt_port] &&
		   r_zero_rx_head[gnt_port] &&
		   (r_zero_rx_vc[gnt_port] == 1) &&
		   (r_zero_channel_out_op[(gnt_port+2)*channel_width+flit_ctrl_width+default_end+:2]==2'b00))
		  $display("Port %d_0 Grant R %d current %d",gnt_port,
			   r_zero_channel_out_op[(gnt_port+2)*channel_width+40:(gnt_port+2+1)*channel_width-1],
			   ports_zero[gnt_port+2].thenic.current_time_q);


		//router one
		  if(r_one_tx_valid[gnt_port] &&
		   r_one_tx_head[gnt_port] &&
		   (r_one_tx_vc[gnt_port] == 1) &&
		   (r_one_channel_in_ip[(gnt_port+2)*channel_width+flit_ctrl_width+default_end+:2]==2'b00))
		  $display("Port %d_1 Grant T %d current %d",gnt_port,
			   r_one_channel_in_ip[(gnt_port+2)*channel_width+40:(gnt_port+2+1)*channel_width-1],
			   ports_one[gnt_port+2].thenic.current_time_q);
		if(r_one_rx_valid[gnt_port] &&
		   r_one_rx_head[gnt_port] &&
		   (r_one_rx_vc[gnt_port] == 1) &&
		   (r_one_channel_out_op[(gnt_port+2)*channel_width+flit_ctrl_width+default_end+:2]==2'b00))
		  $display("Port %d_1 Grant R %d current %d",gnt_port,
			   r_one_channel_out_op[(gnt_port+2)*channel_width+40:(gnt_port+2+1)*channel_width-1],
			   ports_one[gnt_port+2].thenic.current_time_q);
		
	     end
	end // always@ (posedge clk)      
   endgenerate
   
   always@(posedge clk)
     begin
	if(|r_zero_dest_mismatch_error)
	  $display("router zero receivd a dest mismatch");
	if(|r_one_dest_mismatch_error)
	  $display("router one receivd a dest mismatch");
	
     end


   
   integer stat_loop;
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


      //file IO declaration for SRP checking
      srp_in 	= $fopen("srp_input.txt","w");
      srp_out  = $fopen("srp_output.txt","w");
	
   	reset 	      = 1'b0;
	clk_en 	      = 1'b0;
	run 	      = 1'b0;
	run_mesg_gen  = 1'b0;
	cycles 	      = 0;
	
	
	#(Tclk);
	#(Tclk/2);
	reset = 1'b1;
	#(Tclk);
	reset = 1'b0;
	#(Tclk);
	clk_en = 1'b1;
	#(Tclk/2);
	run 	      = 1'b1;
	run_mesg_gen  = 1'b1;
	
	while(cycles < run_time)
	  begin
	     cycles 				= cycles + 1;
	     #(Tclk);
	     end
	run_mesg_gen =0'b1;
	while(cycles < run_time+cool_time)
	  begin
	     cycles 				= cycles + 1;
	     #(Tclk);
	     end
	
	for(stat_loop = 0; stat_loop<2*num_nodes_per_router; stat_loop=stat_loop+1)
	  begin
	     $display("Node %d",stat_loop);
	     $display("\tTota tx\t%d",total_send[stat_loop]);
	     $display("\tData tx\t%d",data_send[stat_loop]);
	     $display("\tSpec tx\t%d",spec[stat_loop]);
	     $display("\tTota rx\t%d",total_receive[stat_loop]);
	     $display("\tData rx\t%d",data_receive[stat_loop]);
	     $display("\tNack rx\t%d\n",nack[stat_loop]);
	  end
	$finish;      
     end
   
   
endmodule
