//Currently this "NIC" can receive reservation but not reply


module test_nic(/*autoarg*/
   // Outputs
   flow_ctrl, channel_out,
   // Inputs
   clk, reset, run, channel_in
   );
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"

   // select network topology
   parameter topology 		     = `TOPOLOGY_FBFLY;
   // flit buffer entries per VC
   parameter num_flits_per_vc 	     = 8;
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
   localparam num_routers= (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
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

   input [0:channel_width-1] channel_in;
   output [0:flow_ctrl_width-1] flow_ctrl;
   
   output[0:channel_width-1] channel_out;


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
   chi
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
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
   wire [0:num_vcs-1] 		gnt_ivc;
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fco
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .fc_event_valid_in(update),
      .fc_event_sel_in_ivc(gnt_ivc),
      .flow_ctrl_out(flow_ctrl));

   //////////////////////////
   //NIC Receive FIFO
   wire [0:num_vcs-1] 		buffer_push_ivc;
   assign buffer_push_ivc = {num_vcs{flit_valid}} & flit_sel_ivc;
   
   wire [0:num_vcs-1] 		buffer_pop_ivc;
   assign buffer_pop_ivc = {num_vcs{consume}} & gnt_ivc;
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
	   c_fifo_tracker
	     #(.depth(num_flits_per_vc),
	       .reset_type(reset_type))
	   ft
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .push(buffer_push),
	      .pop(buffer_pop),
	      .almost_empty(buffer_almost_empty),
	      .empty(buffer_empty),
	      .almost_full(buffer_almost_full),
	      .full(buffer_full),
	      .free(buffer_free),
	      .errors(buffer_errors));
	   assign buffer_empty_ivc[ivc] = buffer_empty;
	end
   endgenerate

   
   ////////////////////////
   //Reservation request 	
   //Extract reseration request info
   wire reservation_request  = flit_valid&flit_head&(flit_sel_ivc[0]);
   wire [0:reservation_size_width-1] reservation_size = 
				     (reservation_request)?
				     flit_data[(header_info_width+2)+:reservation_size_width]:
				     {reservation_size_width{1'b0}};

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
     (
      // Outputs
      .q				(current_time_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(current_time_s));

   wire [0:31] grant_time;
   wire [0:31] reservation_schedule_s;
   wire [0:31] reservation_schedule_q;
   assign grant_time 		  = reservation_request?
				    ((reservation_schedule_q<current_time_q)?
				     current_time_q:
				     reservation_schedule_q):
				    reservation_schedule_q;
   
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

   //create a grant packet


   //insert into grant queue





   
   ////////////////////////////
   //output arbitration
   
endmodule // test_nic











