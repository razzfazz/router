// $Id$

/*
Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list
of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this 
list of conditions and the following disclaimer in the documentation and/or 
other materials provided with the distribution.
Neither the name of the Stanford University nor the names of its contributors 
may be used to endorse or promote products derived from this software without 
specific prior written permission.

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
// input port controller
//==============================================================================

module rtr_ip_ctrl_mac
  (clk, reset, router_address, channel_in, route_valid_out_ivc, 
   route_out_ivc_op, route_out_ivc_orc, flit_valid_out_ivc, flit_last_out_ivc, 
   flit_head_out_ivc, flit_tail_out_ivc, route_fast_out_op, route_fast_out_orc, 
   flit_valid_fast_out, flit_head_fast_out, flit_tail_fast_out, 
   flit_sel_fast_out_ivc, flit_data_out, flit_sel_in_ivc, flit_sent_in, 
   flit_sel_fast_in, flit_sent_fast_in, flow_ctrl_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length = 4;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length = 1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select implementation variant for flit buffer register file
   parameter fb_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 1;
   
   // enable dual-path allocation
   parameter dual_path_alloc = 0;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // width required to select individual resource class
   localparam resource_class_idx_width = clogb(num_resource_classes);
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   // width required for lookahead routing information
   localparam la_route_info_width = port_idx_width + resource_class_idx_width;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
   // width of flit buffer
   localparam fb_width = 1 + 1 + flit_data_width;
   
   // required address size for a single VC's buffer
   localparam fb_addr_width = clogb(num_flits_per_vc);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming channel
   input [0:channel_width-1] 	 channel_in;
   
   // routing information is valid
   output [0:num_vcs-1] 	 route_valid_out_ivc;
   wire [0:num_vcs-1] 		 route_valid_out_ivc;
   
   // selected output port
   output [0:num_vcs*num_ports-1] route_out_ivc_op;
   wire [0:num_vcs*num_ports-1]   route_out_ivc_op;
   
   // selected output resource class
   output [0:num_vcs*num_resource_classes-1] route_out_ivc_orc;
   wire [0:num_vcs*num_resource_classes-1]   route_out_ivc_orc;
   
   // flit is present
   output [0:num_vcs-1] 		     flit_valid_out_ivc;
   wire [0:num_vcs-1] 			     flit_valid_out_ivc;
   
   // flit is last remaining flit
   output [0:num_vcs-1] 		     flit_last_out_ivc;
   wire [0:num_vcs-1] 			     flit_last_out_ivc;
   
   // flit is head flit
   output [0:num_vcs-1] 		     flit_head_out_ivc;
   wire [0:num_vcs-1] 			     flit_head_out_ivc;
   
   // flit is tail flit
   output [0:num_vcs-1] 		     flit_tail_out_ivc;
   wire [0:num_vcs-1] 			     flit_tail_out_ivc;
   
   // 
   output [0:num_ports-1] 		     route_fast_out_op;
   wire [0:num_ports-1] 		     route_fast_out_op;
   
   // 
   output [0:num_resource_classes-1] 	     route_fast_out_orc;
   wire [0:num_resource_classes-1] 	     route_fast_out_orc;
   
   // 
   output 				     flit_valid_fast_out;
   wire 				     flit_valid_fast_out;
   
   // 
   output 				     flit_head_fast_out;
   wire 				     flit_head_fast_out;
   
   // 
   output 				     flit_tail_fast_out;
   wire 				     flit_tail_fast_out;
   
   // 
   output [0:num_vcs-1] 		     flit_sel_fast_out_ivc;
   wire [0:num_vcs-1] 			     flit_sel_fast_out_ivc;
   
   // outgoing flit data
   output [0:flit_data_width-1] 	     flit_data_out;
   wire [0:flit_data_width-1] 		     flit_data_out;
   
   // indicate which VC is candidate for being sent
   input [0:num_vcs-1] 			     flit_sel_in_ivc;
   
   // flit was sent
   input 				     flit_sent_in;
   
   //
   input 				     flit_sel_fast_in;
   
   //
   input 				     flit_sent_fast_in;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] 	     flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 		     flow_ctrl_out;
   
   // internal error condition detected
   output 				     error;
   wire 				     error;
   
   
   //---------------------------------------------------------------------------
   // channel input staging
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 			     fb_full_ivc;
   
   wire 				     chi_active;
   assign chi_active = ~&fb_full_ivc;
   
   wire 				     chi_flit_valid;
   wire 				     chi_flit_head;
   wire 				     chi_flit_tail;
   wire [0:flit_data_width-1] 		     chi_flit_data;
   wire [0:num_vcs-1] 			     chi_flit_sel_ivc;
   rtr_channel_input
     #(.num_vcs(num_vcs),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .la_route_info_width(la_route_info_width),
       .route_info_width(route_info_width),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   chi
     (.clk(clk),
      .reset(reset),
      .active(chi_active),
      .channel_in(channel_in),
      .flit_valid_out(chi_flit_valid),
      .flit_head_out(chi_flit_head),
      .flit_tail_out(chi_flit_tail),
      .flit_data_out(chi_flit_data),
      .flit_sel_out_ivc(chi_flit_sel_ivc));
   
   wire [0:num_vcs-1] 			     chi_flit_valid_ivc;
   assign chi_flit_valid_ivc = {num_vcs{chi_flit_valid}} & chi_flit_sel_ivc;
   
   wire [0:header_info_width-1] 	     chi_header_info;
   assign chi_header_info = chi_flit_data[0:header_info_width-1];

   wire [0:la_route_info_width-1] 	     chi_la_route_info;
   assign chi_la_route_info = chi_header_info[0:la_route_info_width-1];
   
   wire [0:route_info_width-1] 		     chi_route_info;
   assign chi_route_info
     = chi_header_info[la_route_info_width:
		       la_route_info_width+route_info_width-1];
   
   
   //---------------------------------------------------------------------------
   // global lookahead routing information decoder
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] 		     gld_route_op;
   wire [0:num_resource_classes-1] 	     gld_route_orc;
   
   generate
      
      begin:gld
	 
	 wire [0:port_idx_width-1] route_port;
	 assign route_port = chi_la_route_info[0:port_idx_width-1];
	 
	 wire [0:num_ports-1] 	   route_op;
	 c_decode
	   #(.num_ports(num_ports))
	 route_op_dec
	   (.data_in(route_port),
	    .data_out(route_op));
	 
	 wire [0:num_resource_classes-1] route_orc;
	 
	 if(num_resource_classes == 1)
	   assign route_orc = 1'b1;
	 else if(num_resource_classes > 1)
	   begin
	      
	      wire [0:resource_class_idx_width-1] route_rcsel;
	      assign route_rcsel
		= chi_la_route_info[port_idx_width:
				    port_idx_width+resource_class_idx_width-1];
	      
	      c_decode
		#(.num_ports(num_resource_classes))
	      route_orc_dec
		(.data_in(route_rcsel),
		 .data_out(route_orc));
	      
	   end
	 
	 assign gld_route_op = route_op;
	 assign gld_route_orc = route_orc;
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // global lookahead routing information update logic
   //---------------------------------------------------------------------------
   
   wire [0:la_route_info_width-1] 		  glu_la_route_info;
   wire [0:flit_data_width-1] 			  glu_flit_data;
   
   generate
      
      begin:glu
	 
	 wire [0:router_addr_width-1] next_router_address;
	 rtr_next_hop_addr
	   #(.num_resource_classes(num_resource_classes),
	     .num_routers_per_dim(num_routers_per_dim),
	     .num_dimensions(num_dimensions),
	     .num_nodes_per_router(num_nodes_per_router),
	     .connectivity(connectivity),
	     .routing_type(routing_type))
	 nha
	   (.router_address(router_address),
	    .route_info(chi_route_info),
	    .la_route_info(chi_la_route_info),
	    .next_router_address(next_router_address));
	 
	 wire [0:num_message_classes-1] sel_mc;
	 c_mat_mult
	   #(.dim1_width(num_message_classes),
	     .dim2_width(num_resource_classes*num_vcs_per_class),
	     .dim3_width(1),
	     .prod_op(`BINARY_OP_AND),
	     .sum_op(`BINARY_OP_OR))
	 sel_mc_mmult
	   (.input_a(chi_flit_sel_ivc),
	    .input_b({(num_resource_classes*num_vcs_per_class){1'b1}}),
	    .result(sel_mc));
	 
	 wire [0:num_ports-1] 		route_op;
	 wire [0:num_resource_classes-1] route_orc;
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
	    .sel_irc(gld_route_orc),
	    .route_info(chi_route_info),
	    .route_op(route_op),
	    .route_orc(route_orc));
	 
	 wire [0:port_idx_width-1] 	 route_port;
	 c_encode
	   #(.num_ports(num_ports))
	 route_port_enc
	   (.data_in(route_op),
	    .data_out(route_port));
	 
	 wire [0:la_route_info_width-1]  la_route_info;
	 assign la_route_info[0:port_idx_width-1] = route_port;
	 
	 if(num_resource_classes > 1)
	   begin
	      
	      wire [0:resource_class_idx_width-1] route_rcsel;
	      c_encode
		#(.num_ports(num_resource_classes))
	      route_rcsel_enc
		(.data_in(route_orc),
		 .data_out(route_rcsel));
	      
	      assign la_route_info[port_idx_width:
				   port_idx_width+resource_class_idx_width-1]
		= route_rcsel;
	      
	   end
	 
	 assign glu_la_route_info = la_route_info;
	 assign glu_flit_data[0:la_route_info_width-1]
	   = (chi_flit_valid & chi_flit_head) ? 
	     la_route_info : 
	     chi_flit_data[0:la_route_info_width-1];
	 assign glu_flit_data[la_route_info_width:flit_data_width-1]
	   = chi_flit_data[la_route_info_width:flit_data_width-1];
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 				  flit_sent_in_ivc;
   assign flit_sent_in_ivc = {num_vcs{flit_sent_in}} & flit_sel_in_ivc;
   
   wire [0:num_vcs-1] 				  flit_sent_fast_in_ivc;
   
   generate
      
      if(dual_path_alloc)
	assign flit_sent_fast_in_ivc
	  = {num_vcs{flit_sent_fast_in}} & chi_flit_sel_ivc;
      else
	assign flit_sent_fast_in_ivc = {num_vcs{1'b0}};
      
   endgenerate
   
   wire [0:num_vcs-1] 				  flit_sent_prev_ivc;
   wire 					  flit_head_prev;
   wire [0:num_vcs-1] 				  fb_empty_ivc;
   wire [0:num_vcs*flit_data_width-1] 		  llu_flit_data_ivc;
   wire [0:num_vcs*5-1] 			  errors_ivc;
   
   genvar 					  ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------
	   
	   wire chi_flit_valid;
	   assign chi_flit_valid = chi_flit_valid_ivc[ivc];
	   
	   wire flit_sent_in;
	   assign flit_sent_in = flit_sent_in_ivc[ivc];
	   
	   wire flit_sent_fast_in;
	   assign flit_sent_fast_in = flit_sent_fast_in_ivc[ivc];
	   
	   wire flit_sent_prev;
	   assign flit_sent_prev = flit_sent_prev_ivc[ivc];
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------
	   
	   wire flit_valid_out;
	   assign flit_valid_out_ivc[ivc] = flit_valid_out;
	   
	   wire flit_last_out;
	   assign flit_last_out_ivc[ivc] = flit_last_out;
	   
	   wire flit_head_out;
	   assign flit_head_out_ivc[ivc] = flit_head_out;
	   
	   wire flit_tail_out;
	   assign flit_tail_out_ivc[ivc] = flit_tail_out;
	   
	   wire fb_empty;
	   assign fb_empty_ivc[ivc] = fb_empty;
	   
	   wire fb_full;
	   assign fb_full_ivc[ivc] = fb_full;
	   
	   wire [0:flit_data_width-1] llu_flit_data;
	   assign llu_flit_data_ivc[ivc*flit_data_width:
				    (ivc+1)*flit_data_width-1] = llu_flit_data;
	   
	   wire 		      route_valid_out;
	   assign route_valid_out_ivc[ivc] = route_valid_out;
	   
	   wire [0:num_ports-1]       route_out_op;
	   assign route_out_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
	     = route_out_op;
	   
	   wire [0:num_resource_classes-1] route_out_orc;
	   assign route_out_ivc_orc[ivc*num_resource_classes:
				    (ivc+1)*num_resource_classes-1]
	     = route_out_orc;
	   
	   wire [0:4] 			   errors;
	   assign errors_ivc[ivc*5:(ivc+1)*5-1] = errors;
	   
	   
	   //-------------------------------------------------------------------
	   // flit buffer
	   //-------------------------------------------------------------------
	   
	   wire 			   error_fb_underflow;
	   wire 			   error_fb_overflow;
	   
	   wire 			   fb_almost_empty;
	   wire [0:flit_data_width-1] 	   fb_flit_data;
	   wire 			   fb_flit_head;
	   wire 			   fb_flit_tail;
	   wire [0:la_route_info_width-1]  fb_la_route_info;
	   wire [0:route_info_width-1] 	   fb_route_info;
	   
	   begin:fb
	      
	      wire push_active;
	      assign push_active = chi_flit_valid;
	      
	      wire pop_active;
	      assign pop_active = chi_flit_valid | ~fb_empty;
	      
	      wire push;
	      assign push = chi_flit_valid;
	      
	      wire pop;
	      assign pop = flit_sent_in | flit_sent_fast_in;
	      
	      wire [0:fb_addr_width-1] push_addr;
	      wire [0:fb_addr_width-1] pop_addr;
	      wire 		       almost_empty;
	      wire 		       empty;
	      wire 		       almost_full;
	      wire 		       full;
	      wire [0:1] 	       errors;
	      c_fifo_ctrl
		#(.depth(num_flits_per_vc),
		  .reset_type(reset_type))
	      fc
		(.clk(clk),
		 .reset(reset),
		 .push_active(push_active),
		 .pop_active(pop_active),
		 .push(push),
		 .pop(pop),
		 .push_addr(push_addr),
		 .pop_addr(pop_addr),
		 .almost_empty(almost_empty),
		 .empty(empty),
		 .almost_full(almost_full),
		 .full(full),
		 .errors(errors));
	      
	      wire 		       write_enable;
	      wire 		       read_active;
	      wire [0:fb_addr_width-1] read_addr;
	      
	      if(explicit_pipeline_register)
		begin
		   
		   if(explicit_pipeline_register == 1)
		     assign write_enable = chi_flit_valid;
		   else if(explicit_pipeline_register > 1)
		     begin
			if(dual_path_alloc)
			  assign write_enable
			    = chi_flit_valid & ~flit_sent_fast_in;
			else
			  assign write_enable
			    = chi_flit_valid & ~(empty & flit_sent_in);
		     end
		   
		   assign read_active = ~empty;
		   
		   assign read_addr = pop_addr;
		   
		end
	      else
		begin
		   
		   assign write_enable = chi_flit_valid;
		   
		   wire [0:fb_addr_width-1] read_addr_s, read_addr_q;
		   assign read_addr_s = pop_addr;
		   c_dff
		     #(.width(fb_addr_width),
		       .reset_type(reset_type))
		   read_addrq
		     (.clk(clk),
		      .reset(1'b0),
		      .active(pop_active),
		      .d(read_addr_s),
		      .q(read_addr_q));
		   
		   assign read_active = flit_sent_prev;
		   
		   assign read_addr = read_addr_q;
		   
		end
	      
	      wire 			    peek_active;
	      assign peek_active = ~empty & ~almost_empty;
	      
	      wire [0:fb_addr_width-1] 	    peek_addr;
	      c_incr
		#(.width(fb_addr_width),
		  .max_value(num_flits_per_vc - 1))
	      peek_addr_incr
		(.data_in(pop_addr),
		 .data_out(peek_addr));
	      
	      wire [0:fb_width-1] 	    write_data;
	      assign write_data[0] = chi_flit_head;
	      assign write_data[1] = chi_flit_tail;
	      assign write_data[2:2+flit_data_width-1] = chi_flit_data;
	      
	      wire [0:fb_width-1] 	    read_data;
	      wire [0:fb_width-1] 	    peek_data;
	      c_regfile
		#(.depth(num_flits_per_vc),
		  .width(fb_width),
		  .num_read_ports(2),
		  .regfile_type(fb_regfile_type))
	      rf
		(.clk(clk),
		 .write_active(push_active),
		 .write_enable(write_enable),
		 .write_address(push_addr),
		 .write_data(write_data),
		 .read_active({read_active, peek_active}),
		 .read_address({read_addr, peek_addr}),
		 .read_data({read_data, peek_data}));
	      
	      wire [0:header_info_width-1]  peek_header_info;
	      assign peek_header_info = peek_data[2:2+header_info_width-1];
	      
	      assign error_fb_underflow = errors[0];
	      assign error_fb_overflow = errors[1];
	      
	      assign fb_almost_empty = almost_empty;
	      assign fb_empty = empty;
	      assign fb_full = full;
	      assign fb_flit_data = read_data[2:2+flit_data_width-1];
	      assign fb_flit_head = peek_data[0];
	      assign fb_flit_tail = peek_data[1];
	      assign fb_la_route_info
		= peek_header_info[0:la_route_info_width-1];
	      assign fb_route_info
		= peek_header_info[la_route_info_width:
				   la_route_info_width+route_info_width-1];
	      
	   end
	   
	   if(dual_path_alloc)
	     begin
		assign flit_valid_out = ~fb_empty;
		assign flit_last_out = fb_almost_empty;
	     end
	   else
	     begin
		assign flit_valid_out = chi_flit_valid | ~fb_empty;
		assign flit_last_out
		  = chi_flit_valid ? fb_empty : fb_almost_empty;
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // track whether frontmost flit is head or tail
	   //-------------------------------------------------------------------
	   
	   wire 			     htt_flit_head;
	   wire 			     htt_flit_tail;
	   
	   begin:htt
	      
	      wire active;
	      assign active = chi_flit_valid | ~fb_empty;
	      
	      wire flit_head_s, flit_head_q;
	      assign flit_head_s
		= flit_sent_in ?
		  (fb_almost_empty ? chi_flit_head : fb_flit_head) : 
		  (fb_empty ? chi_flit_head : flit_head_q);
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      flit_headq
		(.clk(clk),
		 .reset(1'b0),
		 .active(active),
		 .d(flit_head_s),
		 .q(flit_head_q));
	      
	      wire flit_tail_s, flit_tail_q;
	      assign flit_tail_s
		= flit_sent_in ?
		  (fb_almost_empty ? chi_flit_tail : fb_flit_tail) : 
		  (fb_empty ? chi_flit_tail : flit_tail_q);
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      flit_tailq
		(.clk(clk),
		 .reset(1'b0),
		 .active(active),
		 .d(flit_tail_s),
		 .q(flit_tail_q));
	      
	      assign htt_flit_head = flit_head_q;
	      assign htt_flit_tail = flit_tail_q;
	      
	   end
	   
	   if(dual_path_alloc)
	     begin
		assign flit_head_out = htt_flit_head;
		assign flit_tail_out = htt_flit_tail;
	     end
	   else
	     begin
		assign flit_head_out = fb_empty ? chi_flit_head : htt_flit_head;
		assign flit_tail_out = fb_empty ? chi_flit_tail : htt_flit_tail;
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // track header information for frontmost packet
	   //-------------------------------------------------------------------
	   
	   wire hit_valid;
	   wire [0:num_ports-1] hit_route_op;
	   wire [0:num_resource_classes-1] hit_route_orc;
	   wire [0:la_route_info_width-1]  hit_la_route_info;
	   wire [0:route_info_width-1] 	   hit_route_info;
	   
	   wire 			   error_no_header;
	   
	   begin:hit
	      
	      wire valid_active;
	      assign valid_active = chi_flit_valid | ~fb_empty;
	      
	      wire valid_s, valid_q;
	      
	      if(dual_path_alloc)
		assign valid_s
		  = flit_sent_in ?
		    (~htt_flit_tail | ~fb_almost_empty | chi_flit_valid) :
		    (flit_sent_fast_in ? 
		     ~chi_flit_tail : 
		     (valid_q | chi_flit_valid));
	      else
		assign valid_s
		  = flit_sent_in ? 
		    (fb_empty ?
		     ~chi_flit_tail :
		     (~htt_flit_tail | ~fb_almost_empty | chi_flit_valid)) :
		    (valid_q | chi_flit_valid);
	      
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      validq
		(.clk(clk),
		 .reset(reset),
		 .active(valid_active),
		 .d(valid_s),
		 .q(valid_q));
	      
	      wire active;
	      assign active = ~valid_q | (~fb_empty & htt_flit_tail);
	      
	      wire [0:num_ports-1] route_op;
	      wire [0:num_resource_classes-1] route_orc;
	      wire [0:la_route_info_width-1]  la_route_info;
	      
	      if(dual_path_alloc)
		begin
		   
		   // NOTE: For dual-path routing, we never have to bypass the
		   // selected output port from the channel input (which would
		   // have to go through a decoder first); thus, it makes sense
		   // to store the port in one-hot form here in order to improve
		   // timing.
		   
		   wire [0:port_idx_width-1] fb_route_port;
		   assign fb_route_port = fb_la_route_info[0:port_idx_width-1];
		   
		   wire [0:num_ports-1]      fb_route_op;
		   c_decode
		     #(.num_ports(num_ports))
		   fb_route_op_dec
		     (.data_in(fb_route_port),
		      .data_out(fb_route_op));
		   
		   wire [0:num_ports-1]      route_op_s, route_op_q;
		   assign route_op_s
		     = (flit_sent_in & htt_flit_tail) ?
		       (fb_almost_empty ? gld_route_op : fb_route_op) :
		       (valid_q ? route_op_q : gld_route_op);
		   c_dff
		     #(.width(num_ports),
		       .reset_type(reset_type))
		   route_opq
		     (.clk(clk),
		      .reset(1'b0),
		      .active(active),
		      .d(route_op_s),
		      .q(route_op_q));
		   
		   assign route_op = route_op_q;
		   
		   wire [0:port_idx_width-1] route_port;
		   c_encode
		     #(.num_ports(num_ports))
		   route_port_enc
		     (.data_in(route_op_q),
		      .data_out(route_port));
		   
		   assign la_route_info[0:port_idx_width-1] = route_port;
		   
		   if(num_resource_classes == 1)
		     assign route_orc = 1'b1;
		   else if(num_resource_classes > 1)
		     begin
			
			wire [0:resource_class_idx_width-1] fb_route_rcsel;
			assign fb_route_rcsel
			  = fb_la_route_info[port_idx_width:
					     port_idx_width+
					     resource_class_idx_width-1];
			
			wire [0:num_resource_classes-1]     fb_route_orc;
			c_decode
			  #(.num_ports(num_resource_classes))
			fb_route_orc_dec
			  (.data_in(fb_route_rcsel),
			   .data_out(fb_route_orc));
			
			wire [0:num_resource_classes-1]     route_orc_s;
			wire [0:num_resource_classes-1]     route_orc_q;
			assign route_orc_s
			  = (flit_sent_in & htt_flit_tail) ?
			    (fb_almost_empty ? gld_route_orc : fb_route_orc) :
			    (valid_q ? route_orc_q : gld_route_orc);
			c_dff
			  #(.width(num_resource_classes),
			    .reset_type(reset_type))
			route_orcq
			  (.clk(clk),
			   .reset(1'b0),
			   .active(active),
			   .d(route_orc_s),
			   .q(route_orc_q));
			
			assign route_orc = route_orc_q;
			
			wire [0:resource_class_idx_width-1] route_rcsel;
			c_encode
			  #(.num_ports(num_resource_classes))
			route_rcsel_enc
			  (.data_in(route_orc_q),
			   .data_out(route_rcsel));
			
			assign la_route_info[port_idx_width:
					     port_idx_width+
					     resource_class_idx_width-1]
			  = route_rcsel;
			
		     end
		   
		end
	      else
		begin
		   
		   wire [0:la_route_info_width-1] la_route_info_s;
		   wire [0:la_route_info_width-1] la_route_info_q;
		   assign la_route_info_s
		     = (flit_sent_in & flit_tail_out) ?
		       (fb_almost_empty ? 
			chi_la_route_info : 
			fb_la_route_info) :
		       (valid_q ? la_route_info_q : chi_la_route_info);
		   c_dff
		     #(.width(la_route_info_width),
		       .reset_type(reset_type))
		   la_route_infoq
		     (.clk(clk),
		      .reset(1'b0),
		      .active(active),
		      .d(la_route_info_s),
		      .q(la_route_info_q));
		   
		   assign la_route_info = la_route_info_q;
		   
		   wire [0:port_idx_width-1] 	  route_port;
		   assign route_port = la_route_info_q[0:port_idx_width-1];
		   
		   c_decode
		     #(.num_ports(num_ports))
		   route_op_dec
		     (.data_in(route_port),
		      .data_out(route_op));
		   
		   if(num_resource_classes == 1)
		     assign route_orc = 1'b1;
		   else if(num_resource_classes > 1)
		     begin
			
			wire [0:resource_class_idx_width-1] route_rcsel;
			assign route_rcsel
			  = la_route_info_q[port_idx_width:
					    port_idx_width+
					    resource_class_idx_width-1];
			
			c_decode
			  #(.num_ports(num_resource_classes))
			route_orc_dec
			  (.data_in(route_rcsel),
			   .data_out(route_orc));
			
		     end
		   
		end
	      
	      wire [0:route_info_width-1]    route_info_s, route_info_q;

	      if(dual_path_alloc)
		assign route_info_s
		  = (flit_sent_in & htt_flit_tail) ?
		    (fb_almost_empty ? chi_route_info : fb_route_info) :
		    (valid_q ? route_info_q : chi_route_info);
	      else
		assign route_info_s
		  = (flit_sent_in & flit_tail_out) ?
		    (fb_almost_empty ? chi_route_info : fb_route_info) :
		    (valid_q ? route_info_q : chi_route_info);
	      c_dff
		#(.width(route_info_width),
		  .reset_type(reset_type))
	      route_infoq
		(.clk(clk),
		 .reset(1'b0),
		 .active(active),
		 .d(route_info_s),
		 .q(route_info_q));
	      
	      assign hit_valid = valid_q;
	      assign hit_route_op = route_op;
	      assign hit_route_orc = route_orc;
	      assign hit_la_route_info = la_route_info;
	      assign hit_route_info = route_info_q;
	      
	      assign error_no_header
		= ~valid_q & (~fb_empty | (chi_flit_valid & ~chi_flit_head));
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // generate routing control signals
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 		       route_unmasked_op;
	   wire [0:num_resource_classes-1] 	       route_unmasked_orc;
	   
	   if(dual_path_alloc)
	     begin
		assign route_valid_out = hit_valid;
		assign route_unmasked_op = hit_route_op;
		assign route_unmasked_orc = hit_route_orc;
	     end
	   else
	     begin
		assign route_valid_out = hit_valid | chi_flit_valid;
		assign route_unmasked_op
		  = hit_valid ? hit_route_op : gld_route_op;
		assign route_unmasked_orc
		  = hit_valid ? hit_route_orc : gld_route_orc;
	     end
	   
	   wire rf_active;
	   assign rf_active = route_valid_out;
	   
	   wire [0:1] rf_errors;
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
	       .vc_id(ivc))
	   rf
	     (.clk(clk),
	      .reset(reset),
	      .active(rf_active),
	      .route_valid(route_valid_out),
	      .route_in_op(route_unmasked_op),
	      .route_in_orc(route_unmasked_orc),
	      .route_out_op(route_out_op),
	      .route_out_orc(route_out_orc),
	      .errors(rf_errors));
	   
	   wire       error_invalid_port;
	   assign error_invalid_port =  rf_errors[0];
	   
	   wire       error_invalid_class;
	   assign error_invalid_class = rf_errors[1];
	   
	   
	   //-------------------------------------------------------------------
	   // local lookahead routing information update logic
	   //-------------------------------------------------------------------
	   
	   begin:llu
	      
	      wire [0:router_addr_width-1] next_router_address;
	      rtr_next_hop_addr
		#(.num_resource_classes(num_resource_classes),
		  .num_routers_per_dim(num_routers_per_dim),
		  .num_dimensions(num_dimensions),
		  .num_nodes_per_router(num_nodes_per_router),
		  .connectivity(connectivity),
		  .routing_type(routing_type))
	      nha
		(.router_address(router_address),
		 .route_info(hit_route_info),
		 .la_route_info(hit_la_route_info),
		 .next_router_address(next_router_address));
	      
	      wire [0:num_message_classes-1] sel_mc;
	      c_align
		#(.in_width(1),
		  .out_width(num_message_classes),
		  .offset((ivc / (num_resource_classes*num_vcs_per_class)) %
			  num_message_classes))
	      sel_mc_agn
		(.data_in(1'b1),
		 .dest_in({num_message_classes{1'b0}}),
		 .data_out(sel_mc));
	      
	      wire [0:num_ports-1] 	     route_op;
	      wire [0:num_resource_classes-1] route_orc;
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
		 .sel_irc(hit_route_orc),
		 .route_info(hit_route_info),
		 .route_op(route_op),
		 .route_orc(route_orc));
	      
	      wire [0:port_idx_width-1]       route_port;
	      c_encode
		#(.num_ports(num_ports))
	      route_port_enc
		(.data_in(route_op),
		 .data_out(route_port));
	      
	      wire [0:la_route_info_width-1]  la_route_info;
	      assign la_route_info[0:port_idx_width-1] = route_port;
	      
	      if(num_resource_classes > 1)
		begin
		   
		   wire [0:resource_class_idx_width-1] route_rcsel;
		   c_encode
		     #(.num_ports(num_resource_classes))
		   route_rcsel_enc
		     (.data_in(route_orc),
		      .data_out(route_rcsel));
		   
		   assign la_route_info[port_idx_width:
					port_idx_width+
					resource_class_idx_width-1]
		     = route_rcsel;
		   
		end
	      
	      if(explicit_pipeline_register)
		assign llu_flit_data[0:la_route_info_width-1]
		  = (~fb_empty & htt_flit_head) ? 
		    la_route_info : 
		    fb_flit_data[0:la_route_info_width-1];
	      else
		begin
		   
		   wire active;
		   assign active = (~fb_empty & htt_flit_head) |
				   (chi_flit_valid & chi_flit_head);
		   
		   wire [0:la_route_info_width-1] la_route_info_s;
		   wire [0:la_route_info_width-1] la_route_info_q;
		   assign la_route_info_s
		     = hit_valid ? la_route_info : glu_la_route_info;
		   c_dff
		     #(.width(la_route_info_width),
		       .reset_type(reset_type))
		   la_route_infoq
		     (.clk(clk),
		      .reset(1'b0),
		      .active(active),
		      .d(la_route_info_s),
		      .q(la_route_info_q));
		   
		   assign llu_flit_data[0:la_route_info_width-1]
		     = (flit_sent_prev & flit_head_prev) ? 
		       la_route_info_q :
		       fb_flit_data[0:la_route_info_width-1];
		   
		end
	      
	      assign llu_flit_data[la_route_info_width:flit_data_width-1]
		= fb_flit_data[la_route_info_width:flit_data_width-1];
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // error checking
	   //-------------------------------------------------------------------
	   
	   // synopsys translate_off
	   
	   always @(posedge clk)
	     begin
		
		if(error_no_header)
		  $display("ERROR: Stray flit received in module %m.");
		
	     end
	   
	   // synopsys translate_on
	   
	   assign errors[0] = error_fb_underflow;
	   assign errors[1] = error_fb_overflow;
	   assign errors[2] = error_no_header;
	   assign errors[3] = error_invalid_port;
	   assign errors[4] = error_invalid_class;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate fast-path control signals
   //---------------------------------------------------------------------------
   
   generate
      
      if(dual_path_alloc)
	begin:fpc
	   
	   assign route_fast_out_op = gld_route_op;
	   assign route_fast_out_orc = gld_route_orc;
	   
	   assign flit_valid_fast_out = chi_flit_valid;
	   assign flit_head_fast_out = chi_flit_head;
	   assign flit_tail_fast_out = chi_flit_tail;
	   assign flit_sel_fast_out_ivc = chi_flit_sel_ivc;
	   
	end
      else
	begin
	   
	   assign route_fast_out_op = {num_ports{1'b0}};
	   assign route_fast_out_orc = {num_resource_classes{1'b0}};
	   
	   assign flit_valid_fast_out = 1'b0;
	   assign flit_head_fast_out = 1'b0;
	   assign flit_tail_fast_out = 1'b0;
	   assign flit_sel_fast_out_ivc = {num_vcs{1'b0}};
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // flit buffer read path
   //---------------------------------------------------------------------------
   
   wire alloc_active;
   assign alloc_active = chi_flit_valid | ~&fb_empty_ivc;
   
   wire [0:num_vcs-1] flit_sel_ivc;
   wire 	      flit_sent;
   
   generate
      
      if(dual_path_alloc)
	begin
	   assign flit_sel_ivc
	     = flit_sel_fast_in ? chi_flit_sel_ivc : flit_sel_in_ivc;
	   assign flit_sent = flit_sent_in | flit_sent_fast_in;
	end
      else
	begin
	   assign flit_sel_ivc = flit_sel_in_ivc;
	   assign flit_sent = flit_sent_in;
	end
      
      if(explicit_pipeline_register)
	begin
	   
	   wire [0:flit_data_width-1] flit_data;
	   
	   if(num_vcs == 1)
	     assign flit_data = llu_flit_data_ivc;
	   else if(num_vcs > 1)
	     begin
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_data_width))
		flit_data_sel
		  (.select(flit_sel_in_ivc),
		   .data_in(llu_flit_data_ivc),
		   .data_out(flit_data));
		
	     end
	   
	   wire bypass;
	   
	   if(dual_path_alloc)
	     assign bypass = flit_sel_fast_in;
	   else
	     assign bypass = |(flit_sel_in_ivc & fb_empty_ivc);
	   
	   wire [0:flit_data_width-1] flit_data_s, flit_data_q;
	   assign flit_data_s = bypass ? glu_flit_data : flit_data;
	   c_dff
	     #(.width(flit_data_width),
	       .reset_type(reset_type))
	   flit_dataq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
	      .d(flit_data_s),
	      .q(flit_data_q));
	   
	   assign flit_data_out = flit_data_q;
	   
	end
      else
	begin
	   
	   // NOTE: We need to clock-gate this register such that it can be
	   // turned off once no more flits are available; this will likely
	   // cause it to end up being free-running.
	   
	   wire flit_sent_active;
	   
	   wire flit_sent_s, flit_sent_q;
	   assign flit_sent_s = flit_sent;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_sentq
	     (.clk(clk),
	      .reset(reset),
	      .active(flit_sent_active),
	      .d(flit_sent_s),
	      .q(flit_sent_q));
	   
	   assign flit_sent_active = alloc_active | flit_sent_q;
	   
	   wire flit_head;
	   
	   if(dual_path_alloc)
	     assign flit_head = flit_sel_fast_in ? 
				chi_flit_head : 
				|(flit_sel_in_ivc & flit_head_out_ivc);
	   else
	     assign flit_head = |(flit_sel_in_ivc & flit_head_out_ivc);
	   
	   wire flit_head_s, flit_head_q;
	   assign flit_head_s = flit_head;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_headq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
	      .d(flit_head_s),
	      .q(flit_head_q));
	   
	   assign flit_head_prev = flit_head_q;
	   	      
	   wire [0:flit_data_width-1] flit_data;
	   
	   if(num_vcs == 1)
	     begin
		assign flit_sent_prev_ivc = flit_sent_q;
		assign flit_data = llu_flit_data_ivc;
	     end
	   else if(num_vcs > 1)
	     begin
		
		wire [0:num_vcs-1] flit_sel_ivc_s, flit_sel_ivc_q;
		assign flit_sel_ivc_s = flit_sel_ivc;
		c_dff
		  #(.width(num_vcs),
		    .reset_type(reset_type))
		flit_sel_ivcq
		  (.clk(clk),
		   .reset(reset),
		   .active(alloc_active),
		   .d(flit_sel_ivc_s),
		   .q(flit_sel_ivc_q));
		
		assign flit_sent_prev_ivc
		  = {num_vcs{flit_sent_q}} & flit_sel_ivc_q;
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_data_width))
		flit_data_sel
		  (.select(flit_sel_ivc_q),
		   .data_in(llu_flit_data_ivc),
		   .data_out(flit_data));
		
	     end
	   
	   assign flit_data_out = flit_data;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate outgoing flow control signals
   //---------------------------------------------------------------------------
   
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fco
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .fc_event_valid_in(flit_sent),
      .fc_event_sel_in_ivc(flit_sel_ivc),
      .flow_ctrl_out(flow_ctrl_out));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_vcs*5-1] errors_s, errors_q;
	   assign errors_s = errors_ivc;
	   c_err_rpt
	     #(.num_errors(num_vcs*5),
	       .capture_mode(error_capture_mode),
	       .reset_type(reset_type))
	   chk
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .errors_in(errors_s),
	      .errors_out(errors_q));
	   
	   assign error = |errors_q;
	   
	end
      else
	assign error = 1'b0;
      
   endgenerate
   
endmodule
