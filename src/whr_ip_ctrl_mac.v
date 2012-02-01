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
// input port controller
//==============================================================================

module whr_ip_ctrl_mac
  (clk, reset, router_address, channel_in, route_op, req, req_head, req_tail, 
   gnt, flit_data_out, flow_ctrl_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "whr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
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
   
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask = `ELIG_MASK_NONE;
   
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
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + 1) : 
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
   
   // width required for lookahead routing information
   localparam lar_info_width = port_idx_width;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // total number of bits required for storing routing information
   localparam dest_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (router_addr_width + node_addr_width) : 
       -1;
   
   // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       route_info_width : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       route_info_width : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (route_info_width + payload_length_width) : 
       -1;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // use input register as part of the flit buffer
   parameter input_stage_can_hold = 0;
   
   // number of entries in flit buffer
   localparam fb_depth
     = input_stage_can_hold ? (num_flits_per_vc - 1) : num_flits_per_vc;
   
   // required address width for flit buffer
   localparam fb_addr_width = clogb(fb_depth);
   
   // select implementation variant for flit buffer register file
   parameter fb_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 0;
   
   // gate flit buffer write port if bypass succeeds
   // (requires explicit pipeline register; may increase cycle time)
   parameter gate_buffer_write = 0;
   
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
   
   // destination output port
   output [0:num_ports-1] 	 route_op;
   wire [0:num_ports-1] 	 route_op;
   
   // request allocation
   output 			 req;
   wire 			 req;
   
   // current flit is head flit
   output 			 req_head;
   wire 			 req_head;
   
   // current flit is tail flit
   output 			 req_tail;
   wire 			 req_tail;
   
   // output port granted
   input 			 gnt;
   
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
   
   wire 			 flit_valid_out;
   assign flit_valid_out = gnt;
   
   wire 			 fbc_full;
   
   wire 			 hold_input_enable;
   
   generate
      
      if(input_stage_can_hold)
	assign hold_input_enable = fbc_full;
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
   wire 	flit_head_in_ivc;
   wire 	flit_tail_in;
   wire 	flit_tail_in_ivc;
   wire [0:flit_data_width-1] flit_data_in;
   wire 		      flit_sel_in_ivc;
   rtr_channel_input
     #(.num_vcs(1),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
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
      .flit_head_out_ivc(flit_head_in_ivc),
      .flit_tail_out(flit_tail_in),
      .flit_tail_out_ivc(flit_tail_in_ivc),
      .flit_data_out(flit_data_in),
      .flit_sel_out_ivc(flit_sel_in_ivc));
   
   wire [0:header_info_width-1] header_info_in;
   assign header_info_in = flit_data_in[0:header_info_width-1];
   
   wire [0:route_info_width-1] 	route_info_in;
   assign route_info_in = header_info_in[0:route_info_width-1];
   
   wire [0:lar_info_width-1] lar_info_in;
   assign lar_info_in = route_info_in[0:lar_info_width-1];
   
   wire [0:dest_info_width-1] 	  dest_info_in;
   assign dest_info_in = route_info_in[lar_info_width:
				       lar_info_width+dest_info_width-1];
   
   
   //---------------------------------------------------------------------------
   // flit buffer control
   //---------------------------------------------------------------------------
   
   wire 			  push_active;
   assign push_active = flit_valid_thru;
   
   wire 			  pop_active;
   assign pop_active = flit_valid;
   
   wire 			  fbc_push;
   assign fbc_push = flit_valid_thru;
   
   wire 			  fbc_pop;
   assign fbc_pop = flit_valid_out;
   
   wire [0:fb_addr_width-1] 	  fbc_push_addr;
   wire [0:fb_addr_width-1] 	  fbc_pop_addr;
   wire 			  fbc_almost_empty;
   wire 			  fbc_almost_full;
   wire [0:1] 			  fbc_errors;
   c_fifo_ctrl
     #(.depth(fb_depth),
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
   
   wire 			  error_fbc_underflow;
   assign error_fbc_underflow = fbc_errors[0];
   
   wire 			  error_fbc_overflow;
   assign error_fbc_overflow = fbc_errors[1];
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire 			  fbf_write_enable;
   wire [0:fb_addr_width-1] 	  fbf_read_addr;
   
   generate
      
      if(explicit_pipeline_register)
	begin
	   
	   if(gate_buffer_write)
	     assign fbf_write_enable
	       = flit_valid_in & ~(fbc_empty & flit_valid_out);
	   else
	     assign fbf_write_enable = flit_valid_in;
	   
	   assign fbf_read_addr = fbc_pop_addr;
	   
	end
      else
	begin
	   
	   assign fbf_write_enable = flit_valid_in;
	   
	   wire [0:fb_addr_width-1] fbf_read_addr_s, fbf_read_addr_q;
	   assign fbf_read_addr_s = fbc_pop_addr;
	   c_dff
	     #(.width(fb_addr_width),
	       .reset_type(reset_type))
	   fbf_read_addrq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(pop_active),
	      .d(fbf_read_addr_s),
	      .q(fbf_read_addr_q));
	   
	   assign fbf_read_addr = fbf_read_addr_q;
	   
	end
      
   endgenerate
   
   wire [0:flit_data_width-1] 	     fbf_write_data;
   assign fbf_write_data = flit_data_in;
   
   wire [0:flit_data_width-1] 	     fbf_read_data;
   wire [0:flit_data_width-1] 	     fbf_peek_data;
   
   generate

      if(elig_mask == `ELIG_MASK_USED)
	begin
	   
	   c_regfile
	     #(.depth(fb_depth),
	       .width(flit_data_width),
	       .regfile_type(fb_regfile_type))
	   fbf
	     (.clk(clk),
	      .write_active(push_active),
	      .write_enable(fbf_write_enable),
	      .write_address(fbc_push_addr),
	      .write_data(fbf_write_data),
	      .read_address(fbf_read_addr),
	      .read_data(fbf_read_data));
	   
	   assign fbf_peek_data = {flit_data_width{1'b0}};
	   
	end
      else
	begin
	   
	   wire fbf_peek_active;
	   assign fbf_peek_active = ~fbc_empty & ~fbc_almost_empty;
	   
	   wire [0:fb_addr_width-1] fbf_peek_addr;
	   c_incr
	     #(.width(fb_addr_width),
	       .max_value(fb_depth - 1))
	   fbf_peek_addr_incr
	     (.data_in(fbc_pop_addr),
	      .data_out(fbf_peek_addr));
	   
	   c_regfile
	     #(.depth(fb_depth),
	       .width(flit_data_width),
	       .num_read_ports(2),
	       .regfile_type(fb_regfile_type))
	   fbf
	     (.clk(clk),
	      .write_active(push_active),
	      .write_enable(fbf_write_enable),
	      .write_address(fbc_push_addr),
	      .write_data(fbf_write_data),
	      .read_address({fbf_read_addr, fbf_peek_addr}),
	      .read_data({fbf_read_data, fbf_peek_data}));
	   
	end
      
   endgenerate
   
   wire [0:flit_data_width-1] fbf_flit_data;
   assign fbf_flit_data = fbf_read_data;
   
   wire [0:header_info_width-1] peek_header_info;
   assign peek_header_info = fbf_peek_data[0:header_info_width-1];

   wire [0:route_info_width-1] 	peek_route_info;
   assign peek_route_info = peek_header_info[0:route_info_width-1];
   
   
   //---------------------------------------------------------------------------
   // generate head and tail indicators
   //---------------------------------------------------------------------------
   
   wire 			fb_flit_tail;
   
   wire 			flit_tail_out;
   assign flit_tail_out = fbc_empty ? flit_tail_in : fb_flit_tail;
   
   generate
      
      if(elig_mask == `ELIG_MASK_USED)
	begin
	   
	   wire has_tail_s, has_tail_q;
	   assign has_tail_s = (has_tail_q & ~(flit_valid_in & flit_head_in)) |
			       (flit_valid_in & flit_tail_in);
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   has_tailq
	     (.clk(clk),
	      .reset(reset),
	      .active(pop_active),
	      .d(has_tail_s),
	      .q(has_tail_q));
	   
	   assign fb_flit_tail = fbc_almost_empty & has_tail_q;
	   
	end
      else
	begin
	   
	   wire [0:fb_depth-1] 	push_mask;
	   c_decode
	     #(.num_ports(fb_depth))
	   push_addr_dec
	     (.data_in(fbc_push_addr),
	      .data_out(push_mask));
	   
	   wire [0:fb_depth-1] 	flit_tail_s, flit_tail_q;
	   assign flit_tail_s
	     = fbf_write_enable ? 
	       ({fb_depth{flit_tail_in}} & push_mask) | 
	       (flit_tail_q & ~push_mask) : 
	       flit_tail_q;
	   c_dff
	     #(.width(fb_depth),
	       .reset_type(reset_type))
	   flit_tailq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(push_active),
	      .d(flit_tail_s),
	      .q(flit_tail_q));
	   
	   assign fb_flit_tail = flit_tail_q[fbc_pop_addr];
	   
	end
      
   endgenerate
   
   wire 			htr_flit_head_s, htr_flit_head_q;
   assign htr_flit_head_s = flit_valid_out ? flit_tail_out : htr_flit_head_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type),
       .reset_value(1'b1))
   htr_flit_headq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(htr_flit_head_s),
      .q(htr_flit_head_q));
   
   wire 			flit_head_out;
   assign flit_head_out = fbc_empty ? flit_head_in : htr_flit_head_q;
   
   
   //---------------------------------------------------------------------------
   // head register
   //---------------------------------------------------------------------------
   
   wire 			hdr_valid_s, hdr_valid_q;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_valid_s
	  = (hdr_valid_q | flit_valid_in) & ~(flit_valid_out & flit_tail_out);
      else
	assign hdr_valid_s
	  = flit_valid_out ?
	    (fbc_empty ?
	     ~flit_tail_in :
	     (~fb_flit_tail | ~fbc_almost_empty | flit_valid_in)) :
	    (hdr_valid_q | flit_valid_in);
   endgenerate
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   hdf_validq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(hdr_valid_s),
      .q(hdr_valid_q));
   
   wire 			hdr_active;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_active = ~hdr_valid_q & flit_valid_in;
      else
	// NOTE: If this ends up being timing-critical, we can simply eliminate 
	// the fb_flit_tail term at the expense of slightly worse gating under 
	// load.
	// For relatively short packets, this is probably a good tradeoff.
	assign hdr_active
	  = (~hdr_valid_q & flit_valid_in) | (~fbc_empty & fb_flit_tail);
   endgenerate
   
   wire [0:lar_info_width-1] hdr_lar_info_s, hdr_lar_info_q;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_lar_info_s
	  = hdr_valid_q ? hdr_lar_info_q : lar_info_in;
      else
	begin
	   
	   wire [0:lar_info_width-1] peek_lar_info;
	   assign peek_lar_info = peek_route_info[0:lar_info_width-1];
	   
	   assign hdr_lar_info_s
	     = (flit_valid_out & flit_tail_out) ? 
	       (fbc_almost_empty ? lar_info_in : peek_lar_info) : 
	       (hdr_valid_q ? hdr_lar_info_q : lar_info_in);
	   
	end
   endgenerate
   c_dff
     #(.width(lar_info_width),
       .reset_type(reset_type))
   hdr_lar_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_lar_info_s),
      .q(hdr_lar_info_q));
   
   wire [0:dest_info_width-1] 		  hdr_dest_info_s, hdr_dest_info_q;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_dest_info_s
	  = hdr_valid_q ? hdr_dest_info_q : dest_info_in;
      else
	begin
	   
	   wire [0:dest_info_width-1] peek_dest_info;
	   assign peek_dest_info
	     = peek_route_info[lar_info_width:lar_info_width+dest_info_width-1];
	   
	   assign hdr_dest_info_s
	     = (flit_valid_out & flit_tail_out) ? 
	       (fbc_almost_empty ? dest_info_in : peek_dest_info) : 
	       (hdr_valid_q ? hdr_dest_info_q : dest_info_in);
	   
	end
   endgenerate
   c_dff
     #(.width(dest_info_width),
       .reset_type(reset_type))
   hdr_dest_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_dest_info_s),
      .q(hdr_dest_info_q));
   
   wire 			       error_no_header;
   assign error_no_header
     = ~hdr_valid_q & (~fbc_empty | (flit_valid_in & ~flit_head_in));
   
   
   //---------------------------------------------------------------------------
   // decode lookahead routing information
   //---------------------------------------------------------------------------
   
   wire [0:port_idx_width-1] 	       route_port_in;
   assign route_port_in = lar_info_in[0:port_idx_width-1];
   
   wire [0:num_ports-1] 	       route_in_op;
   c_decode
     #(.num_ports(num_ports))
   route_in_op_dec
     (.data_in(route_port_in),
      .data_out(route_in_op));
   
   wire [0:port_idx_width-1] 	       hdr_route_port;
   assign hdr_route_port = hdr_lar_info_q[0:port_idx_width-1];
   
   wire [0:num_ports-1] 	       hdr_route_op;
   c_decode
     #(.num_ports(num_ports))
   hdr_route_op_dec
     (.data_in(hdr_route_port),
      .data_out(hdr_route_op));
   
   wire [0:num_ports-1] 	       route_unmasked_op;
   assign route_unmasked_op = hdr_valid_q ? hdr_route_op : route_in_op;
   
   wire 			       header_valid;
   assign header_valid = hdr_valid_q | flit_valid_in;
   
   wire 			       rf_active;
   assign rf_active = header_valid;
   
   wire 			       route_orc;
   wire [0:1] 			       rf_errors;
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
   rf
     (.clk(clk),
      .reset(reset),
      .active(rf_active),
      .route_valid(header_valid),
      .route_in_op(route_unmasked_op),
      .route_in_orc(1'b1),
      .route_out_op(route_op),
      .route_out_orc(route_orc),
      .errors(rf_errors));
   
   wire 			       error_invalid_port;
   assign error_invalid_port = rf_errors[0];
   
   wire 			       error_invalid_class;
   assign error_invalid_class = rf_errors[1];
   
   
   //---------------------------------------------------------------------------
   // update lookahead routing information for next hop
   //---------------------------------------------------------------------------
   
   wire [0:dest_info_width-1] 	       dest_info;
   assign dest_info = hdr_valid_q ? hdr_dest_info_q : dest_info_in;
   
   wire [0:lar_info_width-1] 	       lar_info;
   assign lar_info = hdr_valid_q ? hdr_lar_info_q : lar_info_in;
   
   wire [0:router_addr_width-1]        next_router_address;
   rtr_next_hop_addr
     #(.num_resource_classes(1),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type))
   nha
     (.router_address(router_address),
      .dest_info(dest_info),
      .lar_info(lar_info),
      .next_router_address(next_router_address));
   
   wire [0:num_ports-1] 	       next_route_op;
   wire 			       next_route_orc;
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
      .dest_info(dest_info),
      .route_op(next_route_op),
      .route_orc(next_route_orc));
   
   wire [0:port_idx_width-1] 	       next_route_port;
   c_encode
     #(.num_ports(num_ports))
   next_route_port_enc
     (.data_in(next_route_op),
      .data_out(next_route_port));
   
   wire [0:lar_info_width-1] 	       next_lar_info;
   assign next_lar_info = next_route_port;
   
   
   //---------------------------------------------------------------------------
   // generate output data
   //---------------------------------------------------------------------------
   
   wire [0:lar_info_width-1] 	       lar_info_s, lar_info_q;
   assign lar_info_s = flit_head_out ? next_lar_info : lar_info_q;
   c_dff
     #(.width(lar_info_width),
       .reset_type(reset_type))
   lar_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(pop_active),
      .d(lar_info_s),
      .q(lar_info_q));
   
   wire 			       flit_head_prev_s, flit_head_prev_q;
   assign flit_head_prev_s = flit_head_out;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_head_prevq
     (.clk(clk),
      .reset(1'b0),
      .active(pop_active),
      .d(flit_head_prev_s),
      .q(flit_head_prev_q));
   
   wire [0:flit_data_width-1] 	       flit_data_buffered;
   
   generate
      
      if(explicit_pipeline_register)
	begin
	   
	   wire [0:flit_data_width-1] flit_data_s, flit_data_q;
	   assign flit_data_s = fbc_empty ? flit_data_in : fbf_flit_data;
	   c_dff
	     #(.width(flit_data_width),
	       .reset_type(reset_type))
	   flit_dataq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(pop_active),
	      .d(flit_data_s),
	      .q(flit_data_q));
	   
	   assign flit_data_buffered = flit_data_q;
	   
	end
      else
	assign flit_data_buffered = fbf_flit_data;
      
   endgenerate
   
   assign flit_data_out[0:lar_info_width-1]
     = flit_head_prev_q ? lar_info_q : flit_data_buffered[0:lar_info_width-1];
   assign flit_data_out[lar_info_width:flit_data_width-1]
     = flit_data_buffered[lar_info_width:flit_data_width-1];
	   
   
   //---------------------------------------------------------------------------
   // generate control signals to switch allocator
   //---------------------------------------------------------------------------
   
   assign req = flit_valid;
   assign req_head = flit_head_out;
   assign req_tail = flit_tail_out;
   
   
   //---------------------------------------------------------------------------
   // generate outgoing credits
   //---------------------------------------------------------------------------
   
   wire 				  flow_ctrl_active;
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
	
	if(error_no_header)
	  $display("ERROR: Stray flit received in module %m.");
	
     end
   
   // synopsys translate_on
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin

	   wire [0:4] errors_s, errors_q;
	   assign errors_s[0] = error_fbc_underflow;
	   assign errors_s[1] = error_fbc_overflow;
	   assign errors_s[2] = error_no_header;
	   assign errors_s[3] = error_invalid_port;
	   assign errors_s[4] = error_invalid_class;
	   c_err_rpt
	     #(.num_errors(5),
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
