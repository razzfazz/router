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

//==============================================================================
// input port controller
//==============================================================================

module rtr_ip_ctrl_mac
  (clk, reset, router_address, channel_in, route_out_ivc_op, route_out_ivc_orc, 
   flit_valid_out_ivc, flit_head_out_ivc, flit_tail_out_ivc, flit_data_out, 
   flit_sel_in_ivc, flit_sent_in, flow_ctrl_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
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
   
   // enable lookahead routing
   parameter lookahead_routing = 1;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for head/tail register file
   parameter htff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for header data FIFO register file
   parameter hdff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 1;
   
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
   
   // width required for routing information for a single hop
   localparam hop_route_info_width = port_idx_width + resource_class_idx_width;
   
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
   localparam la_route_info_width
     = lookahead_routing ? hop_route_info_width : 0;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
   // required address size for a single VC's buffer
   localparam fbc_addr_width = clogb(num_flits_per_vc);
   
   // required address width for flit buffer
   localparam fbf_addr_width = clogb(num_vcs*num_flits_per_vc);
   
   // additional address bits to add to addresses from FIFO controller
   localparam fbc_extra_addr_width = fbf_addr_width - fbc_addr_width;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming channel
   input [0:channel_width-1] 	 channel_in;
   
   // selected output port
   output [0:num_vcs*num_ports-1] route_out_ivc_op;
   wire [0:num_vcs*num_ports-1]   route_out_ivc_op;
   
   // selected output resource class
   output [0:num_vcs*num_resource_classes-1] route_out_ivc_orc;
   wire [0:num_vcs*num_resource_classes-1]   route_out_ivc_orc;
   
   // flit is present
   output [0:num_vcs-1] 		     flit_valid_out_ivc;
   wire [0:num_vcs-1] 			     flit_valid_out_ivc;
   
   // flit is head flit
   output [0:num_vcs-1] 		     flit_head_out_ivc;
   wire [0:num_vcs-1] 			     flit_head_out_ivc;
   
   // flit is tail flit
   output [0:num_vcs-1] 		     flit_tail_out_ivc;
   wire [0:num_vcs-1] 			     flit_tail_out_ivc;
   
   // outgoing flit data
   output [0:flit_data_width-1] 	     flit_data_out;
   wire [0:flit_data_width-1] 		     flit_data_out;
   
   // indicate which VC is candidate for being sent
   input [0:num_vcs-1] 			     flit_sel_in_ivc;
   
   // flit was sent
   input 				     flit_sent_in;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] 	     flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 		     flow_ctrl_out;
   
   // internal error condition detected
   output 				     error;
   wire 				     error;
   
   
   //---------------------------------------------------------------------------
   // channel input staging
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 			     fbc_full_ivc;
   
   wire 				     chi_active;
   assign chi_active = ~&fbc_full_ivc;
   
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
   
   wire [0:num_vcs-1] 			     flit_sent_in_ivc;
   assign flit_sent_in_ivc = {num_vcs{flit_sent_in}} & flit_sel_in_ivc;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:hop_route_info_width-1] 	     rtl_hop_route_info;
   wire [0:num_ports-1] 		     rtl_route_op;
   wire [0:port_idx_width-1] 		     rtl_route_port;
   wire [0:num_resource_classes-1] 	     rtl_route_orc;
   wire [0:flit_data_width-1] 		     fbf_write_data;
   
   generate
      
      begin:rtl
	 
	 // extract header information from header data
	 wire [0:header_info_width-1] 	     header_info_in;
	 assign header_info_in = chi_flit_data[0:header_info_width-1];
	 
	 wire [0:route_info_width-1] 		     route_info_in;
	 assign route_info_in
	   = header_info_in[la_route_info_width:
			    la_route_info_width+route_info_width-1];
	 
	 wire [0:num_packet_classes-1] 		     chi_flit_sel_ipc;
	 c_mat_mult
	   #(.dim1_width(num_message_classes*num_resource_classes),
	     .dim2_width(num_vcs_per_class),
	     .dim3_width(1),
	     .prod_op(`BINARY_OP_AND),
	     .sum_op(`BINARY_OP_OR))
	 chi_flit_sel_ipc_mmult
	   (.input_a(chi_flit_sel_ivc),
	    .input_b({num_vcs_per_class{1'b1}}),
	    .result(chi_flit_sel_ipc));
	 
	 wire [0:num_message_classes-1] 	     chi_flit_sel_mc;
	 c_mat_mult
	   #(.dim1_width(num_message_classes),
	     .dim2_width(num_resource_classes),
	     .dim3_width(1),
	     .prod_op(`BINARY_OP_AND),
	     .sum_op(`BINARY_OP_OR))
	 chi_flit_sel_mc_mmult
	   (.input_a(chi_flit_sel_ipc),
	    .input_b({num_resource_classes{1'b1}}),
	    .result(chi_flit_sel_mc));
	 
	 if(lookahead_routing)
	   begin
	      
	      wire [0:la_route_info_width-1] la_route_info_in;
	      assign la_route_info_in = header_info_in[0:la_route_info_width-1];
	      
	      assign rtl_hop_route_info = la_route_info_in;
	      
	      assign rtl_route_port = la_route_info_in[0:port_idx_width-1];
	      
	      c_decode
		#(.num_ports(num_ports))
	      rtl_route_op_dec
		(.data_in(rtl_route_port),
		 .data_out(rtl_route_op));
	      
	      if(num_resource_classes == 1)
		assign rtl_route_orc = 1'b1;
	      else
		begin
		   
		   wire [0:resource_class_idx_width-1] route_rcsel;
		   assign route_rcsel
		     = la_route_info_in[port_idx_width:
					port_idx_width+
					resource_class_idx_width-1];
		   
		   c_decode
		     #(.num_ports(num_resource_classes))
		   rtl_route_orc_dec
		     (.data_in(route_rcsel),
		      .data_out(rtl_route_orc));
		   
		end
	      
	      wire [0:router_addr_width-1] 	       nha_router_address;
	      rtr_next_hop_addr
		#(.num_resource_classes(num_resource_classes),
		  .num_routers_per_dim(num_routers_per_dim),
		  .num_dimensions(num_dimensions),
		  .num_nodes_per_router(num_nodes_per_router),
		  .connectivity(connectivity),
		  .routing_type(routing_type))
	      nha
		(.router_address(router_address),
		 .route_info(route_info_in),
		 .la_route_info(la_route_info_in),
		 .next_router_address(nha_router_address));
	      
	      wire [0:num_ports-1] 		       nrtl_route_op;
	      wire [0:num_resource_classes-1] 	       nrtl_route_orc;
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
		(.router_address(nha_router_address),
		 .sel_mc(chi_flit_sel_mc),
		 .sel_irc(rtl_route_orc),
		 .route_info(route_info_in),
		 .route_op(nrtl_route_op),
		 .route_orc(nrtl_route_orc));
	      
	      wire [0:port_idx_width-1] 	       nrtl_route_port;
	      c_encode
		#(.num_ports(num_ports))
	      nrtl_route_port_enc
		(.data_in(nrtl_route_op),
		 .data_out(nrtl_route_port));
	      
	      wire [0:la_route_info_width-1] 	       la_route_info_out;
	      assign la_route_info_out[0:port_idx_width-1] = nrtl_route_port;
	      
	      if(num_resource_classes > 1)
		begin
		   
		   wire [0:resource_class_idx_width-1] nrtl_route_rcsel;
		   c_encode
		     #(.num_ports(num_resource_classes))
		   nrtl_route_rcsel_enc
		     (.data_in(nrtl_route_orc),
		      .data_out(nrtl_route_rcsel));
		   
		   assign la_route_info_out[port_idx_width:
					    port_idx_width+
					    resource_class_idx_width-1]
		     = nrtl_route_rcsel;
		
		end
	      
	      // update lookahead routing information for head flits
	      assign fbf_write_data[0:la_route_info_width-1]
		= chi_flit_head ? la_route_info_out : la_route_info_in;
	      
	   end
	 else
	   begin
	      
	      wire [0:num_resource_classes-1] chi_flit_sel_irc;
	      c_binary_op
		#(.num_ports(num_message_classes),
		  .width(num_resource_classes),
		  .op(`BINARY_OP_OR))
	      chi_flit_sel_irc_or
		(.data_in(chi_flit_sel_ipc),
		 .data_out(chi_flit_sel_irc));
	      
	      rtr_routing_logic
		#(.num_message_classes(num_message_classes),
		  .num_resource_classes(num_resource_classes),
		  .num_routers_per_dim(num_routers_per_dim),
		  .num_dimensions(num_dimensions),
		  .num_nodes_per_router(num_nodes_per_router),
		  .connectivity(connectivity),
		  .routing_type(routing_type),
		  .dim_order(dim_order))
	      crtl
		(.router_address(router_address),
		 .sel_mc(chi_flit_sel_mc),
		 .sel_irc(chi_flit_sel_irc),
		 .route_info(route_info_in),
		 .route_op(rtl_route_op),
		 .route_orc(rtl_route_orc));
	      
	      c_encode
		#(.num_ports(num_ports))
	      rtl_route_port_enc
		(.data_in(rtl_route_op),
		 .data_out(rtl_route_port));
	      
	      assign rtl_hop_route_info[0:port_idx_width-1] = rtl_route_port;
	      
	      if(num_resource_classes > 1)
		begin
		   
		   wire [0:resource_class_idx_width-1] rtl_route_rcsel;
		   c_encode
		     #(.num_ports(num_resource_classes))
		   rtl_route_rcsel_enc
		     (.data_in(rtl_route_orc),
		      .data_out(rtl_route_rcsel));
		   
		   assign rtl_hop_route_info[port_idx_width:
					     port_idx_width+
					     resource_class_idx_width-1]
		     = rtl_route_rcsel;
		   
		end
	      
	   end
	 
      end
      
   endgenerate
   
   assign fbf_write_data[la_route_info_width:flit_data_width-1]
     = chi_flit_data[la_route_info_width:flit_data_width-1];
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*fbf_addr_width-1] 		    fbc_push_addr_ivc;
   wire [0:num_vcs*fbf_addr_width-1] 		    fbc_pop_addr_ivc;
   wire [0:num_vcs-1] 				    fbc_empty_ivc;
   wire [0:num_vcs*9-1] 			    errors_ivc;
   
   genvar 					    ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   //-------------------------------------------------------------------
	   // connect inputs and outputs
	   //-------------------------------------------------------------------
	   
	   wire chi_flit_valid;
	   assign chi_flit_valid = chi_flit_valid_ivc[ivc];
	   
	   wire flit_sent_in;
	   assign flit_sent_in = flit_sent_in_ivc[ivc];
	   
	   wire flit_valid_out;
	   assign flit_valid_out_ivc[ivc] = flit_valid_out;
	   
	   wire flit_head_out;
	   assign flit_head_out_ivc[ivc] = flit_head_out;
	   
	   wire flit_tail_out;
	   assign flit_tail_out_ivc[ivc] = flit_tail_out;
	   
	   wire fbc_empty;
	   assign fbc_empty_ivc[ivc] = fbc_empty;
	   
	   wire fbc_full;
	   assign fbc_full_ivc[ivc] = fbc_full;
	   
	   wire [0:fbf_addr_width-1] fbc_push_addr;
	   assign fbc_push_addr_ivc[ivc*fbf_addr_width:(ivc+1)*fbf_addr_width-1]
	     = fbc_push_addr;
	   
	   wire [0:fbf_addr_width-1] fbc_pop_addr;
	   assign fbc_pop_addr_ivc[ivc*fbf_addr_width:(ivc+1)*fbf_addr_width-1]
	     = fbc_pop_addr;
	   
	   wire [0:num_ports-1]      route_out_op;
	   assign route_out_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
	     = route_out_op;
	   
	   wire [0:num_resource_classes-1] route_out_orc;
	   assign route_out_ivc_orc[ivc*num_resource_classes:
				    (ivc+1)*num_resource_classes-1]
	     = route_out_orc;
	   
	   wire [0:8] 			   errors;
	   assign errors_ivc[ivc*9:(ivc+1)*9-1] = errors;
	   
	   
	   //-------------------------------------------------------------------
	   // flit buffer control
	   //-------------------------------------------------------------------
	   
	   wire 			   push_active;
	   assign push_active = chi_flit_valid;
	   
	   assign flit_valid_out = chi_flit_valid | ~fbc_empty;
	   
	   wire 			   pop_active;
	   assign pop_active = flit_valid_out;
	   
	   wire 			   fbc_push;
	   assign fbc_push = chi_flit_valid;
	   
	   wire 			   fbc_pop;
	   assign fbc_pop = flit_sent_in;
	   
	   wire 			   fbc_almost_empty;
	   wire 			   fbc_almost_full;
	   wire [0:1] 			   fbc_errors;
	   c_fifo_ctrl
	     #(.depth(num_flits_per_vc),
	       .extra_addr_width(fbc_extra_addr_width),
	       .offset(ivc*num_flits_per_vc),
	       .reset_type(reset_type))
	   fbc
	     (.clk(clk),
	      .reset(reset),
	      .push_active(push_active),
	      .pop_active(pop_active),
	      .push(fbc_push),
	      .pop(fbc_pop),
	      .push_addr(fbc_push_addr),
	      .pop_addr(fbc_pop_addr),
	      .almost_empty(fbc_almost_empty),
	      .empty(fbc_empty),
	      .almost_full(fbc_almost_full),
	      .full(fbc_full),
	      .errors(fbc_errors));
	   
	   wire 			   error_fbc_underflow;
	   assign error_fbc_underflow = fbc_errors[0];
	   
	   wire 			   error_fbc_overflow;
	   assign error_fbc_overflow = fbc_errors[1];
	   
	   
	   //-------------------------------------------------------------------
	   // track routing information for frontmost packet
	   //-------------------------------------------------------------------
	   
	   wire 			   flags_active;
	   assign flags_active = flit_valid_out;
	   
	   wire 			   head_received;
	   assign head_received = chi_flit_valid & chi_flit_head;
	   
	   wire 			   tail_received;
	   assign tail_received = chi_flit_valid & chi_flit_tail;
	   
	   wire 			   tail_sent;
	   assign tail_sent = flit_sent_in & flit_tail_out;
	   
	   wire 			   hdr_valid;
	   wire 			   hdff_empty;
	   
	   wire 			   hdff_push;
	   assign hdff_push
	     = head_received & hdr_valid & (~tail_sent | ~hdff_empty);
	   
	   wire 			   hdff_pop;
	   assign hdff_pop = tail_sent & ~hdff_empty;
	   
	   wire [0:hop_route_info_width-1] hdff_hop_route_info;
	   wire 			   error_hdff_underflow;
	   wire 			   error_hdff_overflow;
	   
	   if(num_packets_per_vc > 1)
	     begin
		
		wire [0:hop_route_info_width-1] hdff_push_data;
		assign hdff_push_data = rtl_hop_route_info;
		
		wire [0:hop_route_info_width-1] hdff_pop_data;
		wire 				hdff_almost_full;
		wire 				hdff_full;
		wire 				hdff_almost_empty;
		wire [0:1] 			hdff_errors;
		c_fifo
		  #(.depth(num_packets_per_vc - 1),
		    .width(hop_route_info_width),
		    .regfile_type(hdff_regfile_type),
		    .reset_type(reset_type))
		hdff
		  (.clk(clk),
		   .reset(reset),
		   .push_active(push_active),
		   .pop_active(pop_active),
		   .push(hdff_push),
		   .pop(hdff_pop),
		   .push_data(hdff_push_data),
		   .pop_data(hdff_pop_data),
		   .almost_empty(hdff_almost_empty),
		   .empty(hdff_empty),
		   .almost_full(hdff_almost_full),
		   .full(hdff_full),
		   .errors(hdff_errors));
		
		assign hdff_hop_route_info = hdff_pop_data;
		
		assign error_hdff_underflow = hdff_errors[0];
		assign error_hdff_overflow = hdff_errors[1];
		
	     end
	   else if(num_packets_per_vc == 1)
	     begin
		
		assign hdff_empty = 1'b1;
		
		assign hdff_hop_route_info = {hop_route_info_width{1'b0}};
		
		assign error_hdff_underflow = 1'b0;
		assign error_hdff_overflow = 1'b0;
		
	     end
	   
	   wire hdr_valid_s, hdr_valid_q;
	   assign hdr_valid_s = hdr_valid_q ?
				(~tail_sent | ~hdff_empty | head_received) : 
				(chi_flit_valid & ~tail_sent);
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   hdr_validq
	     (.clk(clk),
	      .reset(reset),
	      .active(flags_active),
	      .d(hdr_valid_s),
	      .q(hdr_valid_q));
	   
	   assign hdr_valid = hdr_valid_q;
	   
	   wire error_no_header;
	   assign error_no_header
	     = ~hdr_valid & (~fbc_empty | (chi_flit_valid & ~chi_flit_head));
	   
	   wire [0:hop_route_info_width-1] hop_route_info_muxed;
	   assign hop_route_info_muxed
	     = hdff_empty ? rtl_hop_route_info : hdff_hop_route_info;
	   
	   wire 			   hdr_capture;
	   assign hdr_capture = (~hdr_valid & chi_flit_valid) | 
				(tail_sent & (~hdff_empty | chi_flit_valid));
	   
	   wire [0:hop_route_info_width-1] hdr_hop_route_info_s;
	   wire [0:hop_route_info_width-1] hdr_hop_route_info_q;
	   assign hdr_hop_route_info_s
	     = hdr_capture ? hop_route_info_muxed : hdr_hop_route_info_q;
	   c_dff
	     #(.width(hop_route_info_width),
	       .reset_type(reset_type))
	   hdr_hop_route_infoq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(flags_active),
	      .d(hdr_hop_route_info_s),
	      .q(hdr_hop_route_info_q));
	   
	   wire [0:hop_route_info_width-1] hdr_hop_route_info;
	   assign hdr_hop_route_info = hdr_hop_route_info_q;
	   
	   wire [0:port_idx_width-1] 	   hdr_route_port;
	   assign hdr_route_port = hdr_hop_route_info[0:port_idx_width-1];
	   
	   wire [0:num_ports-1] 	   hdr_route_op;
	   c_decode
	     #(.num_ports(num_ports))
	   hdr_route_op_dec
	     (.data_in(hdr_route_port),
	      .data_out(hdr_route_op));
	   
	   wire [0:num_ports-1] 	   route_raw_op;
	   assign route_raw_op = hdr_valid ? hdr_route_op : rtl_route_op;
	   
	   wire [0:num_resource_classes-1] route_raw_orc;
	   if(num_resource_classes == 1)
	     assign route_raw_orc = 1'b1;
	   else if(num_resource_classes > 1)
	     begin
		
		wire [0:resource_class_idx_width-1] hdr_route_rcsel;
		assign hdr_route_rcsel
		  = hdr_hop_route_info[port_idx_width:
				       port_idx_width+
				       resource_class_idx_width-1];
		
		wire [0:num_resource_classes-1]     hdr_route_orc;
		c_decode
		  #(.num_ports(num_resource_classes))
		hdr_route_orc_dec
		  (.data_in(hdr_route_rcsel),
		   .data_out(hdr_route_orc));
		
		assign route_raw_orc
		  = hdr_valid ? hdr_route_orc : rtl_route_orc;
		
	     end
	   
	   wire [0:1] 				    rf_errors;
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
	     (.route_in_op(route_raw_op),
	      .route_in_orc(route_raw_orc),
	      .route_out_op(route_out_op),
	      .route_out_orc(route_out_orc),
	      .errors(rf_errors));
	   
	   wire 				    route_valid;
	   assign route_valid = hdr_valid | chi_flit_valid;
	   
	   wire 				    error_invalid_port;
	   assign error_invalid_port =  route_valid & rf_errors[0];
	   
	   wire 				    error_invalid_class;
	   assign error_invalid_class = route_valid & rf_errors[1];
	   
	   
	   //-------------------------------------------------------------------
	   // track whether frontmost flit is head or tail
	   //-------------------------------------------------------------------
	   
	   wire 				    error_htff_underflow;
	   wire 				    error_htff_overflow;
	   
	   if(num_packets_per_vc > 1)
	     begin
		
		wire htff_empty;
		
		wire htff_push;
		assign htff_push
		  = chi_flit_valid & ~fbc_empty & (~flit_sent_in | ~htff_empty);
		
		wire htff_pop;
		assign htff_pop = flit_sent_in & ~htff_empty;
		
		wire [0:1] htff_push_data;
		assign htff_push_data[0] = chi_flit_head;
		assign htff_push_data[1] = chi_flit_tail;
		
		wire [0:1] htff_pop_data;
		wire       htff_almost_full;
		wire       htff_full;
		wire       htff_almost_empty;
		wire [0:1] htff_errors;
		c_fifo
		  #(.depth(num_flits_per_vc - 1),
		    .width(2),
		    .regfile_type(htff_regfile_type),
		    .reset_type(reset_type))
		htff
		  (.clk(clk),
		   .reset(reset),
		   .push_active(push_active),
		   .pop_active(pop_active),
		   .push(htff_push),
		   .pop(htff_pop),
		   .push_data(htff_push_data),
		   .pop_data(htff_pop_data),
		   .almost_empty(htff_almost_empty),
		   .empty(htff_empty),
		   .almost_full(htff_almost_full),
		   .full(htff_full),
		   .errors(htff_errors));
		
		wire       htff_flit_head;
		assign htff_flit_head = htff_pop_data[0];
		
		wire       htff_flit_tail;
		assign htff_flit_tail = htff_pop_data[1];
		
		assign error_htff_underflow = htff_errors[0];		
		assign error_htff_overflow = htff_errors[1];
		
		wire 	   flit_head_muxed;
		assign flit_head_muxed
		  = htff_empty ? chi_flit_head : htff_flit_head;
		
		wire 	   flit_tail_muxed;
		assign flit_tail_muxed
		  = htff_empty ? chi_flit_tail : htff_flit_tail;
		
		wire [0:1] flit_flags_muxed;
		assign flit_flags_muxed[0] = flit_head_muxed;
		assign flit_flags_muxed[1] = flit_tail_muxed;
		
		wire       htr_capture;
		assign htr_capture
		  = (fbc_empty & chi_flit_valid) | 
		    (flit_sent_in & (~htff_empty | chi_flit_valid));
		
		wire [0:1] htr_data_s, htr_data_q;
		assign htr_data_s = htr_capture ? flit_flags_muxed : htr_data_q;
		c_dff
		  #(.width(2),
		    .reset_type(reset_type))
		htr_dataq
		  (.clk(clk),
		   .reset(1'b0),
		   .active(flags_active),
		   .d(htr_data_s),
		   .q(htr_data_q));
		
		assign flit_head_out
		  = fbc_empty ? chi_flit_head : htr_data_q[0];
		assign flit_tail_out
		  = fbc_empty ? chi_flit_tail : htr_data_q[1];
		
	     end
	   else
	     begin
		
		wire head_s, head_q;
		assign head_s = (head_q | head_received) & ~flit_sent_in;
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		headq
		  (.clk(clk),
		   .reset(reset),
		   .active(flags_active),
		   .d(head_s),
		   .q(head_q));
		
		assign flit_head_out = fbc_empty ? chi_flit_head : head_q;
		
		wire tail_valid_s, tail_valid_q;
		assign tail_valid_s
		  = (tail_valid_q | tail_received) & ~tail_sent;
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		tail_validq
		  (.clk(clk),
		   .reset(reset),
		   .active(flags_active),
		   .d(tail_valid_s),
		   .q(tail_valid_q));
		
		assign flit_tail_out = fbc_empty ? 
				       chi_flit_tail : 
				       (tail_valid_q & fbc_almost_empty);
		
		assign error_htff_underflow = 1'b0;
		assign error_htff_overflow = 1'b0;
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // error checking
	   //-------------------------------------------------------------------
	   
	   // synopsys translate_off
	   
	   integer   i;
	   
	   always @(posedge clk)
	     begin
		
		if(error_fbc_underflow)
		  $display("ERROR: Flit buffer underflow in module %m.");
		
		if(error_fbc_overflow)
		  $display("ERROR: Flit buffer overflow in module %m.");
		
		if(error_hdff_underflow)
		  $display("ERROR: Head data FIFO underflow in module %m.");
		
		if(error_hdff_overflow)
		  $display("ERROR: Head data FIFO overflow in module %m.");
		
		if(error_htff_underflow)
		  $display("ERROR: Head/tail FIFO underflow in module %m.");
		
		if(error_htff_overflow)
		  $display("ERROR: Head/tail FIFO overflow in module %m.");
		
		if(error_no_header)
		  $display("ERROR: Stray flit received in module %m.");
		
		if(error_invalid_port)
		  $display({"ERROR: Received flit's destination does not ",
			    "match port constraints in module %m."});
		
		if(error_invalid_class)
		  $display({"ERROR: Received flit's destination does not ",
			    "match class constraints in module %m."});
		
	     end
	   
	   // synopsys translate_on
	   
	   assign errors[0] = error_fbc_underflow;
	   assign errors[1] = error_fbc_overflow;
	   assign errors[2] = error_hdff_underflow;
	   assign errors[3] = error_hdff_overflow;
	   assign errors[4] = error_htff_underflow;
	   assign errors[5] = error_htff_overflow;
	   assign errors[6] = error_no_header;
	   assign errors[7] = error_invalid_port;
	   assign errors[8] = error_invalid_class;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire flit_valid_out;
   assign flit_valid_out = chi_flit_valid | ~&fbc_empty_ivc;
   
   wire [0:fbf_addr_width-1] fbc_push_addr;
   wire [0:fbf_addr_width-1] fbc_pop_addr;
   wire 		     fbf_write_enable;
   wire 		     fbf_read_active;
   wire 		     fbf_read_enable;
   wire [0:fbf_addr_width-1] fbf_read_addr;
   wire [0:flit_data_width-1] fbf_read_data;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(fbf_addr_width))
	   fbc_push_addr_sel
	     (.select(chi_flit_sel_ivc),
	      .data_in(fbc_push_addr_ivc),
	      .data_out(fbc_push_addr));
	   
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(fbf_addr_width))
	   fbc_pop_addr_sel
	     (.select(flit_sel_in_ivc),
	      .data_in(fbc_pop_addr_ivc),
	      .data_out(fbc_pop_addr));
	   
	end
      
      // if we only have a single VC, just use the address as is
      else
	begin
	   assign fbc_push_addr = fbc_push_addr_ivc;
	   assign fbc_pop_addr = fbc_pop_addr_ivc;
	end
      
      if(explicit_pipeline_register)
	begin
	   
	   wire fbf_bypass;
	   assign fbf_bypass = |(flit_sel_in_ivc & fbc_empty_ivc);
	   
	   assign fbf_write_enable
	     = chi_flit_valid & ~(fbf_bypass & flit_sent_in);
	   
	   assign fbf_read_active = ~&fbc_empty_ivc;
	   
	   assign fbf_read_enable = flit_sent_in;
	   
	   assign fbf_read_addr = fbc_pop_addr;
	   
	   assign flit_data_out = fbf_bypass ? fbf_write_data : fbf_read_data;
	   
	end
      else
	begin
	   
	   assign fbf_write_enable = chi_flit_valid;
	   
	   wire read_active;
	   assign read_active = flit_valid_out;
	   
	   wire fbf_read_enable_s, fbf_read_enable_q;
	   assign fbf_read_enable_s = flit_sent_in;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   fbf_read_enableq
	     (.clk(clk),
	      .reset(reset),
	      .active(read_active),
	      .d(fbf_read_enable_s),
	      .q(fbf_read_enable_q));
	   
	   assign fbf_read_active = fbf_read_enable_q;
	   assign fbf_read_enable = fbf_read_enable_q;
	   
	   wire [0:fbf_addr_width-1] fbf_read_addr_s, fbf_read_addr_q;
	   assign fbf_read_addr_s
	     = flit_sent_in ? fbc_pop_addr : fbf_read_addr_q;
	   c_dff
	     #(.width(fbf_addr_width),
	       .reset_type(reset_type))
	   fbf_read_addrq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(read_active),
	      .d(fbf_read_addr_s),
	      .q(fbf_read_addr_q));
	   
	   assign fbf_read_addr = fbf_read_addr_q;
	   
	   assign flit_data_out = fbf_read_data;
	   
	end
      
   endgenerate
   
   wire 			     fbf_write_active;
   assign fbf_write_active = chi_flit_valid;
   
   wire [0:fbf_addr_width-1] 	     fbf_write_addr;
   assign fbf_write_addr = fbc_push_addr;
   
   c_regfile
     #(.depth(num_vcs*num_flits_per_vc),
       .width(flit_data_width),
       .regfile_type(fbf_regfile_type))
   fbf
     (.clk(clk),
      .write_active(fbf_write_active),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(fbf_write_data),
      .read_active(fbf_read_active),
      .read_enable(fbf_read_enable),
      .read_address(fbf_read_addr),
      .read_data(fbf_read_data));
   
   
   //---------------------------------------------------------------------------
   // generate outgoing flow control signals
   //---------------------------------------------------------------------------
   
   wire 			     fco_active;
   assign fco_active = flit_valid_out;
   
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fco
     (.clk(clk),
      .reset(reset),
      .active(fco_active),
      .fc_event_valid_in(flit_sent_in),
      .fc_event_sel_in_ivc(flit_sel_in_ivc),
      .flow_ctrl_out(flow_ctrl_out));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_vcs*9-1] errors_s, errors_q;
	   assign errors_s = errors_ivc;
	   c_err_rpt
	     #(.num_errors(num_vcs*9),
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
