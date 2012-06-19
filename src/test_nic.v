/*
 *Currently this "NIC" 
 * Hard coded for 4 VCs
 * can receive reservation and reply with a grant
 * injection fifo, 
 * ejection fifo, ejection arbitration and ejection flow control
 */         

module test_nic(/*autoarg*/
		// Outputs
		channel_inject, flow_ctrl_eject, host_next_flit, buffer_empty,
		error,
		// Inputs
		clk, reset, run, source_address, channel_eject, flow_ctrl_inject,
		message_ready, message_size, message_dest, host_data_valid,
		host_data_head, host_data_tail, host_data
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
   // number of routers in each dimfbension
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
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + num_vcs) :
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
   parameter dim_order 		      = `DIM_ORDER_ASCENDING;
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask 		      = `ELIG_MASK_NONE;
   // maximum packet length (in flits)
   localparam max_packet_length       = 1 + max_payload_length;
   // total number of bits required to represent maximum packet length
   localparam packet_length_width     = clogb(max_packet_length);

   
   parameter max_reservation_size     = 16; //packets
   localparam reservation_size_width  = clogb(max_reservation_size);
   parameter time_to_wait_width       = 8;
   parameter spec_buffer_capacity     = 4;
   localparam spec_buffer_width       = clogb(spec_buffer_capacity);   
   parameter reset_type 	      = `RESET_TYPE_ASYNC;
   
   //SRP packet related
`include "srp_format.v"
   
   
   //default inputs
   input clk;
   input reset;
   input run;
   input [0:dest_info_width-1] source_address;      
   wire [0:router_addr_width-1] router_address=source_address[0:router_addr_width-1];

   
   //network side
   input [0:channel_width-1] channel_eject;
   output[0:channel_width-1] channel_inject;
   output [0:flow_ctrl_width-1] flow_ctrl_eject;
   input [0:flow_ctrl_width-1] flow_ctrl_inject;   


   
   //host side
   input message_ready; 
   input [0:reservation_size_width-1] message_size; //messages cannot be > reservation size
   input [0:dest_info_width-1] message_dest;
   input host_data_valid;
   input host_data_head;
   input host_data_tail;
   input [0:flit_data_width-1] host_data;
   output host_next_flit; //get a new flit on the next cycle
   output buffer_empty; //allows the message generator to select this buffer

   
   output error;
   
   //////////////////////////////
   //channel input from the router
   wire 			flit_valid_eject;
   wire 			flit_head_eject;
   wire [0:num_vcs-1] 		flit_head_eject_ivc;
   wire 			flit_tail_eject;
   wire [0:num_vcs-1] 		flit_tail_eject_ivc;
   wire [0:flit_data_width-1] 	flit_data_eject;
   wire [0:num_vcs-1] 		flit_eject_sel_ivc;
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
      .channel_in(channel_eject),
      .flit_valid_out(flit_valid_eject),
      .flit_head_out(flit_head_eject),
      .flit_head_out_ivc(flit_head_eject_ivc),
      .flit_tail_out(flit_tail_eject),
      .flit_tail_out_ivc(flit_tail_eject_ivc),
      .flit_data_out(flit_data_eject),
      .flit_sel_out_ivc(flit_eject_sel_ivc));


   wire [0:31] current_time_s;
   wire [0:31] current_time_q;
   assign current_time_s = current_time_q+'b1;   
   c_dff
     #(// Parameters
       .width				(32),
       .reset_type			(reset_type))
   nic_timer
     (// Outputs
      .q				(current_time_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(current_time_s));

   //ejection port Flow control, easy
   //credit reply based which vc was processed
   wire [0:num_vcs-1] 		ejection_gnt_ivc;
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   channel_eject_fc
     (.clk(clk),
      .reset(reset),
      .active(run),
      .fc_event_valid_in(|ejection_gnt_ivc),
      .fc_event_sel_in_ivc(ejection_gnt_ivc),
      .flow_ctrl_out(flow_ctrl_eject));

   //Injection flow control ~ hard,
   //mimic vcr_ovc_ctrl
   wire inject_fc_active;
   wire [0:num_vcs-1] inject_credit;
   wire [0:num_vcs-1] inject_debit;
   wire [0:num_vcs-1] inject_elig;
   
   rtr_flow_ctrl_input
     #(// Parameters
       .num_vcs				(num_vcs),
       .flow_ctrl_type			(flow_ctrl_type),
       .reset_type			(reset_type))
   channel_inject_fc
     (// Outputs
      .fc_event_valid_out		(inject_fc_active),
      .fc_event_sel_out_ovc		(inject_credit),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .flow_ctrl_in			(flow_ctrl_inject));
   
   wire [0:num_vcs-1] inject_fc_error;
   
   generate
      genvar ivc_fc;
      for(ivc_fc=0; ivc_fc<num_vcs;ivc_fc=ivc_fc+1)
	begin:ivc_fcs
	   wire full;
	   wire [0:1] errors;
	   
	   c_fifo_tracker
	     #(// Parameters
	       .depth(num_flits_per_vc),
	       .reset_type		(reset_type))
	   inj_credit_counter
	     (// Outputs
	      .almost_empty		(),
	      .empty		(),
	      .almost_full		(),
	      .full			(full),
	      .free			(),
	      .errors		(errors),
	      // Inputs
	      .clk			(clk),
	      .reset		(reset),
	      .active		(1'b1),
	      .push			((|inject_debit)?inject_debit[ivc_fc]:1'b0),
	      .pop			(inject_fc_active?inject_credit[ivc_fc]:1'b0));
	   assign inject_elig[ivc_fc]  = ~full;
	   assign inject_fc_error      = |errors;
	end
   endgenerate
   
   //////////////////////////
	       //NIC Receive FIFO
   //  65 wide fifo, flit_data + is_flit_head
   wire [0:num_vcs-1] 		fifo_push_ivc;
   assign fifo_push_ivc = {num_vcs{flit_valid_eject}} & flit_eject_sel_ivc;
   wire [0:num_vcs-1] 		fifo_pop_ivc;
   assign fifo_pop_ivc  = ejection_gnt_ivc;
   wire [0:num_vcs*(flit_data_width+1)-1] eject_fifo_data;
   wire [0:num_vcs*2-1] eject_fifo_error;
   wire [0:num_vcs-1] eject_fifo_empty;
   
   generate
      genvar 		    ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   wire fifo_push;
	   assign fifo_push = fifo_push_ivc[ivc];
	   wire fifo_pop;
	   assign fifo_pop = fifo_pop_ivc[ivc];
	   wire 			    fifo_almost_empty;
	   wire 			    fifo_empty;
	   wire 			    fifo_almost_full;
	   wire 			    fifo_full;
	   wire [0:flit_count_width-1] 	    fifo_free;
	   wire [0:1] 			    fifo_errors;
	   wire [0:flit_data_width+1-1] fifo_pop_data;
	   c_fifo
	     #(
	       // Parameters
	       .depth			(num_flits_per_vc),
	       .width			(flit_data_width+1),
	       .regfile_type		(`REGFILE_TYPE_FF_2D),
	       .reset_type		(reset_type))
	   eject_fifo
	     (// Outputs
	      .pop_data			(fifo_pop_data),
	      .almost_empty		(fifo_almost_empty),
	      .empty			(fifo_empty),
	      .almost_full		(fifo_almost_full),
	      .full			(fifo_full),
	      .errors			(fifo_errors),
	      // Inputs
	      .clk			(clk),
	      .reset			(reset),
	      .push_active		(run),
	      .pop_active		(run),
	      .push			(fifo_push),
	      .pop			(fifo_pop),
	      .push_data		({flit_data_eject,flit_head_eject}));
	   assign eject_fifo_data[ivc*(flit_data_width+1)+:(flit_data_width+1)]
 	     =fifo_pop_data;
	   assign eject_fifo_error[ivc*2+:2] = fifo_errors;
	   assign eject_fifo_empty[ivc]  = fifo_empty;
	end
   endgenerate

   
   //////////////////////
	       //Ejection arbitration
   //Strict priority grant > res > ack/nack > nonspec > spec
   wire[0:4] ejection_req;
   wire[0:4] ejection_carry;
   wire[0:4] ejection_gnt;
   wire  is_ack;
   //these requests NEEDS to be modified significantly, add as we see fit
   assign ejection_req[0]  = ~eject_fifo_empty[1] &  //Grant VC
			     ~(|eject_fifo_data[(flit_data_width+1)+header_info_width+:2]); //SRP_TYPE == 00
   assign ejection_req[1] = ~eject_fifo_empty[0] & //Reservation VC{testbench.thebuffer.spec_packet[0:63]}
			    ~grant_almost_full;    //Grant output fifo flow control
   assign ejection_req[2] = ~eject_fifo_empty[1] &  //ack/nack
			    (|eject_fifo_data[(flit_data_width+1)+header_info_width+:2]);
   assign is_ack 	   = (eject_fifo_data[(flit_data_width+1)+header_info_width+:2] ==2'b01);
   assign ejection_req[3]  = ~eject_fifo_empty[2];  //nonspec
   assign ejection_req[4]  = ~eject_fifo_empty[3] &  //spec
			     (~ack_almost_full | ~eject_fifo_data[4*(flit_data_width+1)-1]); //ack output fifo flow control

   //fix priority aribitration
   assign ejection_carry[0:4] = {1'b1, ~ejection_req[0:3]&ejection_carry[0:3]};
   assign ejection_gnt[0:4] = ejection_req[0:4]&ejection_carry[0:4];
   assign ejection_gnt_ivc[0:3] = {ejection_gnt[1], 
				   ejection_gnt[0]|ejection_gnt[2],
				   ejection_gnt[3:4]};

   //signals for internal ejection processing
   wire ejection_valid 	= |ejection_gnt_ivc;
   wire ejection_head 	= |{ejection_gnt_ivc &
			    {eject_fifo_data[1*(flit_data_width+1)-1],
			     eject_fifo_data[2*(flit_data_width+1)-1],
			     eject_fifo_data[3*(flit_data_width+1)-1],
			     eject_fifo_data[4*(flit_data_width+1)-1]}};
   
   wire fb_gnt_rdy  = ejection_gnt_ivc[1]&ejection_req[0];
   wire fb_ack_rdy  = ejection_gnt_ivc[1]&ejection_req[2]& is_ack;
   wire fb_nack_rdy  = ejection_gnt_ivc[1]&ejection_req[2]&~is_ack;
   
   
   wire fb_gnt; //assigned in injection arbitration

   
   
   ////////////////////////
   //Reservation request 	
   //extract reservaiton info
   wire reservation_request  = ejection_valid&ejection_head&(ejection_gnt_ivc[0]);
   wire [0:flit_data_width-1] reservation_data  = eject_fifo_data[0:flit_data_width-1];
   wire [0:reservation_size_width+packet_length_width-1] reservation_size = 
							 (reservation_request)?
							 {reservation_data[res_size_start +:reservation_size_width], {packet_length_width{1'b0}}}:
							 {{reservation_size_width{1'b0}},{packet_length_width{1'b0}}};
   wire [0:dest_info_width-1] reservation_src = (reservation_request)?
			      reservation_data[res_src_start+:dest_info_width]:
			      {dest_info_width{1'b0}};
   
   
   ///////////////////////
   //Reservation scheduler   
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
   wire [0:flit_data_width-1] grant_packet_out;
   wire [0:payload_length_width-1] grant_payload_size = {payload_length_width{1'b0}};
   
   assign grant_packet_in[0:flit_data_width-1] = {grant_route_port,
						  reservation_src,
						  grant_payload_size,
						  2'b00,
						  {(grant_time_start-grant_data_start){1'b0}},
						  grant_time
						  };


   //insert into grant fifo
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




   //////////////////////////////
     //Spec and Ack handling
   //Only head generate ack, extract reply src
   wire speculative_request  = ejection_valid&ejection_head&(ejection_gnt_ivc[3]);
   wire [0:flit_data_width-1] speculative_data  = eject_fifo_data[3*(flit_data_width+1)+:flit_data_width];
   wire [0:dest_info_width-1] speculative_src = (speculative_request)?
			      speculative_data[spec_src_start+:dest_info_width]:
			      {dest_info_width{1'b0}};
   wire [0:spec_buffer_width-1] speculative_id  = speculative_data[spec_id_start+:spec_buffer_width];
   
   wire [0:num_ports-1] ack_route_op;
   rtr_routing_logic
     #(.num_message_classes(1),
       .num_resource_classes(1),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order))
   ack_route_compute
     (.router_address(router_address),
      .sel_mc(1'b1),
      .sel_irc(1'b1),
      .dest_info(speculative_src),
      .route_op( ack_route_op),
      .route_orc());
   wire [0:port_idx_width-1] 			       ack_route_port;
   c_encode
     #(.num_ports(num_ports))
   ack_route_port_enc
     (.data_in(ack_route_op),
      .data_out(ack_route_port));
   
   wire [0:flit_data_width-1] ack_packet_in;
   wire [0:flit_data_width-1] ack_packet_out;
   wire [0:payload_length_width-1] ack_payload_size = {payload_length_width{1'b0}};
   assign ack_packet_in[0:ack_data_start-1] = {ack_route_port,
					       speculative_src,
					       ack_payload_size,
					       2'b01,
					       speculative_id};
   assign ack_packet_in[ack_data_start:flit_data_width-1] = 'b0;//filler

   //insert into ack fifo   
   wire ack_push = speculative_request; //0 cycle turn around
   wire ack_pop ;
   wire [0:1] ack_errors;
   wire ack_full;
   wire ack_empty;
   wire ack_almost_full;
   wire ack_almost_empty;
   c_fifo
     #(
       // Parameters
       .depth			(num_flits_per_vc),
       .width			(flit_data_width),
       .regfile_type		(`REGFILE_TYPE_FF_2D),
       .reset_type		(reset_type))
   out_ack_fifo
     (// Outputs
      .pop_data			(ack_packet_out),
      .almost_empty		(ack_almost_empty),
      .empty			(ack_empty),
      .almost_full		(ack_almost_full),
      .full			(ack_full),
      .errors			(ack_errors),
      // Inputs
      .clk			(clk),
      .reset			(reset),
      .push_active		(run),
      .pop_active		(run),
      .push			(ack_push),
      .pop			(ack_pop),
      .push_data		(ack_packet_in));


   //////////////////////////////
     //Flow buffer!
   
   wire fb_res_rdy;
   wire fb_nonspec_rdy;
   wire fb_spec_rdy;
   wire [0:flit_data_width-1] fb_output_data;
   wire [0:flit_data_width-1] fb_input_data  
			      = eject_fifo_data[1*(flit_data_width+1)+:flit_data_width];
   wire fb_output_head;
   wire fb_output_tail;

   wire fb_error;
   
   
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
       .spec_buffer_capacity		(spec_buffer_capacity),
       .time_to_wait_width		(time_to_wait_width),
       .max_reservation_size		(max_reservation_size),
       .reset_type			(reset_type))
   source_queue
     (// Outputs
      .host_next_flit			(host_next_flit),
      .buffer_empty			(buffer_empty), 
      .reservation_ready		(fb_res_rdy),
      .nonspec_ready			(fb_nonspec_rdy),
      .spec_ready			(fb_spec_rdy),
      .output_data			(fb_output_data),
      .output_head			(fb_output_head),
      .output_tail			(fb_output_tail),
      .error				(fb_error),
      // Inputs
      .clk				(clk),
      .run				(run),
      .reset				(reset),
      .source_address			(source_address),
      //generated outside to nic to buffer
      .message_ready			(message_ready),
      .message_size			(message_size),
      .message_dest			(message_dest),
      .host_data_valid			(host_data_valid),
      .host_data_head			(host_data_head),
      .host_data_tail			(host_data_tail),
      .host_data			(host_data),
      //generated by nic
      .grant_ready			(fb_gnt_rdy),
      .ack_ready			(fb_ack_rdy),
      .nack_ready			(fb_nack_rdy),
      .nic_data				(fb_input_data),
      .current_time			(current_time_q),
      .nic_gnt				(fb_gnt));
   
   
   
   ////////////////////////////
     //injection arbitration
   //Strict priority grant > res > ack/nack > nonspec > spec
   wire[0:4] injection_req;
   wire[0:4] injection_carry;
   wire[0:3] injection_gnt_ovc;
   wire[0:4] injection_gnt;
   
   //these requests NEEDS to be modified significantly, especially flow control
   assign injection_req[0]  = ~grant_empty& inject_elig[1];
   assign injection_req[1]  = fb_res_rdy & inject_elig[0];
   assign injection_req[2]  = ~ack_empty& inject_elig[1];
   assign injection_req[3]  = fb_nonspec_rdy& inject_elig[2];
   assign injection_req[4]  = fb_spec_rdy& inject_elig[3];
   
   assign injection_carry[0:4] = {1'b1, ~injection_req[0:3]&injection_carry[0:3]};
   assign injection_gnt[0:4] = injection_req[0:4]&injection_carry[0:4];
   assign injection_gnt_ovc[0:3] = {injection_gnt[1], 
				    injection_gnt[0]|injection_gnt[2],
				    injection_gnt[3:4]};

   assign inject_debit 	      = injection_gnt_ovc;
   
   assign grant_pop 	      = injection_gnt[0];
   assign ack_pop 	      = injection_gnt[2];
   assign fb_gnt 	      = injection_gnt[1]|injection_gnt[3]|injection_gnt[4];
   

   //Send them out
   //For now, both gnt and ack are single flit packets
   wire injection_flit_valid  = |injection_gnt;
   wire injection_flit_head;
   wire injection_flit_tail;
   wire [0:flit_data_width-1] injection_flit_data;

   c_select_1ofn
     #(// Parameters
       .num_ports			(3),
       .width				(flit_data_width+1+1))
   injection_mux
     (// Outputs
      .data_out				({injection_flit_head,
					  injection_flit_tail,
					  injection_flit_data}),
      // Inputs
      .select				({grant_pop, ack_pop, fb_gnt}),
      .data_in				({{injection_gnt[0],injection_gnt[0],grant_packet_out},
					  {injection_gnt[2], injection_gnt[2], ack_packet_out}, 
					  {fb_output_head, fb_output_tail, fb_output_data}}));
   
   rtr_channel_output
     #(// Parameters
       .num_vcs(num_vcs),
       .packet_format(packet_format),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   channel_output_stage
     (// Outputs
      .channel_out			(channel_inject),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .flit_valid_in			(injection_flit_valid),
      .flit_head_in			(injection_flit_head),
      .flit_tail_in			(injection_flit_tail),
      .flit_data_in			(injection_flit_data[0:flit_data_width-1]),
      .flit_sel_in_ovc			(injection_gnt_ovc));


  
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	if(|eject_fifo_error)
	  $display("NIC ERROR: Eject fifo problem %m");
	if(|grant_errors)
	  $display("NIC ERROR: Grant fifo error %m");
	if(|ack_errors)
	  $display("NIC ERROR: Ack fifo error %m");
	if(|inject_fc_error)
	  $display("NIC ERROR: Flow control from injection error %m");
     end
    // synopsys translate_on

   
   assign error  = (|eject_fifo_error) | (|grant_errors) | (|ack_errors) |(|inject_fc_error)|fb_error; 
endmodule // test_nic











