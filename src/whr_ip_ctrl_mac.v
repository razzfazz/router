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

module whr_ip_ctrl_mac
  (clk, reset, router_address, channel_in, req_op, req_head, req_tail, gnt_op, 
   xbr_active, flit_data_out, flow_ctrl_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "whr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
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
   
   // width required for routing information for a single hop
   localparam hop_route_info_width = port_idx_width;
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? 1 :
       -1;
   
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
   localparam route_info_width = addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // enable lookahead routing
   parameter lookahead_routing = 1;
   
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
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // use input register as part of the flit buffer
   parameter input_stage_can_hold = 0;
   
   // number of entries in flit buffer
   localparam fbf_depth
     = input_stage_can_hold ? (num_flits_per_vc - 1) : num_flits_per_vc;
   
   // required address width for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // required address width for head/tail FIFO
   localparam htff_addr_width = clogb(num_flits_per_vc - 1);
   
   // select implementation variant for head/tail FIFO register file
   parameter htff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // required address width for header data FIFO
   localparam hdff_addr_width = clogb(num_packets_per_vc - 1);
   
   // select implementation variant for header data FIFO register file
   parameter hdff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 0;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
      
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming channel
   input [0:channel_width-1] 	 channel_in;
   
   // request for output port
   output [0:num_ports-1] 	 req_op;
   wire [0:num_ports-1] 	 req_op;
   
   // current flit is head flit
   output 			 req_head;
   wire 			 req_head;
   
   // current flit is tail flit
   output 			 req_tail;
   wire 			 req_tail;
   
   // output port granted
   input [0:num_ports-1] 	 gnt_op;
   
   // crossbar enable signal
   output 			 xbr_active;
   wire 			 xbr_active;
   
   // outgoing flit data
   output [0:flit_data_width-1]  flit_data_out;
   wire [0:flit_data_width-1] 	 flit_data_out;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1]  flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 	 flow_ctrl_out;
   
   // internal error condition detected
   output 			 error;
   wire 			 error;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   wire 			 flit_valid_in;
   wire 			 fbc_empty;
   
   wire 			 flit_valid;
   assign flit_valid = flit_valid_in | ~fbc_empty;
   
   wire 			 fbc_almost_full;
   wire 			 flit_valid_out;
   
   wire 			 hold_input_enable;
   
   generate
      
      if(input_stage_can_hold)
	begin
	   
	   wire hold_input_enable_active;
	   assign hold_input_enable_active = flit_valid;
	   
	   wire hold_input_enable_set;
	   assign hold_input_enable_set = fbc_almost_full & flit_valid_in;
	   
	   wire hold_input_enable_reset;
	   assign hold_input_enable_reset = flit_valid_out;
	   
	   wire hold_input_enable_s, hold_input_enable_q;
	   assign hold_input_enable_s
	     = (hold_input_enable_q | hold_input_enable_set) & 
	       ~hold_input_enable_reset;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   hold_input_enableq
	     (.clk(clk),
	      .reset(reset),
	      .active(hold_input_enable_active),
	      .d(hold_input_enable_s),
	      .q(hold_input_enable_q));
	   
	   assign hold_input_enable = hold_input_enable_q;
	   
	end
      else
	assign hold_input_enable = 1'b0;
      
   endgenerate
   
   wire 	flit_valid_thru;
   assign flit_valid_thru = flit_valid_in & ~hold_input_enable;
   
   wire 	hold_input_stage_b;
   assign hold_input_stage_b = ~(flit_valid_in & hold_input_enable);
   
   wire 	chi_active;
   assign chi_active = hold_input_stage_b;
   
   wire 	flit_head_in;
   wire 	flit_tail_in;
   wire [0:flit_data_width-1] flit_data_in;
   wire 		      flit_sel_in_ivc;
   rtr_channel_input
     #(.num_vcs(1),
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
      .flit_valid_out(flit_valid_in),
      .flit_head_out(flit_head_in),
      .flit_tail_out(flit_tail_in),
      .flit_data_out(flit_data_in),
      .flit_sel_out_ivc(flit_sel_in_ivc));
   
   // extract header information from header data
   wire [0:header_info_width-1] header_info_in;
   assign header_info_in = flit_data_in[0:header_info_width-1];
   
   
   //---------------------------------------------------------------------------
   // routing
   //---------------------------------------------------------------------------
   
   wire [0:route_info_width-1] 	route_info_in;
   assign route_info_in
     = header_info_in[la_route_info_width:
		      la_route_info_width+route_info_width-1];
   
   wire [0:hop_route_info_width-1] hop_route_info;
   wire [0:num_ports-1] 	   hop_route_op;
   wire [0:port_idx_width-1] 	   hop_route_port;
   wire [0:header_info_width-1]    header_info_out;
   
   generate
      
      if(lookahead_routing)
	begin
	   
	   wire [0:la_route_info_width-1] la_route_info_in;
	   assign la_route_info_in = header_info_in[0:la_route_info_width-1];
	   
	   assign hop_route_info = la_route_info_in;
	   assign hop_route_port = la_route_info_in[0:port_idx_width-1];
	   
	   c_decode
	     #(.num_ports(num_ports))
	   hop_route_op_dec
	     (.data_in(hop_route_port),
	      .data_out(hop_route_op));
	   
	   wire [0:router_addr_width-1]   next_router_address;
	   rtr_next_hop_addr
	     #(.num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity))
	   nha
	     (.router_address(router_address),
	      .route_port(hop_route_port),
	      .next_router_address(next_router_address));
	   
	   wire [0:num_ports-1] 	  next_route_op;
	   wire 			  next_route_orc;
	   rtr_routing_logic
	     #(.num_message_classes(1),
	       .num_resource_classes(1),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity),
	       .routing_type(routing_type),
	       .dim_order(dim_order))
	   rtl
	     (.router_address(next_router_address),
	      .sel_mc(1'b1),
	      .sel_irc(1'b1),
	      .route_info(route_info_in),
	      .route_op(next_route_op),
	      .route_orc(next_route_orc));
	   
	   wire [0:port_idx_width-1] 	  next_route_port;
	   c_encode
	     #(.num_ports(num_ports))
	   next_route_port_enc
	     (.data_in(next_route_op),
	      .data_out(next_route_port));
	   
	   wire [0:la_route_info_width-1] la_route_info_out;
	   assign la_route_info_out[0:port_idx_width-1] = next_route_port;
	   
	   assign header_info_out[0:la_route_info_width-1] = la_route_info_out;
	   
	end
      else
	begin
	   
	   wire route_orc;
	   rtr_routing_logic
	     #(.num_message_classes(1),
	       .num_resource_classes(1),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity),
	       .routing_type(routing_type),
	       .dim_order(dim_order))
	   rtl
	     (.router_address(router_address),
	      .sel_mc(1'b1),
	      .sel_irc(1'b1),
	      .route_info(route_info_in),
	      .route_op(hop_route_op),
	      .route_orc(route_orc));
	   
	   c_encode
	     #(.num_ports(num_ports))
	   hop_route_port_enc
	     (.data_in(hop_route_op),
	      .data_out(hop_route_port));
	   
	   assign hop_route_info[0:port_idx_width-1] = hop_route_port;
	   
	end
      
   endgenerate
   
   assign header_info_out[la_route_info_width:header_info_width-1]
     = header_info_in[la_route_info_width:header_info_width-1];
   
   
   //---------------------------------------------------------------------------
   // generate head and tail indicators
   //---------------------------------------------------------------------------

   wire 	buffer_active;
   assign buffer_active = flit_valid_thru;
   
   wire 	flags_active;
   assign flags_active = flit_valid;
   
   wire 	gnt;
   assign gnt = |gnt_op;
   
   assign flit_valid_out = gnt;
   
   wire 	fbc_almost_empty;
   wire [0:fbf_addr_width-1] fbc_push_addr;
   wire [0:fbf_addr_width-1] fbc_pop_addr;
   
   wire 		     flit_head_out;
   wire 		     flit_tail_out;
   
   generate
      
      if(num_packets_per_vc > 1)
	begin
	   
	   wire htff_empty;
	   
	   wire htff_push;
	   assign htff_push
	     = flit_valid_thru & ~fbc_empty & (~flit_valid_out | ~htff_empty);
	   
	   wire htff_pop;
	   assign htff_pop = flit_valid_out & ~htff_empty;
	   
	   wire [0:1] htff_push_data;
	   assign htff_push_data[0] = flit_head_in;
	   assign htff_push_data[1] = flit_tail_in;
	   
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
	      .push_active(buffer_active),
	      .pop_active(flags_active),
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
	   
	   wire       error_htff_underflow;
	   assign error_htff_underflow = htff_errors[0];
	   
	   wire       error_htff_overflow;
	   assign error_htff_overflow = htff_errors[1];
	   
	   wire flit_head_muxed;
	   assign flit_head_muxed = htff_empty ? flit_head_in : htff_flit_head;
	   
	   wire flit_tail_muxed;
	   assign flit_tail_muxed = htff_empty ? flit_tail_in : htff_flit_tail;
	   
	   wire [0:1] flit_flags_muxed;
	   assign flit_flags_muxed[0] = flit_head_muxed;
	   assign flit_flags_muxed[1] = flit_tail_muxed;
	   
	   wire       htr_capture;
	   assign htr_capture = (fbc_empty & flit_valid_in) | flit_valid_out;
	   
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
	   
	   assign flit_head_out = fbc_empty ? flit_head_in : htr_data_q[0];
	   assign flit_tail_out = fbc_empty ? flit_tail_in : htr_data_q[1];
	   
	end
      else
	begin
	   
	   wire head_in;
	   assign head_in = flit_valid_thru & flit_head_in;
	   
	   wire head_valid_s, head_valid_q;
	   assign head_valid_s = (head_valid_q | head_in) & ~flit_valid_out;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   head_validq
	     (.clk(clk),
	      .reset(reset),
	      .active(flags_active),
	      .d(head_valid_s),
	      .q(head_valid_q));
	   
	   assign flit_head_out = fbc_empty ? flit_head_in : head_valid_q;
	   
	   wire 		     tail_in;
	   assign tail_in = flit_valid_thru & flit_tail_in;
	   
	   wire 		     tail_valid_s, tail_valid_q;
	   assign tail_valid_s
	     = (tail_valid_q | tail_in) & ~(flit_valid_out & flit_tail_out);
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   tail_validq
	     (.clk(clk),
	      .reset(reset),
	      .active(flags_active),
	      .d(tail_valid_s),
	      .q(tail_valid_q));
	   
	   assign flit_tail_out
	     = fbc_empty ? flit_tail_in : (tail_valid_q & fbc_almost_empty);
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // header buffer
   //---------------------------------------------------------------------------
   
   wire 			     head_received;
   assign head_received = flit_valid_thru & flit_head_in;
   
   wire 			     tail_sent;
   assign tail_sent = flit_valid_out & flit_tail_out;
   
   wire 			     hdr_valid;
   wire 			     hdff_empty;
   
   wire 			     hdff_push;
   assign hdff_push = head_received & hdr_valid & (~tail_sent | ~hdff_empty);
   
   wire 			     hdff_pop;
   assign hdff_pop = tail_sent & ~hdff_empty;
   
   wire [0:hop_route_info_width-1]   hdff_hop_route_info;
   wire 			     error_hdff_underflow;
   wire 			     error_hdff_overflow;
   
   generate
      
      if(num_packets_per_vc > 1)
	begin
	   
	   wire [0:hop_route_info_width-1] hdff_push_data;
	   assign hdff_push_data = hop_route_info;
	   
	   wire [0:hop_route_info_width-1] hdff_pop_data;
	   wire 		      hdff_almost_full;
	   wire 		      hdff_full;
	   wire 		      hdff_almost_empty;
	   wire [0:1] 		      hdff_errors;
	   c_fifo
	     #(.depth(num_packets_per_vc - 1),
	       .width(hop_route_info_width),
	       .regfile_type(hdff_regfile_type),
	       .reset_type(reset_type))
	   hdff
	     (.clk(clk),
	      .reset(reset),
	      .push_active(buffer_active),
	      .pop_active(flags_active),
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
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // head register
   //---------------------------------------------------------------------------
   
   wire hdr_valid_s, hdr_valid_q;
   assign hdr_valid_s = hdr_valid_q ?
			(~tail_sent | ~hdff_empty | head_received) : 
			(flit_valid_in & ~tail_sent);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   hdf_validq
     (.clk(clk),
      .reset(reset),
      .active(flags_active),
      .d(hdr_valid_s),
      .q(hdr_valid_q));
   
   assign hdr_valid = hdr_valid_q;
   
   wire [0:hop_route_info_width-1] hop_route_info_muxed;
   assign hop_route_info_muxed
     = hdff_empty ? hop_route_info : hdff_hop_route_info;
   
   wire 			   hdr_capture;
   assign hdr_capture = (~hdr_valid & flit_valid_in) | 
			(tail_sent & (~hdff_empty | flit_valid_in));
   
   wire [0:hop_route_info_width-1] hdr_hop_route_info_s, hdr_hop_route_info_q;
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
   
   wire 			   header_valid;
   assign header_valid = hdr_valid | flit_valid_in;
   
   wire 			   error_no_header;
   assign error_no_header = flit_valid & ~header_valid;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:port_idx_width-1] 	   hdr_route_port;
   assign hdr_route_port = hdr_hop_route_info[0:port_idx_width-1];
   
   wire [0:num_ports-1] 	   hdr_route_op;
   c_decode
     #(.num_ports(num_ports))
   hdr_route_op_dec
     (.data_in(hdr_route_port),
      .data_out(hdr_route_op));
   
   wire [0:num_ports-1] 	   route_unmasked_op;
   assign route_unmasked_op = hdr_valid ? hdr_route_op : hop_route_op;
   
   wire [0:num_ports-1] 	   route_op;
   wire 			   route_orc;
   wire [0:1] 			   rfl_errors;
   rtr_route_filter
     #(.num_message_classes(1),
       .num_resource_classes(1),
       .num_vcs_per_class(1),
       .num_ports(num_ports),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .num_nodes_per_router(num_nodes_per_router),
       .restrict_turns(restrict_turns),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .port_id(port_id),
       .vc_id(0))
   rfl
     (.route_in_op(route_unmasked_op),
      .route_in_orc(1'b1),
      .route_out_op(route_op),
      .route_out_orc(route_orc),
      .errors(rfl_errors));
   
   wire 			   error_invalid_port;
   assign error_invalid_port = header_valid & rfl_errors[0];
   
   wire 			   error_invalid_class;
   assign error_invalid_class = header_valid & rfl_errors[1];
   
   
   //---------------------------------------------------------------------------
   // flit buffer control
   //---------------------------------------------------------------------------
   
   wire 			   fbc_push;
   assign fbc_push = flit_valid_thru;
   
   wire 			   fbc_pop;
   assign fbc_pop = flit_valid_out;
   
   wire 			   fbc_full;
   wire [0:1] 			   fbc_errors;
   c_fifo_ctrl
     #(.depth(fbf_depth),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push_active(buffer_active),
      .pop_active(flags_active),
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
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   
   // multiplex in updated lookahead routingo info for head flits
   
   wire [0:flit_data_width-1] 	   fbf_write_data;
   assign fbf_write_data[0:header_info_width-1]
     = flit_head_in ? header_info_out : header_info_in;
   assign fbf_write_data[header_info_width:flit_data_width-1]
     = flit_data_in[header_info_width:flit_data_width-1];

   wire 			   fbf_write_enable;
   wire 			   fbf_read_active;
   wire 			   fbf_read_enable;
   wire [0:fbf_addr_width-1] 	   fbf_read_addr;
   wire [0:flit_data_width-1] 	   fbf_read_data;
   
   generate
      
      if(explicit_pipeline_register)
	begin
	   
	   wire fbf_bypass;
	   assign fbf_bypass = fbc_empty;
	   
	   assign fbf_write_enable
	     = flit_valid_thru & ~(fbf_bypass & flit_valid_out);
	   
	   assign fbf_read_active = flags_active;
	   
	   assign fbf_read_enable = flit_valid_out;
	   
	   assign fbf_read_addr = fbc_pop_addr;
	   
	   wire [0:flit_data_width-1] flit_data_muxed;
	   assign flit_data_muxed = fbf_bypass ? fbf_write_data : fbf_read_data;
	   
	   wire [0:flit_data_width-1] flit_data_s, flit_data_q;
	   assign flit_data_s = flit_valid_out ? flit_data_muxed : flit_data_q;
	   c_dff
	     #(.width(flit_data_width),
	       .reset_type(reset_type))
	   flit_dataq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(flags_active),
	      .d(flit_data_s),
	      .q(flit_data_q));
	   
	   assign flit_data_out = flit_data_q;
	   
	end
      else
	begin
	   
	   assign fbf_write_enable = flit_valid_thru;
	   
	   
	   // In the absence of an explicit pipeline register between flit 
	   // buffer and crossbar, the read address is delayed by one clock 
	   // cycle such as to line up the flit data read from the buffer with 
	   // the crossbar control signals.
	   
	   wire fbf_read_enable_s, fbf_read_enable_q;
	   assign fbf_read_enable_s = flit_valid_out;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   fbf_read_enableq
	     (.clk(clk),
	      .reset(reset),
	      .active(flags_active),
	      .d(fbf_read_enable_s),
	      .q(fbf_read_enable_q));
	   
	   assign fbf_read_active = fbf_read_enable_q;
	   assign fbf_read_enable = fbf_read_enable_q;
	   
	   wire [0:fbf_addr_width-1] fbf_read_addr_s, fbf_read_addr_q;
	   assign fbf_read_addr_s
	     = flit_valid_out ? fbc_pop_addr : fbf_read_addr_q;
	   c_dff
	     #(.width(fbf_addr_width),
	       .reset_type(reset_type))
	   fbf_read_addrq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(flags_active),
	      .d(fbf_read_addr_s),
	      .q(fbf_read_addr_q));
	   
	   assign fbf_read_addr = fbf_read_addr_q;
	   
	   assign flit_data_out = fbf_read_data;
	   
	end
      
   endgenerate
   
   wire [0:fbf_addr_width-1] 	     fbf_write_addr;
   assign fbf_write_addr = fbc_push_addr;
   
   c_regfile
     #(.depth(fbf_depth),
       .width(flit_data_width),
       .regfile_type(fbf_regfile_type))
   fbf
     (.clk(clk),
      .write_active(buffer_active),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(fbf_write_data),
      .read_active(fbf_read_active),
      .read_enable(fbf_read_enable),
      .read_address(fbf_read_addr),
      .read_data(fbf_read_data));
   
   
   //---------------------------------------------------------------------------
   // generate control signals to switch allocator
   //---------------------------------------------------------------------------
   
   wire 			     req;
   assign req = flit_valid;
   
   assign req_op = {num_ports{req}} & route_op;
   
   assign req_head = flit_head_out;
   assign req_tail = flit_tail_out;
   
   
   //---------------------------------------------------------------------------
   // generate control signals to crossbar module
   //---------------------------------------------------------------------------
   
   assign xbr_active = flit_valid;
   
   
   //---------------------------------------------------------------------------
   // generate outgoing credits
   //---------------------------------------------------------------------------
   
   wire 			     flow_ctrl_active;
   assign flow_ctrl_active = flit_valid;
   
   rtr_flow_ctrl_output
     #(.num_vcs(1),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fco
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .fc_event_valid_in(flit_valid_out),
      .fc_event_sel_in_ivc(1'b1),
      .flow_ctrl_out(flow_ctrl_out));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   always @(posedge clk)
     begin
	
	if(error_fbc_underflow)
	  $display("ERROR: Flit buffer controller underflow in module %m.");
	
	if(error_fbc_overflow)
	  $display("ERROR: Flit buffer controller overflow in module %m.");
	
	if(error_hdff_underflow)
	  $display("ERROR: Head FIFO underflow in module %m.");
	
	if(error_hdff_overflow)
	  $display("ERROR: Head FIFO overflow in module %m.");
	
	if(error_no_header)
	  $display("ERROR: Stray flit received in module %m.");
	
	if(error_invalid_port)
	  $display({"ERROR: Received flit's destination port does not match ",
		    "constraints in module %m."});
	
     end
   // synopsys translate_on
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin

	   wire [0:6] errors_s, errors_q;
	   assign errors_s[0] = error_fbc_underflow;
	   assign errors_s[1] = error_fbc_overflow;
	   assign errors_s[2] = error_hdff_underflow;
	   assign errors_s[3] = error_hdff_overflow;
	   assign errors_s[4] = error_no_header;
	   assign errors_s[5] = error_invalid_port;
	   assign errors_s[6] = error_invalid_class;
	   c_err_rpt
	     #(.num_errors(7),
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
