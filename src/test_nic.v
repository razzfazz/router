/*
 *Currently this "NIC" 
 * Hard coded for 4 VCs
 * can receive reservation but not reply
 * ejection fifo, ejection arbitration and ejection flow control
 */         

module test_nic(/*autoarg*/
   // Outputs
   flow_ctrl, channel_out, error,
   // Inputs
   clk, reset, run, router_address, channel_in
   );
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"

   // select network topology
   parameter topology 		     = `TOPOLOGY_FBFLY;
   // flit buffer entries per VC
   parameter num_flits_per_vc 	     = 8;
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   // number of bits required for flit buffer addresses
   localparam flit_buffer_idx_width  = clogb(num_flits_per_vc);
      // number of message classes (e.g. request, reply)
   parameter num_message_classes     = 2;
      // total number of packet classes
   localparam num_packet_classes     = num_message_classes;   
      // number of VCs per class
   parameter num_vcs_per_class 	     = 2;
      // number of VCs
   localparam num_vcs 		     = num_packet_classes * num_vcs_per_class;
      // width required to select individual VC
   localparam vc_idx_width 	     = clogb(num_vcs);
      // total number of nodes
   parameter num_nodes 		     = 64;
      // number of dimensions in network
   parameter num_dimensions 	     = 2;
      // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router    = 4;
   // total number of routers
   localparam num_routers	     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
      // number of routers in each dimension
   localparam num_routers_per_dim    = croot(num_routers, num_dimensions);
      // width required to select individual router in a dimension
   localparam dim_addr_width 	     = clogb(num_routers_per_dim);
      // width required to select individual router in entire network
   localparam router_addr_width      = num_dimensions * dim_addr_width;
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
      // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
      // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
      // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
      // make incoming flow control signals bypass the output VC state tracking 
   // logic
   parameter flow_ctrl_bypass = 1;
      // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
      // maximum payload length (in flits)
   parameter max_payload_length = 4;
      // minimum payload length (in flits)
   parameter min_payload_length = 0;
      // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
      // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
      // width of flit payload data
   parameter flit_data_width   = 64;
      // channel width
   localparam channel_width    = flit_ctrl_width + flit_data_width;
      // width required for lookahead routing information
   localparam lar_info_width   = port_idx_width;
      // select routing function type
   parameter routing_type      = `ROUTING_TYPE_PHASED_DOR;
      // total number of bits required for storing routing information
   localparam dest_info_width
 			       = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       ( router_addr_width + node_addr_width) : 
       -1;
      // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
      // total number of bits required for storing header information
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       route_info_width: 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       route_info_width : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (route_info_width + payload_length_width ) : 
       -1;
      // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask = `ELIG_MASK_NONE;
   // maximum packet length (in flits)
   localparam max_packet_length = 1 + max_payload_length;
   // total number of bits required to represent maximum packet length
   localparam packet_length_width = clogb(max_packet_length);

   
   parameter max_reservation_size     = 256;
   localparam reservation_size_width  = clogb(max_reservation_size);
   parameter reset_type 	      = `RESET_TYPE_ASYNC;
   
   
   input clk;
   input reset;
   input run;

   input [0:router_addr_width-1] router_address;   
   
   
   input [0:channel_width-1] channel_in;
   output [0:flow_ctrl_width-1] flow_ctrl;
   output[0:channel_width-1] channel_out;

   output error;
   
   
   //Raw input from the router
   wire 			flit_valid;
   wire 			flit_head;
   wire [0:num_vcs-1] 		flit_head_ivc;
   wire 			flit_tail;
   wire [0:num_vcs-1] 		flit_tail_ivc;
   wire [0:flit_data_width-1] 	flit_data;
   wire [0:num_vcs-1] 		flit_sel_ivc;
   rtr_channel_input
     #(.num_vcs(num_vcs),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .route_info_width(route_info_width),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   channel_input_stage
     (.clk(clk),
      .reset(reset),
      .active(run),
      .channel_in(channel_in),
      .flit_valid_out(flit_valid),
      .flit_head_out(flit_head),
      .flit_head_out_ivc(flit_head_ivc),
      .flit_tail_out(flit_tail),
      .flit_tail_out_ivc(flit_tail_ivc),
      .flit_data_out(flit_data),
      .flit_sel_out_ivc(flit_sel_ivc));

   //credit reply based which vc was processed
   wire [0:num_vcs-1] 		buffer_empty_ivc;
   wire 			update;
   assign update  = ~&buffer_empty_ivc;
   wire [0:num_vcs-1] 		ejection_gnt_ivc;
   
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   channel_in_fc
     (.clk(clk),
      .reset(reset),
      .active(run),
      .fc_event_valid_in(update),
      .fc_event_sel_in_ivc(ejection_gnt_ivc),
      .flow_ctrl_out(flow_ctrl));

   
   //////////////////////////
   //NIC Receive FIFO
   //  65 wide fifo, flit_data + is_flit_head
   wire [0:num_vcs-1] 		buffer_push_ivc;
   assign buffer_push_ivc = {num_vcs{flit_valid}} & flit_sel_ivc;
   wire [0:num_vcs-1] 		buffer_pop_ivc;
   assign buffer_pop_ivc  = ejection_gnt_ivc
;
   wire [0:num_vcs*(flit_data_width+1)-1] input_fifo_data;
   wire [0:num_vcs*2-1] input_fifo_error;
   wire [0:num_vcs-1] input_fifo_empty;
   
   generate
      genvar 		    ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   wire buffer_push;
	   assign buffer_push = buffer_push_ivc[ivc];
	   wire buffer_pop;
	   assign buffer_pop = buffer_pop_ivc[ivc];
	   wire 			    buffer_almost_empty;
	   wire 			    buffer_empty;
	   wire 			    buffer_almost_full;
	   wire 			    buffer_full;
	   wire [0:flit_count_width-1] 	    buffer_free;
	   wire [0:1] 			    buffer_errors;
	   wire [0:flit_data_width+1-1] buffer_pop_data;
	   c_fifo
	     #(
	       // Parameters
	       .depth			(num_flits_per_vc),
	       .width			(flit_data_width+1),
	       .regfile_type		(`REGFILE_TYPE_FF_2D),
	       .reset_type		(reset_type))
	   eject_fifo
	     (// Outputs
	      .pop_data			(buffer_pop_data),
	      .almost_empty		(buffer_almost_empty),
	      .empty			(buffer_empty),
	      .almost_full		(buffer_almost_full),
	      .full			(buffer_full),
	      .errors			(buffer_errors),
	      // Inputs
	      .clk			(clk),
	      .reset			(reset),
	      .push_active		(run),
	      .pop_active		(run),
	      .push			(buffer_push),
	      .pop			(buffer_pop),
	      .push_data		({flit_data,flit_head}));
	   assign buffer_empty_ivc[ivc]  = buffer_empty;
	   assign input_fifo_data[ivc*(flit_data_width+1)+:(flit_data_width+1)]
 	     =buffer_pop_data;
	   assign input_fifo_error[ivc*2+:2] = buffer_errors;
	   assign input_fifo_empty[ivc]  = buffer_empty;
	   end
   endgenerate
   assign error 			 = |input_fifo_error;

   //////////////////////
   //Ejection arbitration
   //Strict priority grant > res > ack/nack > nonspec > spec
   wire[0:4] ejection_req;
   wire[0:4] ejection_carry;
   wire[0:4] ejection_gnt;

   //these requests NEEDS to be modified significantly, add as we see fit
   assign ejection_req[0]  = ~input_fifo_empty[1] &  //Grant
			    ~(|input_fifo_data[(flit_data_width+1)+header_info_width+:2]);
   assign ejection_req[1] = ~input_fifo_empty[0] & //Reser
			    ~grant_almost_full;  
   assign ejection_req[2] = ~input_fifo_empty[1] &  //ack/nack
			    (|input_fifo_data[(flit_data_width+1)+header_info_width+:2]);
   assign ejection_req[3]    = ~input_fifo_empty[3];  //nonspec
   assign ejection_req[4]    = ~input_fifo_empty[2];  //spec
   
   assign ejection_carry[0:4] = {1'b1, ~ejection_req[0:3]&ejection_carry[0:3]};
   assign ejection_gnt[0:4] = ejection_req[0:4]&ejection_carry[0:4];
   //reduce 5 gnt signal to the 4 vcs
   assign ejection_gnt_ivc[0:3] = {ejection_gnt[1], 
				   ejection_gnt[0]|ejection_gnt[2],
				   ejection_gnt[3:4]};

   //signals for internal ejection processing
   wire ejection_valid 	= |ejection_gnt_ivc;
   wire ejection_head 	= |{ejection_gnt_ivc &
	{input_fifo_data[1*(flit_data_width+1)-1],
	 input_fifo_data[2*(flit_data_width+1)-1],
	 input_fifo_data[3*(flit_data_width+1)-1],
	 input_fifo_data[4*(flit_data_width+1)-1]}};
   

   
   ////////////////////////
   //Reservation request 	
   //extract reservaiton info
   wire reservation_request  = ejection_valid&ejection_head&(ejection_gnt_ivc[0]);
   wire [0:flit_data_width-1] reservation_data  = input_fifo_data[0:flit_data_width-1];
   wire [0:reservation_size_width-1] reservation_size = 
				     (reservation_request)?
				     reservation_data[(header_info_width+2)+:reservation_size_width]:
				     {reservation_size_width{1'b0}};
   wire [0:dest_info_width-1] reservation_src = (reservation_request)?
			      reservation_data[(header_info_width+2+reservation_size_width)+:dest_info_width]:
			       {dest_info_width{1'b0}};
   
   
   ///////////////////////
   //Reservation scheduler   
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

   wire [0:31] grant_time;
   wire [0:31] reservation_schedule_s;
   wire [0:31] reservation_schedule_q;
   //grant time is max(current time , scheduler)
   assign grant_time 		  = reservation_request?
				    ((reservation_schedule_q<current_time_q)?
				     current_time_q:
				     reservation_schedule_q):
				    reservation_schedule_q;
   //next reservaiton time = grant_time + reservation_size or last reservation time
   assign reservation_schedule_s  = reservation_request?
				    grant_time +reservation_size:
				    reservation_schedule_q;
   
   c_dff
     #(// Parameters
       .width				(32),
       .reset_type			(reset_type))
   reservation_scheduler
     (// Outputs
      .q				(reservation_schedule_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(reservation_schedule_s)); 


   //////////////////////////////
     //Grant construction
   wire [0:num_ports-1] grant_route_op;
   rtr_routing_logic
     #(.num_message_classes(1),
       .num_resource_classes(1),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order))
   grant_route_compute
     (.router_address(router_address),
      .sel_mc(1'b1),
      .sel_irc(1'b1),
      .dest_info(reservation_src),
      .route_op( grant_route_op),
      .route_orc());
   wire [0:port_idx_width-1] 			       grant_route_port;
   c_encode
     #(.num_ports(num_ports))
   grant_route_port_enc
     (.data_in(grant_route_op),
      .data_out(grant_route_port));


   
   wire [0:flit_data_width-1] grant_packet_in;
   assign grant_packet_in[0:lar_info_width-1] =  grant_route_port; //lar
   assign grant_packet_in[lar_info_width+:dest_info_width] =  reservation_src;//dest
   assign grant_packet_in[lar_info_width+dest_info_width:header_info_width-1] = 'b0;//psize
   assign grant_packet_in[header_info_width+:2] = 2'b00; //srp_type
   assign grant_packet_in[header_info_width+2:flit_data_width-32-1] = 'b0;//filler
   assign grant_packet_in[flit_data_width-32:flit_data_width-1] = grant_time;//G_ts

   wire [0:flit_data_width-1] grant_packet_out;



   //insert into grant queue   
   wire grant_push = reservation_request; //0 cycle turn around
   wire grant_pop ;
   wire [0:1] grant_errors;
   wire grant_full;
   wire grant_empty;
   wire grant_almost_full;
   wire grant_almost_empty;
   c_fifo
     #(
       // Parameters
       .depth			(num_flits_per_vc),
       .width			(flit_data_width),
       .regfile_type		(`REGFILE_TYPE_FF_2D),
       .reset_type		(reset_type))
   out_grant_fifo
     (// Outputs
      .pop_data			(grant_packet_out),
      .almost_empty		(grant_almost_empty),
      .empty			(grant_empty),
      .almost_full		(grant_almost_full),
      .full			(grant_full),
      .errors			(grant_errors),
      // Inputs
      .clk			(clk),
      .reset			(reset),
      .push_active		(run),
      .pop_active		(run),
      .push			(grant_push),
      .pop			(grant_pop),
      .push_data		(grant_packet_in));



   
   ////////////////////////////
   //injection arbitration
   //Strict priority grant > res > ack/nack > nonspec > spec
   wire[0:4] injection_req;
   wire[0:4] injection_carry;
   wire[0:4] injection_gnt;
   wire[0:3] injection_gnt_ovc;
   
   //these requests NEEDS to be modified significantly, add as we see fit
   assign injection_req[0]    = ~grant_empty;
   assign injection_req[1]    = 1'b0;
   assign injection_req[2]    = 1'b0;
   assign injection_req[3]    = 1'b0;
   assign injection_req[4]    = 1'b0;
   
   assign injection_carry[0:4] = {1'b1, ~injection_req[0:3]&injection_carry[0:3]};
   assign injection_gnt[0:4] = injection_req[0:4]&injection_carry[0:4];
   assign injection_gnt_ovc[0:3] = {injection_gnt[1], 
				    injection_gnt[0]|injection_gnt[2],
				    injection_gnt[3:4]};

   assign grant_pop 	      = injection_gnt[0];
   
   
   wire injection_flit_valid  = |injection_gnt;
   wire injection_flit_head   = injection_gnt[0];
   wire injection_flit_tail   = injection_gnt[0];
   wire [0:flit_data_width-1] injection_flit_data = grant_packet_out;
   
   rtr_channel_output
     #(// Parameters
       .num_vcs(num_vcs),
       .packet_format(packet_format),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   channel_output_stage
     (// Outputs
      .channel_out			(channel_out),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .flit_valid_in			(injection_flit_valid),
      .flit_head_in			(injection_flit_head),
      .flit_tail_in			(injection_flit_tail),
      .flit_data_in			(injection_flit_data[0:flit_data_width-1]),
      .flit_sel_in_ovc			(injection_gnt_ovc));

   
endmodule // test_nic











