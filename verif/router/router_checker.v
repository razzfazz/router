// $Id$

/*
Copyright (c) 2007-2010, Trustees of The Leland Stanford Junior University
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

module router_checker
  (clk, reset, router_address, channel_in_ip, channel_out_op, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // number of bits required for flit buffer addresses
   localparam flit_buffer_idx_width = clogb(num_flits_per_vc);
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // width required to select individual resource class
   localparam resource_class_idx_width = clogb(num_resource_classes);
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 1;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // enable lookahead routing
   parameter lookahead_routing = 1;
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = lookahead_routing ? (port_idx_width + resource_class_idx_width) : 0;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming channels
   input [0:num_ports*channel_width-1] channel_in_ip;
   
   // outgoing channels
   input [0:num_ports*channel_width-1] channel_out_op;
   
   // error indicator
   output 			       error;
   wire 			       error;
   
   wire [0:num_ports*num_vcs*num_ports-1] match_ip_ivc_op;
   
   wire [0:num_ports*num_vcs-1] 	  ref_valid_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	  ref_head_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	  ref_tail_ip_ivc;
   wire [0:num_ports*num_vcs*flit_data_width-1] ref_data_ip_ivc;
   wire [0:num_ports*num_vcs*port_idx_width-1] 	ref_port_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	ref_vcs_ip_ivc;
   
   wire [0:num_ports-1] 			rff_errors_ip;
   
   genvar 					ip;
   
   generate
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // extract signals for this input port
	   //-------------------------------------------------------------------
	   
	   wire [0:channel_width-1] channel_in;
	   assign channel_in
	     = channel_in_ip[ip*channel_width:(ip+1)*channel_width-1];
	   
	   wire 			  flit_valid;
	   wire 			  flit_head;
	   wire 			  flit_tail;
	   wire [0:flit_data_width-1] 	  flit_data;
	   wire [0:num_vcs-1] 		  sel_ivc;
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
	      .active(1'b1),
	      .channel_in(channel_in),
	      .flit_valid_out(flit_valid),
	      .flit_head_out(flit_head),
	      .flit_tail_out(flit_tail),
	      .flit_data_out(flit_data),
	      .flit_sel_out_ivc(sel_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // compute destination port and VC mask
	   //-------------------------------------------------------------------
	   
	   wire [0:num_message_classes*num_resource_classes-1] sel_mc_irc;
	   c_mat_mult
	     #(.dim1_width(num_message_classes*num_resource_classes),
	       .dim2_width(num_vcs_per_class),
	       .dim3_width(1),
	       .prod_op(`BINARY_OP_AND),
	       .sum_op(`BINARY_OP_OR))
	   sel_mc_irc_mmult
	     (.input_a(sel_ivc),
	      .input_b({num_vcs_per_class{1'b1}}),
	      .result(sel_mc_irc));
	   
	   wire [0:num_message_classes-1] 		       sel_mc;
	   c_mat_mult
	     #(.dim1_width(num_message_classes),
	       .dim2_width(num_resource_classes),
	       .dim3_width(1),
	       .prod_op(`BINARY_OP_AND),
	       .sum_op(`BINARY_OP_OR))
	   sel_mc_mmult
	     (.input_a(sel_mc_irc),
	      .input_b({num_resource_classes{1'b1}}),
	      .result(sel_mc));
	   
	   wire [0:num_resource_classes*num_message_classes-1] sel_irc_mc;
	   c_interleave
	     #(.width(num_message_classes*num_resource_classes),
	       .num_blocks(num_message_classes))
	   sel_irc_mc_intl
	     (.data_in(sel_mc_irc),
	      .data_out(sel_irc_mc));
	   
	   wire [0:num_resource_classes-1] 		       sel_irc;
	   c_mat_mult
	     #(.dim1_width(num_resource_classes),
	       .dim2_width(num_message_classes),
	       .dim3_width(1),
	       .prod_op(`BINARY_OP_AND),
	       .sum_op(`BINARY_OP_OR))
	   sel_irc_mmult
	     (.input_a(sel_irc_mc),
	      .input_b({num_message_classes{1'b1}}),
	      .result(sel_irc));
	   
	   
	   // compute destination port
	   
	   wire [0:header_info_width-1] 		       header_info_in;
	   assign header_info_in = flit_data[0:header_info_width-1];
	   
	   wire [0:route_info_width-1] 			       route_info;
	   assign route_info = header_info_in[la_route_info_width:
					      la_route_info_width+
					      route_info_width-1];
	   
	   wire [0:num_ports-1] 			       route_op;
	   wire [0:num_resource_classes-1] 		       route_orc;
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
	     (.router_address(router_address),
	      .sel_mc(sel_mc),
	      .sel_irc(sel_irc),
	      .route_info(route_info),
	      .route_op(route_op),
	      .route_orc(route_orc));
	   
	   wire [0:port_idx_width-1] 			       route_port;
	   c_encode
	     #(.num_ports(num_ports))
	   route_port_enc
	     (.data_in(route_op),
	      .data_out(route_port));
	   
	   wire [0:num_resource_classes-1] sel_orc;
	   assign sel_orc = route_orc;
	   
	   
	   // determine candidate output VCs
	   
	   wire [0:num_resource_classes*num_vcs_per_class-1] sel_orc_ocvc;
	   c_mat_mult
	     #(.dim1_width(num_resource_classes),
	       .dim2_width(1),
	       .dim3_width(num_vcs_per_class))
	   sel_orc_ocvc_mmult
	     (.input_a(sel_orc),
	      .input_b({num_vcs_per_class{1'b1}}),
	      .result(sel_orc_ocvc));
	   
	   wire [0:num_vcs-1] 				     route_ovc;
	   c_mat_mult
	     #(.dim1_width(num_message_classes),
	       .dim2_width(1),
	       .dim3_width(num_resource_classes*num_vcs_per_class))
	   route_ovc_mmult
	     (.input_a(sel_mc),
	      .input_b(sel_orc_ocvc),
	      .result(route_ovc));
	   
	   
	   //-------------------------------------------------------------------
	   // update header info
	   //-------------------------------------------------------------------
	   
	   wire [0:header_info_width-1] header_info_out;
	   
	   if(lookahead_routing)
	     begin
		
		// generate lookahead routing information
		
		wire [0:router_addr_width-1] next_router_address;
		rtr_next_hop_addr
		  #(.num_routers_per_dim(num_routers_per_dim),
		    .num_dimensions(num_dimensions),
		    .num_nodes_per_router(num_nodes_per_router),
		    .connectivity(connectivity))
		nha
		  (.router_address(router_address),
		   .route_port(route_port),
		   .next_router_address(next_router_address));
		
		wire [0:num_ports-1] 	     next_route_op;
		wire [0:num_resource_classes-1] next_route_orc;
		rtr_routing_logic
		  #(.num_message_classes(num_message_classes),
		    .num_resource_classes(num_resource_classes),
		    .num_routers_per_dim(num_routers_per_dim),
		    .num_dimensions(num_dimensions),
		    .num_nodes_per_router(num_nodes_per_router),
		    .connectivity(connectivity),
		    .routing_type(routing_type),
		    .dim_order(dim_order))
		nrtl
		  (.router_address(next_router_address),
		   .sel_mc(sel_mc),
		   .sel_irc(sel_orc),
		   .route_info(route_info),
		   .route_op(next_route_op),
		   .route_orc(next_route_orc));
		
		wire [0:port_idx_width-1] 	next_route_port;
		c_encode
		  #(.num_ports(num_ports))
		next_route_port_enc
		  (.data_in(next_route_op),
		   .data_out(next_route_port));
		
		wire [0:la_route_info_width-1] 	la_route_info;
		assign la_route_info[0:port_idx_width-1] = next_route_port;
		
		if(num_resource_classes > 1)
		  begin
		     
		     wire [0:resource_class_idx_width-1] next_route_rcsel;
		     c_encode
		       #(.num_ports(num_resource_classes))
		     next_route_rcsel_enc
		       (.data_in(next_route_orc),
			.data_out(next_route_rcsel));
		     
		     assign la_route_info[port_idx_width:
					  port_idx_width+
					  resource_class_idx_width-1]
		       = next_route_rcsel;
		     
		  end
		
		assign header_info_out[0:la_route_info_width-1] = la_route_info;
		
	     end
	   
	   assign header_info_out[la_route_info_width:header_info_width-1]
	     = header_info_in[la_route_info_width:header_info_width-1];
	   
	   
	   //-------------------------------------------------------------------
	   // store incoming flits with information about expected output and 
	   // candidate VCs in per-VC FIFOs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*2-1] 	       rff_errors_ivc;
	   
	   genvar 			       ivc;
	   
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		wire sel;
		assign sel = sel_ivc[ivc];
		
		
		// save destination port for subsequent body and tail flits
		
		wire [0:port_idx_width-1] dest_port_s, dest_port_q;
		assign dest_port_s
		  = (flit_valid & flit_head & sel) ? route_port : dest_port_q;
		c_dff
		  #(.width(port_idx_width),
		    .reset_type(reset_type))
		dest_portq
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .d(dest_port_s),
		   .q(dest_port_q));
		
		
		// save candidate VCs for subsequent body and tail flits
		
		wire [0:num_vcs-1] 	  dest_ovc_s, dest_ovc_q;
		assign dest_ovc_s
		  = (flit_valid & flit_head & sel) ? route_ovc : dest_ovc_q;
		c_dff
		  #(.width(num_vcs),
		    .reset_type(reset_type))
		dest_ovcq
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .d(dest_ovc_s),
		   .q(dest_ovc_q));
		
		
		// reference FIFO
		
		wire 			  push;
		assign push = flit_valid & sel;
		
		wire 			  match;
		
		wire 			  pop;
		assign pop = match;
		
		wire [0:(flit_data_width+2+
			 port_idx_width+num_vcs)-1] rff_push_data;
		assign rff_push_data[0:header_info_width-1]
		  = flit_head ? header_info_out : header_info_in;
		assign rff_push_data[header_info_width:flit_data_width-1]
		  = flit_data[header_info_width:flit_data_width-1];
		assign rff_push_data[flit_data_width] = flit_head;
		assign rff_push_data[flit_data_width+1] = flit_tail;
		assign rff_push_data[flit_data_width+2:
				     flit_data_width+2+port_idx_width-1]
		  = dest_port_s;
		assign rff_push_data[flit_data_width+2+port_idx_width:
				     flit_data_width+2+port_idx_width+num_vcs-1]
		  = dest_ovc_s;
		
		wire [0:(flit_data_width+2+
			 port_idx_width+num_vcs)-1] rff_pop_data;
		wire 				    rff_almost_full;
		wire 				    rff_full;
		wire 				    rff_almost_empty;
		wire 				    rff_empty;
		wire [0:1] 			    rff_errors;
		c_fifo
		  #(.depth(num_flits_per_vc),
		    .width(flit_data_width+2+port_idx_width+num_vcs),
		    .reset_type(reset_type))
		rff
		  (.clk(clk),
		   .reset(reset),
		   .push_active(1'b1),
		   .pop_active(1'b1),
		   .push(push),
		   .pop(pop),
		   .push_data(rff_push_data),
		   .pop_data(rff_pop_data),
		   .almost_empty(rff_almost_empty),
		   .empty(rff_empty),
		   .almost_full(rff_almost_full),
		   .full(rff_full),
		   .errors(rff_errors));
		
		assign rff_errors_ivc[ivc*2:(ivc+1)*2-1] = rff_errors;
		
		
		// generate reference bit patterns
		
		wire [0:flit_data_width-1] ref_data;
		assign ref_data = rff_pop_data[0:flit_data_width-1];
		
		wire 			   ref_head;
		assign ref_head = rff_pop_data[flit_data_width];
		
		wire 			   ref_tail;
		assign ref_tail = rff_pop_data[flit_data_width+1];
		
		wire [0:port_idx_width-1]  ref_port;
		assign ref_port
		  = rff_pop_data[flit_data_width+2:
				 flit_data_width+2+port_idx_width-1];
		
		wire [0:num_vcs-1] 	   ref_sel_ovc;
		assign ref_sel_ovc
		  = rff_pop_data[flit_data_width+2+port_idx_width:
				 flit_data_width+2+port_idx_width+num_vcs-1];
		
		
		// extract observed bit patterns
		
		wire [0:channel_width-1]   check_channel;
		assign check_channel
		  = channel_out_op[ref_port*channel_width +: channel_width];
		
		wire 			   check_valid;
		wire 			   check_head;
		wire 			   check_tail;
		wire [0:flit_data_width-1] check_data;
		wire [0:num_vcs-1] 	   check_sel_ivc;
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
		   .active(1'b1),
		   .channel_in(check_channel),
		   .flit_valid_out(check_valid),
		   .flit_head_out(check_head),
		   .flit_tail_out(check_tail),
		   .flit_data_out(check_data),
		   .flit_sel_out_ivc(check_sel_ivc));
		
		wire 			     match_data;
		assign match_data = (ref_data == check_data);
		
		wire 			     match_head;
		assign match_head = (ref_head == check_head);
		
		wire 			     match_tail;
		assign match_tail = (ref_tail == check_tail);
		
		wire 			     match_vcs;
		assign match_vcs = |(ref_sel_ovc & check_sel_ivc);
		
		// check only if output is active and FIFO contains data
		assign match = check_valid & ~rff_empty & 
			       match_head & match_tail & match_data & match_vcs;
		
		
		// indicate which port matched
		
		wire [0:num_ports-1] 	     port_mask;
		c_decode
		  #(.num_ports(num_ports))
		port_mask_dec
		  (.data_in(ref_port),
		   .data_out(port_mask));
		
		wire [0:num_ports-1] 	     match_op;
		assign match_op = {num_ports{match}} & port_mask;
		
		assign match_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				       (ip*num_vcs+ivc+1)*num_ports-1]
			 = match_op;
		
		// determine head-of-line expected flits for each VC
		assign ref_valid_ip_ivc[ip*num_vcs+ivc] = ~rff_empty;
		assign ref_head_ip_ivc[ip*num_vcs+ivc] = ref_head;
		assign ref_tail_ip_ivc[ip*num_vcs+ivc] = ref_tail;
		assign ref_data_ip_ivc[(ip*num_vcs+ivc)*flit_data_width:
				       (ip*num_vcs+ivc+1)*flit_data_width-1]
			 = ref_data;
		assign ref_port_ip_ivc[(ip*num_vcs+ivc)*port_idx_width:
				       (ip*num_vcs+ivc+1)*port_idx_width-1]
			 = ref_port;
		assign ref_vcs_ip_ivc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1]
			 = ref_sel_ovc;
		
	     end
	   
	   if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	     begin
		
		// synopsys translate_off
		
		integer i;
		
		always @(posedge clk)
		  begin
		     
		     for(i = 0; i < num_vcs; i = i + 1)
		       begin
			  
			  if(rff_errors_ivc[i*2])
			    $display({"ERROR: Reference FIFO underflow at ", 
				      "port %d, VC %d."}, ip, i);
			  
			  if(rff_errors_ivc[i*2+1])
			    $display({"ERROR: Reference FIFO overflow at ", 
				      "port %d, VC %d."}, ip, i);
			  
		       end
		     
		  end
		// synopsys translate_on
		
		wire [0:num_vcs*2-1] errors_s, errors_q;
		assign errors_s = rff_errors_ivc;
		c_err_rpt
		  #(.num_errors(num_vcs*2),
		    .capture_mode(error_capture_mode),
		    .reset_type(reset_type))
		chk
		  (.clk(clk),
		   .reset(reset),
		   .active(1'b1),
		   .errors_in(errors_s),
		   .errors_out(errors_q));
		
		assign rff_errors_ip[ip] = |errors_q;
		
	     end
	   else
	     assign rff_errors_ip[ip] = 1'b0;
	   
	   
	end
      
   endgenerate
   
   wire [0:num_ports-1] 	   flit_valid_out_op;
   
   // summary signal indicating if any input VC matched the flit at each output
   wire [0:num_ports-1] 	   match_op;
   c_binary_op
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports),
       .op(`BINARY_OP_OR))
   match_op_or
     (.data_in(match_ip_ivc_op),
      .data_out(match_op));
   
   // unmatched flits indicate something went wrong
   wire [0:num_ports-1] 	   check_error_op;
   assign check_error_op = (flit_valid_out_op & ~match_op);
   
   wire [0:num_ports-1] 	   x_error_op;
   
   genvar 			   op;
   
   generate
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:channel_width-1] channel_out;
	   assign channel_out
	     = channel_out_op[op*channel_width:(op+1)*channel_width-1];
	   
	   wire 		    flit_valid_out;
	   wire 		    flit_head_out;
	   wire 		    flit_tail_out;
	   wire [0:flit_data_width-1] flit_data_out;
	   wire [0:num_vcs-1] 	      flit_sel_out_ivc;
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
	      .active(1'b1),
	      .channel_in(channel_out),
	      .flit_valid_out(flit_valid_out),
	      .flit_head_out(flit_head_out),
	      .flit_tail_out(flit_tail_out),
	      .flit_data_out(flit_data_out),
	      .flit_sel_out_ivc(flit_sel_out_ivc));
	   
	   assign flit_valid_out_op[op] = flit_valid_out;
	   
	   wire 			x_error;
	   assign x_error
	     = (flit_valid_out === 1'bx) ||
	       ((flit_valid_out === 1'b1) &&
		((flit_head_out === 1'bx) ||
		 (flit_tail_out === 1'bx) ||
		 (^flit_data_out === 1'bx) ||
		 (^flit_sel_out_ivc === 1'bx)));

	   assign x_error_op[op] = x_error;
	   
	   // synopsys translate_off
	   
	   integer 			x;
	   
	   always @(posedge clk)
	     begin
		if(check_error_op[op])
		  begin
		     $display("check error: op=%d, cyc=%d", op, $time);
		     $display("head=%b, tail=%b, vcs=%b, data=%x",
			      flit_head_out,
			      flit_tail_out,
			      flit_sel_out_ivc,
			      flit_data_out);
		     $display("expected flits:");
		     for(x = 0; x < num_ports*num_vcs; x = x + 1)
		       begin
			  if(ref_valid_ip_ivc[x])
			    $display({"ip=%d,ivc=%d,head=%b,tail=%b,data=%x,",
				      "op=%d,vcs=%b"},
				     x / num_vcs, x % num_vcs,
				     ref_head_ip_ivc[x],
				     ref_tail_ip_ivc[x],
				     ref_data_ip_ivc[x*flit_data_width +: 
						     flit_data_width],
				     ref_port_ip_ivc[x*port_idx_width +: 
						     port_idx_width],
				     ref_vcs_ip_ivc[x*num_vcs +: num_vcs]);
		       end
		  end
		if(x_error)
		  begin
		     $display("X value error: op=%d, cyc=%d", op, $time);
		     $display("valid=%b, head=%b, tail=%b, vcs=%b, data=%x",
			      flit_valid_out,
			      flit_head_out,
			      flit_tail_out,
			      flit_sel_out_ivc,
			      flit_data_out);
		  end
	     end
	   
	   // synopsys translate_on
   
	end
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   // synopsys translate_off
	   
	   integer 			  i;
	   
	   always @(posedge clk)
	     begin
		
		for(i = 0; i < num_ports; i = i + 1)
		  begin
		     if(rff_errors_ip[i])
		       $display({"ERROR: Reference FIFO error detected at ", 
				 "input port %d."}, i);
		  end
		
	     end
	   // synopsys translate_on
	   
	   wire [0:3*num_ports-1] errors_s, errors_q;
	   assign errors_s = {rff_errors_ip, check_error_op, x_error_op};
	   c_err_rpt
	     #(.num_errors(3*num_ports),
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
