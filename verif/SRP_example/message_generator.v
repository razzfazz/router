module message_generator(/*autoarg*/
   // Outputs
   message_size, message_dest, has_message, host_data_head,
   host_data_tail, host_data_valid, host_data,
   // Inputs
   clk, reset, run, host_next_flit, buffer_empty
   );
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
`include "parameters.v"

   parameter seed 			= 1;
   integer msg_gen_seed 		= seed;
   parameter injection_rate 		= 10;
   parameter intra_router_only 		= 1;

   parameter router_id=0;
   parameter node_id=0;
   
   
   
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
   
   parameter max_reservation_size     = 16;
   parameter time_to_wait_width       = 8;
   localparam reservation_size_width  = clogb(max_reservation_size);
   parameter spec_buffer_capacity     = 4;
   localparam spec_buffer_width       = clogb(spec_buffer_capacity);
   
   parameter use_target_dest 		      = 0;
   parameter [0:dest_info_width-1] target_dest 		      = {dest_info_width{1'b0}};
`include "srp_format.v"

   input clk;
   input reset;

   input run;
   
   
   input host_next_flit;
   input buffer_empty;
   
   output [0:reservation_size_width-1] message_size;
   reg  [0:reservation_size_width-1] message_size;
   output [0:dest_info_width-1] message_dest;
   reg [0:dest_info_width-1] message_dest;
   output has_message;
   wire has_message;
   reg generate_message; //generate includes has, generate is filtered if src==dest
   
   
   output host_data_head;
   output host_data_tail;
   output host_data_valid;
   
   output [0:flit_data_width-1]host_data;
   reg  [0:flit_data_width-1]host_data;
   
   reg [0:payload_length_width-1]  host_flit_counter;
   reg [0:reservation_size_width-1] host_message_size;

   //CAUTION this assume all data packets are Max sized
   assign host_data_head   = (|host_message_size) & ~(|host_flit_counter);
   assign host_data_tail   = (|host_message_size) *  (host_flit_counter==max_payload_length);
   
   assign host_data_valid  = |host_message_size;

   wire message_ready 	   = has_message & buffer_empty;
   
   integer i;
   integer total_injected;
   //message generator
   generate
      always@(posedge clk, posedge reset)
	begin
	   if(reset)
	     begin
		generate_message       <= 0;
		message_size 	       <= 0;
		message_dest 	       <= 0;
		host_message_size      <= {reservation_size_width{1'b0}};
		host_data 	       <= {flit_data_width{1'b0}};
		host_flit_counter      <= 0;
	     end
	   else
	     begin
		//stat
		if(message_ready)
		  total_injected 	= total_injected +  message_size;

		//random bits come and go
		for(i = 0; i < flit_data_width; i = i + 1)
		  host_data[i] 	       <= $dist_uniform(msg_gen_seed, 0, 1);

		if(message_ready)
		  begin
		     host_message_size <= message_size;
		  end
		if(host_message_size) //decrement
		  host_message_size    <=host_message_size-(host_data_tail & host_next_flit);

		if(host_next_flit)
		  host_flit_counter    <= host_flit_counter+1'b1;
		
		
		//create message
		if(~has_message&run)
		  begin
		     generate_message  <= ($dist_uniform(msg_gen_seed, 0,  999) < injection_rate);
		     message_size      <=  max_reservation_size-1;
//$dist_uniform(msg_gen_seed,4,  max_reservation_size-1);
		     if(use_target_dest)
		       begin
			  message_dest[0:dest_info_width-1] = target_dest;
		       end
		     else
		       begin
			  if(intra_router_only)
			    begin
			       if(num_nodes_per_router>1)
				 message_dest[router_addr_width:dest_info_width-1]  <= (node_id+$dist_uniform(msg_gen_seed, 0,num_nodes_per_router-2)+1)%num_nodes_per_router;
			       
			       
			       message_dest[0:router_addr_width-1] <= router_id;
			    end
			  else
			    begin
			       if(num_nodes_per_router>1)
				 message_dest[router_addr_width:dest_info_width-1]  <= $dist_uniform(msg_gen_seed, 0,num_nodes_per_router-1);
			       
			       message_dest[0:router_addr_width-1] <= $dist_uniform(msg_gen_seed, 0, num_routers-1);
			    end // else: !if(intra_router_only)
		       end // else: !if(use_target_dest)
		  end // if (~has_message)
		else
		  begin
		     if(message_ready)
		       begin
			  generate_message  <=0;
			  message_size <=0;
			  message_dest <= 0;
		       end
		  end // else: !if(~has_message)	
	     end
	end // always@ (posedge clk, posedge reset)
      wire [0:31] router_address = router_id;
      wire [0:31] node_address = node_id;
      wire conflict =  ~|({router_address[31-router_addr_width+1:31],
			   node_address  [31-node_addr_width+1:31]}^
			  message_dest);
      assign has_message  = generate_message &~conflict;
      

   endgenerate
   

   
endmodule
