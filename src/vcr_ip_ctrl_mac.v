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

module vcr_ip_ctrl_mac
  (/*autoarg*/
   // Outputs
   route_ivc_op, route_ivc_orc, allocated_ivc, flit_valid_ivc,
   free_nonspec_ivc, int_flit_ctrl, flit_data, flow_ctrl_out, error,
   expired, cancel_vc,
   // Inputs
   clk, reset, router_address, channel_in, vc_gnt_ivc,
   vc_gnt_ivc_ocvc, sw_sel_ivc, sw_gnt, int_flow_ctrl_op_ovc
   );
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
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
   
   // number of nodes per router (a.k.a. consentration factor)
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
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + num_vcs) :
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
   parameter flit_data_width = 64;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // width required for lookahead routing information
   localparam lar_info_width = port_idx_width + resource_class_idx_width;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // total number of bits required for storing routing information
   localparam dest_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   
   // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width = 1 + 2 + num_vcs;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_LEVEL) ? 2 :
       (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_PUSH) ? 1 :
       -1;
   
   // number of entries in flit buffer
   localparam fbf_depth = num_vcs*num_flits_per_vc;
   
   // required address width for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
   // select implementation variant for flit buffer register file
   parameter fb_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 0;
   
   // gate flit buffer write port if bypass succeeds
   // (requires explicit pipeline register; may increase cycle time)
   parameter gate_buffer_write = 0;
   
   // select speculation type
   parameter sw_alloc_spec = 1;
   
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask = `ELIG_MASK_NONE;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   localparam time_to_wait_width = 8;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming channel
   input [0:channel_width-1] 	 channel_in;
   
   // destination port
   output [0:num_vcs*num_ports-1] route_ivc_op;
   wire [0:num_vcs*num_ports-1]   route_ivc_op;
   
   // select next resource class
   output [0:num_vcs*num_resource_classes-1] route_ivc_orc;
   wire [0:num_vcs*num_resource_classes-1]   route_ivc_orc;
   
   // VC has an output VC allocated to it
   output [0:num_vcs-1] 		     allocated_ivc;
   wire [0:num_vcs-1] 			     allocated_ivc;
   
   // VC has a flit available
   output [0:num_vcs-1] 		     flit_valid_ivc;
   wire [0:num_vcs-1] 			     flit_valid_ivc;
   
   // credit availability if output VC has been allocated
   output [0:num_vcs-1] 		     free_nonspec_ivc;
   wire [0:num_vcs-1] 			     free_nonspec_ivc;
   
   // VC allocation successful
   input [0:num_vcs-1] 			     vc_gnt_ivc;
   
   // granted output VC
   input [0:num_vcs*num_vcs_per_class-1]     vc_gnt_ivc_ocvc;
   
   // select VC for switch grant
   input [0:num_vcs-1] 			     sw_sel_ivc;
   
   // switch grant
   input 				     sw_gnt;
   
   // internal flow control signals from output controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   // outgoing flit control signals
   output [0:int_flit_ctrl_width-1] 		     int_flit_ctrl;
   wire [0:int_flit_ctrl_width-1] 		     int_flit_ctrl;
   
   // outgoing flit data
   output [0:flit_data_width-1] 		     flit_data;
   wire [0:flit_data_width-1] 			     flit_data;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] 		     flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 			     flow_ctrl_out;
   
   // internal error condition detected
   output 					     error;
   wire 					     error;

   output expired;
   output [0:num_ports-1] cancel_vc;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 				     full_ivc;
   
   wire 					     input_stage_active;
   assign input_stage_active = ~&full_ivc;
   
   wire 					     flit_valid_in;
   wire 					     flit_head_in;
   wire [0:num_vcs-1] 				     flit_head_in_ivc;
   wire 					     flit_tail_in;
   wire [0:num_vcs-1] 				     flit_tail_in_ivc;
   wire [0:flit_data_width-1] 			     flit_data_in;
   wire [0:num_vcs-1] 				     flit_sel_in_ivc;
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
      .active(input_stage_active),
      .channel_in(channel_in),
      .flit_valid_out(flit_valid_in),
      .flit_head_out(flit_head_in),
      .flit_head_out_ivc(flit_head_in_ivc),
      .flit_tail_out(flit_tail_in),
      .flit_tail_out_ivc(flit_tail_in_ivc),
      .flit_data_out(flit_data_in),
      .flit_sel_out_ivc(flit_sel_in_ivc));
   

   //---------------------------------------------------------------------------
   // switch allocation
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 				     free_spec_ivc;
   
   wire 					     flit_sent;
   
   generate
      
      if(sw_alloc_spec)
	begin
	   if(elig_mask == `ELIG_MASK_NONE)
	     assign flit_sent
			 = sw_gnt & 
			 |(sw_sel_ivc & (allocated_ivc | (vc_gnt_ivc & free_spec_ivc)));
	   else
	     assign flit_sent
	       = sw_gnt & |(sw_sel_ivc & (allocated_ivc | vc_gnt_ivc));
	end
      else
	assign flit_sent = sw_gnt;
      
   endgenerate
   
   wire [0:num_vcs-1] 				     sw_gnt_ivc;
   assign sw_gnt_ivc = {num_vcs{sw_gnt}} & sw_sel_ivc;
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   wire 					     buffer_active;
   assign buffer_active = flit_valid_in;
   
   wire [0:num_vcs-1] 				     flit_valid_in_ivc;
   assign flit_valid_in_ivc = {num_vcs{flit_valid_in}} & flit_sel_in_ivc;
   
   wire [0:num_vcs-1] 				     flit_sent_prev_ivc;
   wire 					     flit_tail_prev;
   wire [0:num_vcs*lar_info_width-1] 		     next_lar_info_ivc;
   wire [0:num_vcs-1] 				     flit_head_ivc;
   wire [0:num_vcs-1] 				     flit_tail_ivc;
   wire [0:num_vcs*num_vcs-1] 			     flit_sel_ivc_ovc;
   wire [0:num_vcs*flit_data_width-1] 		     flit_data_ivc;
   wire [0:num_vcs-1] 				     empty_ivc;
   wire [0:num_vcs*6-1] 			     ivcc_errors_ivc;

   wire drop_event;
   
   genvar 					     ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire flit_valid_in;
	   assign flit_valid_in = flit_valid_in_ivc[ivc];
	   
	   wire flit_head_in;
	   assign flit_head_in = flit_head_in_ivc[ivc];
	   
	   wire flit_tail_in;
	   assign flit_tail_in = flit_tail_in_ivc[ivc];
	   
	   wire vc_gnt;
	   assign vc_gnt = vc_gnt_ivc[ivc];
	   
	   wire [0:num_vcs_per_class-1] vc_gnt_ocvc;
	   assign vc_gnt_ocvc = vc_gnt_ivc_ocvc[ivc*num_vcs_per_class:
						(ivc+1)*num_vcs_per_class-1];
	   
	   wire 			sw_gnt;
	   assign sw_gnt = sw_gnt_ivc[ivc];
	   
	   wire 			flit_sent_prev;
	   assign flit_sent_prev = flit_sent_prev_ivc[ivc];
	   wire [0:num_ports-1] 	route_op;
	   wire [0:num_resource_classes-1] route_orc;
	   wire [0:lar_info_width-1] 	   next_lar_info;
	   wire 			   flit_valid;
	   wire 			   flit_head;
	   wire 			   flit_tail;
	   wire [0:num_vcs-1] 		   flit_sel_ovc;
	   wire [0:flit_data_width-1] 	   flit_data;
	   wire 			   empty;
	   wire 			   full;
	   wire 			   allocated;
	   wire 			   free_nonspec;
	   wire 			   free_spec;
	   wire [0:5] 			   ivcc_errors;
	   

	   
	   
	   if (ivc == (num_vcs - 1)) begin
	      vcr_ivc_ctrl_justin
		    #(.num_flits_per_vc(num_flits_per_vc),
	              .num_message_classes(num_message_classes),
	              .num_resource_classes(num_resource_classes),
	              .num_vcs_per_class(num_vcs_per_class),
	              .num_routers_per_dim(num_routers_per_dim),
	              .num_dimensions(num_dimensions),
	              .num_nodes_per_router(num_nodes_per_router),
	              .connectivity(connectivity),
	              .packet_format(packet_format),
	              .max_payload_length(max_payload_length),
	              .min_payload_length(min_payload_length),
	              .flit_data_width(flit_data_width),
	              .restrict_turns(restrict_turns),
	              .routing_type(routing_type),
	              .dim_order(dim_order),
	              .int_flow_ctrl_type(int_flow_ctrl_type),
	              .elig_mask(elig_mask),
	              .sw_alloc_spec(sw_alloc_spec),
	              .fb_regfile_type(fb_regfile_type),
	              .explicit_pipeline_register(explicit_pipeline_register),
	              .gate_buffer_write(gate_buffer_write),
	              .vc_id(ivc),
	              .port_id(port_id),
	              .reset_type(reset_type),
	              .time_to_wait_width(time_to_wait_width))
	      ivcc_justin
		    (.clk(clk),
	             .reset(reset),
	             .router_address(router_address),
	             .flit_valid_in(flit_valid_in),
	             .flit_head_in(flit_head_in),
	             .flit_tail_in(flit_tail_in),
	             .flit_data_in(flit_data_in),
	             .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
	             .route_op(route_op),
	             .route_orc(route_orc),
	             .vc_gnt(vc_gnt),
	             .vc_gnt_ocvc(vc_gnt_ocvc),
	             .sw_gnt(sw_gnt),
	             .flit_sent_prev(flit_sent_prev),
	             .flit_tail_prev(flit_tail_prev),
	             .next_lar_info(next_lar_info),
	             .flit_valid(flit_valid),
	             .flit_head(flit_head),
	             .flit_tail(flit_tail),
	             .flit_sel_ovc(flit_sel_ovc),
	             .flit_data(flit_data),
	             .empty(empty),
	             .full(full),
	             .allocated(allocated),
	             .free_nonspec(free_nonspec),
	             .free_spec(free_spec),
	             .errors(ivcc_errors),
		     .expired(expired),
		     .cancel_vc(cancel_vc),
		     .drop_event(drop_event));
	      
	   end 
	   else 
	     begin		
		vcr_ivc_ctrl
		  #(.num_flits_per_vc(num_flits_per_vc),
		    .num_message_classes(num_message_classes),
		    .num_resource_classes(num_resource_classes),
		    .num_vcs_per_class(num_vcs_per_class),
		    .num_routers_per_dim(num_routers_per_dim),
		    .num_dimensions(num_dimensions),
		    .num_nodes_per_router(num_nodes_per_router),
		    .connectivity(connectivity),
		    .packet_format(packet_format),
		    .max_payload_length(max_payload_length),
		    .min_payload_length(min_payload_length),
		    .flit_data_width(flit_data_width),
		    .restrict_turns(restrict_turns),
		    .routing_type(routing_type),
		    .dim_order(dim_order),
		    .int_flow_ctrl_type(int_flow_ctrl_type),
		    .elig_mask(elig_mask),
		    .sw_alloc_spec(sw_alloc_spec),
		    .fb_regfile_type(fb_regfile_type),
		    .explicit_pipeline_register(explicit_pipeline_register),
		    .gate_buffer_write(gate_buffer_write),
		    .vc_id(ivc),
		    .port_id(port_id),
		    .reset_type(reset_type))
		ivcc
		  (.clk(clk),
		   .reset(reset),
		   .router_address(router_address),
		   .flit_valid_in(flit_valid_in),
		   .flit_head_in(flit_head_in),
		   .flit_tail_in(flit_tail_in),
		   .flit_data_in(flit_data_in),
		   .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
		   .route_op(route_op),
		   .route_orc(route_orc),
		   .vc_gnt(vc_gnt),
		   .vc_gnt_ocvc(vc_gnt_ocvc),
		   .sw_gnt(sw_gnt),
		   .flit_sent_prev(flit_sent_prev),
		   .flit_tail_prev(flit_tail_prev),
		   .next_lar_info(next_lar_info),
		   .flit_valid(flit_valid),
		   .flit_head(flit_head),
		   .flit_tail(flit_tail),
		   .flit_sel_ovc(flit_sel_ovc),
		   .flit_data(flit_data),
		   .empty(empty),
		   .full(full),
		   .allocated(allocated),
		   .free_nonspec(free_nonspec),
		   .free_spec(free_spec),
		   .errors(ivcc_errors));
		
	     end
	   
	   assign route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
	       = route_op;
	   assign route_ivc_orc[ivc*num_resource_classes:
				(ivc+1)*num_resource_classes-1]
	     = route_orc;
	   assign next_lar_info_ivc[ivc*lar_info_width:
				    (ivc+1)*lar_info_width-1] = next_lar_info;
	   assign flit_valid_ivc[ivc] = flit_valid;
	   assign flit_head_ivc[ivc] = flit_head;
	   assign flit_tail_ivc[ivc] = flit_tail;
	   assign flit_sel_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]
	     = flit_sel_ovc;
	   assign flit_data_ivc[ivc*flit_data_width:(ivc+1)*flit_data_width-1]
	     = flit_data;
	   assign empty_ivc[ivc] = empty;
	   assign full_ivc[ivc] = full;
	   assign allocated_ivc[ivc] = allocated;
	   assign free_nonspec_ivc[ivc] = free_nonspec;
	   assign free_spec_ivc[ivc] = free_spec;
	   assign ivcc_errors_ivc[ivc*6:(ivc+1)*6-1] = ivcc_errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // flit buffer read path
   //---------------------------------------------------------------------------
   
   wire 				   alloc_active;
   assign alloc_active = flit_valid_in | ~&empty_ivc;
   
   wire [0:num_vcs-1] 			   prev_sw_sel_ivc;
   
   wire [0:flit_data_width-1] 		   flit_data_buffered;
   
   generate
      
      if(explicit_pipeline_register)
	begin
	   
	   wire [0:flit_data_width-1] flit_data_s, flit_data_q;

	   if(num_vcs == 1)
	     assign flit_data_s = flit_data_ivc;
	   else if(num_vcs > 1)
	     begin
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_data_width))
		flit_data_s_sel
		  (.select(sw_sel_ivc),
		   .data_in(flit_data_ivc),
		   .data_out(flit_data_s));
		
	     end
	   
	   c_dff
	     #(.width(flit_data_width),
	       .reset_type(reset_type))
	   flit_dataq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
	      .d(flit_data_s),
	      .q(flit_data_q));
	   
	   assign flit_data_buffered = flit_data_q;
	   
	end
      else
	begin
	   
	   if(num_vcs == 1)
	     assign flit_data_buffered = flit_data_ivc;
	   else if(num_vcs > 1)
	     begin
		
		// In the absence of an explicit pipeline register between flit 
		// buffer and crossbar, buffer read is delayed by one clock 
		// cycle such as to line up the flit data with the crossbar 
		// control signals.
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_data_width))
		flit_data_buffered_sel
		  (.select(prev_sw_sel_ivc),
		   .data_in(flit_data_ivc),
		   .data_out(flit_data_buffered));
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // update lookahead routing info
   //---------------------------------------------------------------------------
   
   wire [0:lar_info_width-1] next_lar_info;
   generate
      if(num_vcs == 1)
	assign next_lar_info = next_lar_info_ivc;
      else
	begin
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(lar_info_width))
	   next_lar_info_sel
	     (.select(sw_sel_ivc),
	      .data_in(next_lar_info_ivc),
	      .data_out(next_lar_info));
	end
   endgenerate
   
   wire flit_head;

   wire [0:lar_info_width-1] lar_info_s, lar_info_q;
   assign lar_info_s = flit_head ? next_lar_info : lar_info_q;
   c_dff
     #(.width(lar_info_width),
       .reset_type(reset_type))
   lar_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(alloc_active),
      .d(lar_info_s),
      .q(lar_info_q));
   
   wire 		     flit_head_prev;
   
   assign flit_data[0:lar_info_width-1]
     = flit_head_prev ? lar_info_q : flit_data_buffered[0:lar_info_width-1];
   assign flit_data[lar_info_width:flit_data_width-1]
     = flit_data_buffered[lar_info_width:flit_data_width-1];
   
   
   //---------------------------------------------------------------------------
   // generate signals to crossbar module
   //---------------------------------------------------------------------------
   
   // NOTE: Because we need to clear it in the cycle after a flit / credit has 
   // been transmitted, this register cannot be included in any of the other 
   // clock gating domains. If we could change things such that flits are 
   // transmitted using edge-based signaling (i.e., transitions), they could be 
   // included in the clock gating domain controlled by alloc_active.
   // Alternatively, we could include the flit_valid_q term in alloc_active;
   // this would allow us to include flit_validq in the gating domain at 
   // the cost of some unnecessary activity. As synthesis will probably not 
   // create a clock gating domain for just these two registers, they currently 
   // will most likely end up being free-running, so this may be a reasonable 
   // tradeoff.
   
   wire 		     flit_sent_prev;
   
   wire 		     flit_valid_active;
   assign flit_valid_active = alloc_active | flit_sent_prev;
   
   wire 		     flit_valid_s, flit_valid_q;
   assign flit_valid_s = flit_sent;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .active(flit_valid_active),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   assign flit_sent_prev = flit_valid_q;
   assign int_flit_ctrl[0] = flit_valid_q;
   
   wire 		     flit_tail;
   
   generate
      
      if(num_vcs == 1)
	begin
	   assign flit_head = flit_head_ivc;
	   assign flit_tail = flit_tail_ivc;
	end
      else if(num_vcs > 1)
	begin
	   
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(1))
	   flit_head_sel
	     (.select(sw_sel_ivc),
	      .data_in(flit_head_ivc),
	      .data_out(flit_head));
	   
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(1))
	   flit_tail_sel
	     (.select(sw_sel_ivc),
	      .data_in(flit_tail_ivc),
	      .data_out(flit_tail));
	   
	end
      
   endgenerate
   
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
   assign int_flit_ctrl[1+0] = flit_head_q;
   
   wire flit_tail_s, flit_tail_q;
   assign flit_tail_s = flit_tail;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_tailq
     (.clk(clk),
      .reset(1'b0),
      .active(alloc_active),
      .d(flit_tail_s),
      .q(flit_tail_q));
   
   assign flit_tail_prev = flit_tail_q;
   assign int_flit_ctrl[1+1] = flit_tail_q;
   
   generate
      
      if(num_vcs == 1)
	begin
	   assign int_flit_ctrl[1+2+0] = 1'b1;
	   assign prev_sw_sel_ivc = 1'b1;
	   assign flit_sent_prev_ivc = flit_valid_q;
	end
      else if(num_vcs > 1)
	begin
	   
	   wire [0:num_vcs-1] flit_sel_ovc;
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(num_vcs))
	   flit_sel_ovc_sel
	     (.select(sw_sel_ivc),
	      .data_in(flit_sel_ivc_ovc),
	      .data_out(flit_sel_ovc));
	   
	   wire [0:num_vcs-1] flit_sel_ovc_s, flit_sel_ovc_q;
	   assign flit_sel_ovc_s = flit_sel_ovc;
	   c_dff
	     #(.width(num_vcs),
	       .reset_type(reset_type))
	   flit_sel_ovcq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
	      .d(flit_sel_ovc_s),
	      .q(flit_sel_ovc_q));
	   
	   assign int_flit_ctrl[1+2+0:1+2+num_vcs-1] = flit_sel_ovc_q;
	   
	   wire [0:num_vcs-1] sw_sel_ivc_s, sw_sel_ivc_q;
	   assign sw_sel_ivc_s = sw_sel_ivc;
	   c_dff
	     #(.width(num_vcs),
	       .reset_type(reset_type))
	   sw_sel_ivcq
	     (.clk(clk),
	      .reset(reset),
	      .active(alloc_active),
	      .d(sw_sel_ivc_s),
	      .q(sw_sel_ivc_q));
	   
	   assign prev_sw_sel_ivc = sw_sel_ivc_q;
	   
	   assign flit_sent_prev_ivc
	     = {num_vcs{flit_valid_q}} & sw_sel_ivc_q;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate outgoing flow control signals
   //---------------------------------------------------------------------------
   //CAUTION hardcoded Speculative VC
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fco
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .fc_event_valid_in(flit_sent|drop_event),
      .fc_event_sel_in_ivc(sw_sel_ivc|{3'b0,drop_event}),
      .flow_ctrl_out(flow_ctrl_out));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_vcs*6-1] errors_s, errors_q;
	   assign errors_s = ivcc_errors_ivc;
	   c_err_rpt
	     #(.num_errors(num_vcs*6),
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
