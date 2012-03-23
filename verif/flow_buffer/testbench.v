module testbench();
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
`include "parameters.v"

   parameter Tclk 		      = 2;
   // width required to select individual resource class
   localparam resource_class_idx_width = clogb(num_resource_classes);
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   // total number of routers
   localparam num_routers
     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   // number of routers in each dimension
   localparam num_routers_per_dim = croot(num_routers, num_dimensions);
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
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
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
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
   
   parameter max_reservation_size     = 256;
   parameter time_to_wait_width      = 8;
   localparam reservation_size_width  = clogb(max_reservation_size);

   // measurement interval in cycles
   parameter run_time 		      = 10000;
   integer seed;
   


   
   
   reg clk;
   reg reset;
   reg clk_en;
   reg run;

   
   wire [0:31] current_time_s;
   wire [0:31] current_time_q;
   assign current_time_s = current_time_q+'b1;   
   c_dff
     #(// Parameters
       .width				(32),
       .reset_type			(reset_type))
   destination_timer
     (// Outputs
      .q				(current_time_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(current_time_s));


   wire [0:router_addr_width-1] router_address 	= {router_addr_width{1'b1}};
   
   wire buffer_empty;
   wire reservation_ready;
   wire nonspec_ready;
   wire spec_ready;
   wire [0:flit_data_width-1] buffer_data;
   wire [0:dest_info_width-1] source_address = {router_address};

   //message generator
   wire  message_ready;
   reg [0:reservation_size_width-1] message_size;
   reg [0:dest_info_width-1] message_dest;
   reg has_message;
   assign message_ready  = has_message & buffer_empty;

   wire buffer_gnt;
   
 
   wire grant_ready;
   wire ack_ready;
   wire nack_ready;
   wire buffer_error;



   wire [0:channel_width-1] channel_bton;
   wire [0:channel_width-1] channel_ntob;
   
   
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
       .max_reservation_size		(max_reservation_size),
       .time_to_wait_width		(time_to_wait_width),
       .reset_type			(reset_type))
   thenic
     (// Outputs
      .flow_ctrl			(),
      .channel_out			(channel_ntob),
      .error				(error),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .run				(run),
      .router_address			(router_address),
      .channel_in			(channel_bton));
   


   
   
   flow_buffer
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
       .max_reservation_size		(max_reservation_size),
       .reset_type			(reset_type))
   thebuffer
     (// Outputs
      .buffer_empty			(buffer_empty),
      .reservation_ready		(reservation_ready),
      .nonspec_ready			(nonspec_ready),
      .spec_ready			(spec_ready),
      .output_data			(buffer_data),
      .error (buffer_error),
      // Inputs
      .clk				(clk),
      .run				(run),
      .reset				(reset),
      .source_address			(source_address),
      .message_ready			(message_ready),
      .message_size			(message_size),
      .message_dest			(message_dest),
      .grant_ready			(grant_ready),
      .ack_ready			(ack_ready),
      .nack_ready			(nack_ready),
      .input_data			(channel_ntob[4:channel_width-1]),
      .current_time			(current_time_q),
      .nic_gnt				(buffer_gnt));

   assign buffer_gnt 		     = reservation_ready;
   
   assign grant_ready 		     = (channel_ntob[0:2] == 3'b101);

   rtr_channel_output
     #(// Parameters
       .num_vcs(num_vcs),
       .packet_format(packet_format),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   channel_output_stage
     (// Outputs
      .channel_out			(channel_bton),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .flit_valid_in			(reservation_ready),
      .flit_head_in			(1'b1),
      .flit_tail_in			(1'b1),
      .flit_data_in			(buffer_data),
      .flit_sel_in_ovc			(4'b1000));



   integer total_injected;

   
   
   //message genearrotr
   always@(posedge clk, posedge reset)
     begin
	if(reset)
	  begin
	     has_message 	    <=0;
	     message_size 	    <=0;
	     message_dest 	    <= 0;
	  end
	else
	  begin
	     if(message_ready)
	       total_injected 	     = total_injected +  message_size;
	     
	     
	     
	     if(~has_message)
	       begin 
		  has_message 	    <= ($dist_uniform(seed, 0,  99) < 10);
		  message_size 	    <= $dist_uniform(seed, 1,  max_reservation_size);
		  message_dest 	    <= $dist_uniform(seed, 0, num_routers_per_dim*num_routers_per_dim-2);
	       end
	     else
	       begin
		  if(buffer_empty)
		    begin
		       has_message  <=0;
		       message_size <=0;
		       message_dest <= 0;
		    end
	       end // else: !if(~has_message)	
	  end
     end
   
   //clock
   always
     begin
	clk 		      <= clk_en;
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
	total_injected  = 0;
	
	
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
