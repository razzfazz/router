// $Id$

/*
 Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

//==============================================================================
// input VC controller
//==============================================================================

module vcr_ivc_ctrl
  (clk, reset, router_address, flit_valid_in, flit_head_in, flit_tail_in, 
   header_info_in, int_flow_ctrl_op_ovc, route_op, route_orc, vc_gnt, 
   vc_gnt_ocvc, sw_gnt, flit_sent_prev, peek_header_info, peek_flit_head, 
   peek_flit_tail, flit_valid, flit_head, flit_tail, flit_sel_ovc, 
   header_info, fb_almost_empty, fb_empty, allocated, free_nonspec, free_spec,
   errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width of credit hold register
   // (note: this parameter is only used for INT_FLOW_CTRL_TYPE_PUSH)
   localparam cred_hold_width = clogb(num_flits_per_vc);
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // width required to select individual resource class
   localparam resource_class_idx_width = clogb(num_resource_classes);
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs available for each class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
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
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length = 4;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length = 1;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // width required for lookahead routing information
   localparam la_route_info_width = port_idx_width + resource_class_idx_width;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_LEVEL) ? 2 :
       (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_PUSH) ? 1 :
       -1;
   
   // select whether VCs must have credits available in order to be considered 
   // for VC allocation
   parameter vc_alloc_requires_credit = 0;
   
   // enable speculative switch allocation
   parameter sw_alloc_spec = 1;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   // message class to which this VC belongs
   localparam message_class
     = (vc_id / (num_resource_classes*num_vcs_per_class)) % num_message_classes;
   
   // resource class to which this VC belongs
   localparam resource_class
     = (vc_id / num_vcs_per_class) % num_resource_classes;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming flit valid
   input			 flit_valid_in;
   
   // incoming flit is head flit
   input 			 flit_head_in;
   
   // incoming flit is tail
   input 			 flit_tail_in;
   
   // header info for incoming flit
   input [0:header_info_width-1] header_info_in;
   
   // internal flow control signalling from output controller to input 
   // controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   // destination port (1-hot)
   output [0:num_ports-1] 			     route_op;
   wire [0:num_ports-1] 			     route_op;
   
   // select next resource class
   output [0:num_resource_classes-1] 		     route_orc;
   wire [0:num_resource_classes-1] 		     route_orc;
   
   // VC allocation successful
   input 					     vc_gnt;
   
   // granted output VC
   input [0:num_vcs_per_class-1] 		     vc_gnt_ocvc;
   
   // switch allocator grants
   input 					     sw_gnt;
   
   // did this VC send a flit in the previous cycle?
   input 					     flit_sent_prev;
   
   // header info for next flit in buffer
   input [0:header_info_width-1] 		     peek_header_info;

   // head bit for next flit in buffer
   input 					     peek_flit_head;

   // tail bit for next flit in buffer
   input 					     peek_flit_tail;
   
   // outgoing flit is available
   output 					     flit_valid;
   wire 					     flit_valid;
   
   // outgoing flit is head flit
   output 					     flit_head;
   wire 					     flit_head;
   
   // outgoing flit is tail flit
   output 					     flit_tail;
   wire 					     flit_tail;
   
   // destination VC for outgoing flit
   output [0:num_vcs-1] 			     flit_sel_ovc;
   wire [0:num_vcs-1] 				     flit_sel_ovc;
   
   // updated lookahead routing information for outgoind head flit
   output [0:header_info_width-1] 		     header_info;
   wire [0:header_info_width-1] 		     header_info;
   
   // flit buffer has only a single valid entry
   input 					     fb_almost_empty;
   
   // flit buffer does not have any valid entries
   input 					     fb_empty;
   
   // has an output VC been assigned to this input VC?
   output 					     allocated;
   wire 					     allocated;
   
   // credit availability if VC has been assigned
   output 					     free_nonspec;
   wire 					     free_nonspec;
   
   // credit availability if no VC has been assigned yet
   output 					     free_spec;
   wire 					     free_spec;
   
   // internal error condition detected
   output [0:3] 				     errors;
   wire [0:3] 					     errors;
   
   
   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   
   assign flit_valid = flit_valid_in | ~fb_empty;
   
   wire 					     pop_active;
   assign pop_active = flit_valid;
   
   wire 					     flit_sent;
   
   wire 					     packet_done;
   assign packet_done = flit_sent & flit_tail;
   
   wire 					     vc_allocated_s, 
						     vc_allocated_q;
   assign vc_allocated_s = (vc_allocated_q | vc_gnt) & ~packet_done;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocatedq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(vc_allocated_s),
      .q(vc_allocated_q));
   
   assign allocated = vc_allocated_q;
   
   wire [0:num_vcs_per_class-1] 		     vc_allocated_ocvc;
   wire [0:num_vcs_per_class-1] 		     vc_allocated_next_ocvc;
   wire [0:num_vcs_per_class-1] 		     allocated_ocvc;
   
   generate
      
      if(num_vcs_per_class == 1)
	begin
	   assign vc_allocated_next_ocvc = 1'b1;
	   assign vc_allocated_ocvc = 1'b1;
	end
      if(num_vcs_per_class > 1)
	begin
	   
	   assign vc_allocated_next_ocvc
	     = vc_allocated_q ? vc_allocated_ocvc : vc_gnt_ocvc;
	   
	   wire [0:num_vcs_per_class-1] vc_allocated_ocvc_s;
	   wire [0:num_vcs_per_class-1] vc_allocated_ocvc_q;
	   assign vc_allocated_ocvc_s = vc_allocated_next_ocvc;
	   c_dff
	     #(.width(num_vcs_per_class),
	       .reset_type(reset_type))
	   vc_allocated_ocvcq
	     (.clk(clk),
	      .reset(reset),
	      .active(pop_active),
	      .d(vc_allocated_ocvc_s),
	      .q(vc_allocated_ocvc_q));
	   
	   assign vc_allocated_ocvc = vc_allocated_ocvc_q;
	   
	end
      
      if(sw_alloc_spec)
	begin
	   if(vc_alloc_requires_credit)
	     assign flit_sent = sw_gnt & (vc_gnt | vc_allocated_q);
	   else
	     assign flit_sent
	       = sw_gnt & ((vc_gnt & free_spec) | vc_allocated_q);
	   
	   assign allocated_ocvc = vc_allocated_next_ocvc;
	end
      else
	begin
	   assign flit_sent = sw_gnt;
	   
	   assign allocated_ocvc = vc_allocated_ocvc;
	end
      
   endgenerate
   
   wire [0:num_resource_classes*num_vcs_per_class-1] allocated_orc_ocvc;
   c_mat_mult
     #(.dim1_width(num_resource_classes),
       .dim2_width(1),
       .dim3_width(num_vcs_per_class),
       .prod_op(`BINARY_OP_AND),
       .sum_op(`BINARY_OP_OR))
   allocated_orc_ocvc_mmult
     (.input_a(route_orc),
      .input_b(allocated_ocvc),
      .result(allocated_orc_ocvc));
   
   wire [0:num_vcs-1] allocated_ovc;
   c_align
     #(.in_width(num_resource_classes*num_vcs_per_class),
       .out_width(num_vcs),
       .offset(message_class*num_resource_classes*num_vcs_per_class))
   allocated_ovc_alg
     (.data_in(allocated_orc_ocvc),
      .dest_in({num_vcs{1'b0}}),
      .data_out(allocated_ovc));
   
   assign flit_sel_ovc = allocated_ovc;
   
   
   //---------------------------------------------------------------------------
   // generate head and tail indicators
   //---------------------------------------------------------------------------
   
   wire 	      htr_flit_head_s, htr_flit_head_q;
   assign htr_flit_head_s = flit_sent ?
			    (fb_almost_empty ? flit_head_in : peek_flit_head) :
			    (fb_empty ? flit_head_in : htr_flit_head_q);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   htr_flit_headq
     (.clk(clk),
      .reset(1'b0),
      .active(pop_active),
      .d(htr_flit_head_s),
      .q(htr_flit_head_q));
   
   assign flit_head = fb_empty ? flit_head_in : htr_flit_head_q;
   
   wire 	      htr_flit_tail_s, htr_flit_tail_q;
   assign htr_flit_tail_s = flit_sent ?
			    (fb_almost_empty ? flit_tail_in : peek_flit_tail) :
			    (fb_empty ? flit_tail_in : htr_flit_tail_q);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   htr_flit_tailq
     (.clk(clk),
      .reset(1'b0),
      .active(pop_active),
      .d(htr_flit_tail_s),
      .q(htr_flit_tail_q));
   
   assign flit_tail = fb_empty ? flit_tail_in : htr_flit_tail_q;
   
   
   //---------------------------------------------------------------------------
   // head register
   //---------------------------------------------------------------------------
   
   wire 			     bypass_peek;
   assign bypass_peek = fb_empty | fb_almost_empty;
   
   wire 			     hdr_valid_s, hdr_valid_q;
   assign hdr_valid_s
     = flit_sent ?
       (fb_empty ? 
	~flit_tail_in : 
	(~htr_flit_tail_q | ~fb_almost_empty | flit_valid_in)) : 
       (hdr_valid_q | flit_valid_in);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   hdf_validq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(hdr_valid_s),
      .q(hdr_valid_q));
   
   wire [0:header_info_width-1]      header_info_in;
   assign header_info_in = flit_data_in[0:header_info_width-1];
   
   wire [0:la_route_info_width-1]    la_route_info_in;
   assign la_route_info_in = header_info_in[0:la_route_info_width-1];
   
   wire [0:route_info_width-1] 	     route_info_in;
   assign route_info_in
     = header_info_in[la_route_info_width:
		      la_route_info_width+route_info_width-1];
   
   wire 			     hdr_active;
   assign hdr_active = ~hdr_valid_q | (~fb_empty & htr_flit_tail_q);
   
   wire [0:la_route_info_width-1]    la_route_info_in;
   assign la_route_info_in = header_info_in[0:la_route_info_width-1];
   
   wire [0:la_route_info_width-1]    peek_la_route_info;
   assign peek_la_route_info = peek_header_info[0:la_route_info_width-1];
   
   wire [0:la_route_info_width-1]    hdr_la_route_info_s, hdr_la_route_info_q;
   assign hdr_la_route_info_s
     = (flit_sent & flit_tail) ? 
       (fb_almost_empty ? la_route_info_in : peek_la_route_info) : 
       (hdr_valid_q ? hdr_la_route_info_q : la_route_info_in);
   c_dff
     #(.width(la_route_info_width),
       .reset_type(reset_type))
   hdr_la_route_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_la_route_info_s),
      .q(hdr_la_route_info_q));
   
   wire [0:route_info_width-1] 	     route_info_in;
   assign route_info_in
     = header_info_in[la_route_info_width:
		      la_route_info_width+route_info_width-1];
   
   wire [0:route_info_width-1] 	     peek_route_info;
   assign peek_route_info
     = peek_header_info[la_route_info_width:
			la_route_info_width+route_info_width-1];
   
   wire [0:route_info_width-1] 	     hdr_route_info_s, hdr_route_info_q;
   assign hdr_route_info_s
     = (flit_sent & flit_tail) ?
       (fb_almost_empty ? route_info_in : peek_route_info) :
       (hdr_valid_q ? hdr_route_info_q : route_info_in);
   c_dff
     #(.width(route_info_width),
       .reset_type(reset_type))
   hdr_route_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_route_info_s),
      .q(hdr_route_info_q));
   
   wire 			     error_no_header;
   assign error_no_header
     = ~hdr_valid_q & (~fb_empty | (flit_valid_in & ~flit_head_in));
   
   
   //---------------------------------------------------------------------------
   // decode lookahead routing information
   //---------------------------------------------------------------------------
   
   wire [0:port_idx_width-1] 	     route_port_in;
   assign route_port_in = la_route_info_in[0:port_idx_width-1];
   
   wire [0:num_ports-1] 	     route_in_op;
   c_decode
     #(.num_ports(num_ports))
   route_in_op_dec
     (.data_in(route_port_in),
      .data_out(route_in_op));
   
   wire [0:port_idx_width-1] 	     hdr_route_port;
   assign hdr_route_port = hdr_la_route_info_q[0:port_idx_width-1];
   
   wire [0:num_ports-1] 	     hdr_route_op;
   c_decode
     #(.num_ports(num_ports))
   hdr_route_op_dec
     (.data_in(hdr_route_port),
      .data_out(hdr_route_op));
   
   wire [0:num_ports-1] 	     route_unmasked_op;
   assign route_unmasked_op = hdr_valid_q ? hdr_route_op : route_in_op;
   
   wire [0:num_resource_classes-1]   route_unmasked_orc;
   
   generate
      
      if(num_resource_classes == 1)
	assign route_unmasked_orc = 1'b1;
      else if(num_resource_classes > 1)
	begin
	   
	   wire [0:resource_class_idx_width-1] route_rcsel_in;
	   assign route_rcsel_in
	     = la_route_info_in[port_idx_width:
				port_idx_width+resource_class_idx_width-1];
	   
	   wire [0:num_resource_classes-1]     route_in_orc;
	   c_decode
	     #(.num_ports(num_resource_classes))
	   route_in_orc_dec
	     (.data_in(route_rcsel_in),
	      .data_out(route_in_orc));
	   
	   wire [0:resource_class_idx_width-1] hdr_route_rcsel;
	   assign hdr_route_rcsel
	     = hdr_la_route_info_q[port_idx_width:
				   port_idx_width+resource_class_idx_width-1];
	   
	   wire [0:num_resource_classes-1]     hdr_route_orc;
	   c_decode
	     #(.num_ports(num_resource_classes))
	   hdr_route_orc_dec
	     (.data_in(hdr_route_rcsel),
	      .data_out(hdr_route_orc));
	   
	   assign route_unmasked_orc
	     = hdr_valid_q ? hdr_route_orc : route_in_orc;
	   
	end
      
   endgenerate
   
   wire 				       header_valid;
   assign header_valid = hdr_valid_q | flit_valid_in;
   
   wire 				       rf_active;
   assign rf_active = header_valid;
   
   wire [0:1] 				       rf_errors;
   rtr_route_filter
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .num_nodes_per_router(num_nodes_per_router),
       .restrict_turns(restrict_turns),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .port_id(port_id),
       .vc_id(vc_id))
   rf
     (.clk(clk),
      .reset(reset),
      .active(rf_active),
      .route_valid(header_valid),
      .route_in_op(route_unmasked_op),
      .route_in_orc(route_unmasked_orc),
      .route_out_op(route_op),
      .route_out_orc(route_orc),
      .errors(rf_errors));
   
   wire 				       error_invalid_port;
   assign error_invalid_port = rf_errors[0];
   
   wire 				       error_invalid_class;
   assign error_invalid_class = rf_errors[1];
   
   
   //---------------------------------------------------------------------------
   // update lookahead routing information for next hop
   //---------------------------------------------------------------------------
   
   wire [0:la_route_info_width-1] 	       la_route_info;
   assign la_route_info = hdr_valid_q ? hdr_la_route_info_q : la_route_info_in;
   
   assign header_info[0:la_route_info_width-1] = la_route_info;

   wire [0:route_info_width-1] 		       route_info;
   assign route_info = hdr_valid_q ? hdr_route_info_q : route_info_in;
   
   assign header_info[la_route_info_width:
		      la_route_info_width+route_info_width-1] = route_info;
   
   wire [0:router_addr_width-1] 	       next_router_address;
   rtr_next_hop_addr
     #(.num_resource_classes(num_resource_classes),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type))
   nha
     (.router_address(router_address),
      .route_info(route_info),
      .la_route_info(la_route_info),
      .next_router_address(next_router_address));
   
   wire [0:num_message_classes-1] 	       sel_mc;
   c_align
     #(.in_width(1),
       .out_width(num_message_classes),
       .offset(message_class))
   sel_mc_agn
     (.data_in(1'b1),
      .dest_in({num_message_classes{1'b0}}),
      .data_out(sel_mc));
   
   wire [0:num_ports-1] 		       next_route_op;
   wire [0:num_resource_classes-1] 	       next_route_orc;
   rtr_routing_logic
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order))
   rtl
     (.router_address(next_router_address),
      .sel_mc(sel_mc),
      .sel_irc(route_orc),
      .route_info(route_info),
      .route_op(next_route_op),
      .route_orc(next_route_orc));
   
   wire [0:port_idx_width-1] 		       next_route_port;
   c_encode
     #(.num_ports(num_ports))
   next_route_port_enc
     (.data_in(next_route_op),
      .data_out(next_route_port));
   
   assign la_route_info[0:port_idx_width-1] = next_route_port;
   
   generate
      
      if(num_resource_classes > 1)
	begin
	   
	   wire [0:resource_class_idx_width-1] next_route_rcsel;
	   c_encode
	     #(.num_ports(num_resource_classes))
	   next_route_rcsel_enc
	     (.data_in(next_route_orc),
	      .data_out(next_route_rcsel));
	   
	   assign la_route_info[port_idx_width:
				port_idx_width+resource_class_idx_width-1]
	     = next_route_rcsel;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // credit tracking
   //---------------------------------------------------------------------------
   
   wire 				   cred_track_active;
   assign cred_track_active = flit_valid | vc_allocated_q;
   
   wire [0:num_vcs*int_flow_ctrl_width-1]  int_flow_ctrl_ovc;
   c_select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs*int_flow_ctrl_width))
   int_flow_ctrl_ovc_sel
     (.select(route_op),
      .data_in(int_flow_ctrl_op_ovc),
      .data_out(int_flow_ctrl_ovc));
   
   wire [0:num_resource_classes*num_vcs_per_class*
	 int_flow_ctrl_width-1] 	   int_flow_ctrl_orc_ocvc;
   assign int_flow_ctrl_orc_ocvc = int_flow_ctrl_ovc[message_class*
						     num_resource_classes*
						     num_vcs_per_class*
						     int_flow_ctrl_width:
						     (message_class+1)*
						     num_resource_classes*
						     num_vcs_per_class*
						     int_flow_ctrl_width-1];
   
   wire [0:num_vcs_per_class*int_flow_ctrl_width-1] int_flow_ctrl_ocvc;
   wire 					    error_ct_overflow;
   
   generate
      
      if(num_resource_classes == 1)
	assign int_flow_ctrl_ocvc = int_flow_ctrl_orc_ocvc;
      else if(num_resource_classes > 1)
	begin
	   c_select_1ofn
	     #(.num_ports(num_resource_classes),
	       .width(num_vcs_per_class*int_flow_ctrl_width))
	   int_flow_ctrl_ocvc_sel
	     (.select(route_orc),
	      .data_in(int_flow_ctrl_orc_ocvc),
	      .data_out(int_flow_ctrl_ocvc));
	end
      
      case(int_flow_ctrl_type)
	
	// the current number of credits available are transmitted from the 
	// output controllers as a multi-level signal (0, 1, 2 or 3+ credits
	// currently available)
	`INT_FLOW_CTRL_TYPE_LEVEL:
	  begin
	     
	     wire [0:num_vcs_per_class-1]   next_free_ocvc;
	     wire [0:num_vcs_per_class-1]   free_spec_ocvc;
	     
	     genvar 			    ocvc;
	     
	     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
	       begin:ocvcs
		  
		  wire [0:1] int_flow_ctrl;
		  assign int_flow_ctrl
		    = int_flow_ctrl_ocvc[ocvc*2:(ocvc+1)*2-1];
		  
		  wire 	     two_or_more_credits;
		  assign two_or_more_credits
		    = int_flow_ctrl[0] & (int_flow_ctrl[1] | ~flit_sent_prev);
		  
		  wire 	     one_or_more_credits;
		  assign one_or_more_credits
		    = int_flow_ctrl[0] | (int_flow_ctrl[1] & ~flit_sent_prev);
		  
		  wire 	     next_free;
		  assign next_free
		    = flit_sent ? two_or_more_credits : one_or_more_credits;
		  
		  assign next_free_ocvc[ocvc] = next_free;
		  
		  // NOTE: When sending the first flit in each packet, we must 
		  // have won VC allocation. Consequently, the destination 
		  // output VC must have been eligible and thus not assigned to 
		  // any input VC, so we know that nobody sent a flit to it in 
		  // the previous cycle.
		  
		  wire 	     free_spec;
		  assign free_spec = |int_flow_ctrl;
		  
		  assign free_spec_ocvc[ocvc] = free_spec;
		  
	       end
	     
	     wire 	     free_nonspec_s, free_nonspec_q;
	     assign free_nonspec_s = |(next_free_ocvc & vc_allocated_next_ocvc);
	     c_dff
	       #(.width(1),
		 .reset_value(1'b1),
		 .reset_type(reset_type))
	     free_nonspecq
	       (.clk(clk),
		.reset(reset),
		.active(cred_track_active),
		.d(free_nonspec_s),
		.q(free_nonspec_q));
	     
	     assign free_nonspec = free_nonspec_q;
	     
	     if(num_vcs_per_class == 1)
	       assign free_spec = free_spec_ocvc;
	     else if(num_vcs_per_class > 1)
	       assign free_spec = |(free_spec_ocvc & vc_gnt_ocvc);
	     
	     assign error_ct_overflow = 1'b0;
	     
	  end
	
	// credits are forwarded from the output controllers individually as 
	// pulses, accumulated at the input controllers, and used whenever a
	// flit is sent to the crossbar
	`INT_FLOW_CTRL_TYPE_PUSH:
	  begin
	     
	     wire [0:num_vcs_per_class-1] cred_ocvc;
	     assign cred_ocvc = int_flow_ctrl_ocvc;
	     
	     wire 			  cred_allocated;
	     assign cred_allocated = |(cred_ocvc & vc_allocated_ocvc);
	     
	     wire 			  cred_unallocated;
	     
	     if(num_vcs_per_class == 1)
	       assign cred_unallocated = cred_ocvc;
	     else
	       assign cred_unallocated = |(cred_ocvc & vc_gnt_ocvc);
	     
	     wire [0:cred_hold_width-1]   cred_hold_q;
	     
	     wire 			  has_cred_s, has_cred_q;
	     if(vc_alloc_requires_credit)
	       assign has_cred_s 
		 = vc_allocated_q ? 
		   ((has_cred_q & ~sw_gnt) | (|cred_hold_q) | cred_allocated) :
		   (~sw_gnt | cred_unallocated);
	     else
	       assign has_cred_s
		 = vc_allocated_q ?
		   ((has_cred_q & ~sw_gnt) | (|cred_hold_q) | cred_allocated) :
		   (~sw_gnt & cred_unallocated);
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type))
	     has_credq
	       (.clk(clk),
		.reset(reset),
		.active(cred_track_active),
		.d(has_cred_s),
		.q(has_cred_q));
	     
	     assign free_nonspec = has_cred_q;
	     
	     assign free_spec = cred_unallocated;
	     
	     wire 			  incr_cred_hold;
	     assign incr_cred_hold = cred_allocated & has_cred_q & ~sw_gnt;
	     
	     wire 			  decr_cred_hold;
	     assign decr_cred_hold = ~cred_allocated & |cred_hold_q & sw_gnt;
	     
	     wire [0:cred_hold_width-1]   cred_hold_new;
	     if(vc_alloc_requires_credit)
	       assign cred_hold_new = cred_unallocated & ~sw_gnt;
	     else
	       assign cred_hold_new = {cred_hold_width{1'b0}};
	     
	     wire [0:cred_hold_width-1]   cred_hold_s;
	     assign cred_hold_s
	       = vc_allocated_q ?
		 (cred_hold_q + incr_cred_hold - decr_cred_hold) :
		 cred_hold_new;
	     c_dff
	       #(.width(cred_hold_width),
		 .reset_type(reset_type))
	     cred_holdq
	       (.clk(clk),
		.reset(reset),
		.active(cred_track_active),
		.d(cred_hold_s),
		.q(cred_hold_q));
	     
	     assign error_ct_overflow
	       = vc_allocated_q && (cred_hold_q == num_flits_per_vc-1) &&
		 incr_cred_hold;
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	
	if(error_no_header)
	  $display("ERROR: Stray flit received in module %m.");
	
	if(error_ct_overflow)
	  $display("ERROR: Credit tracker overflow in module %m.");
	
     end
   
   // synopsys translate_on
   
   assign errors[0] = error_no_header;
   assign errors[1] = error_ct_overflow;
   assign errors[2] = error_invalid_port;
   assign errors[3] = error_invalid_class;
   
endmodule
