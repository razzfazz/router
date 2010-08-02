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

module vcr_ip_ctrl_mac
  (clk, reset, router_address, channel_in, route_ivc_op, route_ivc_orc, 
   vc_req_ivc, vc_gnt_ivc, vc_gnt_ivc_ocvc, sw_alloc_out_op, sw_alloc_in_op, 
   xbr_active, int_flit_ctrl_out, flit_data_out, flow_ctrl_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
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
   
   // width required for routing information for a single hop
   localparam hop_route_info_width = port_idx_width + resource_class_idx_width;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
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
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
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
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width = 1 + vc_idx_width + 1 + 1;
   
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
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for head/tail register file
   parameter htff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for header data FIFO register file
   parameter hdff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 0;
   
   // select implementation variant for VC allocator
   parameter vc_alloc_type = `VC_ALLOC_TYPE_SEP_IF;
   
   // select whether VCs must have credits available in order to be considered 
   // for VC allocation
   parameter vc_alloc_requires_credit = 0;
   
   // select implementation variant for switch allocator
   parameter sw_alloc_type = `SW_ALLOC_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_alloc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type for switch allocator
   parameter sw_alloc_spec_type = `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS;
   
   // number of bits required for request signals
   localparam sw_alloc_req_width
     = (sw_alloc_spec_type == `SW_ALLOC_SPEC_TYPE_NONE) ? 1 : (1 + 1);
   
   // number of bits required for grant signals
   localparam sw_alloc_gnt_width = sw_alloc_req_width;
   
   // width of outgoing allocator control signals
   localparam sw_alloc_out_width
     = (sw_alloc_type == `SW_ALLOC_TYPE_SEP_IF) ? 
       sw_alloc_req_width : 
       (sw_alloc_type == `SW_ALLOC_TYPE_SEP_OF) ? 
       (sw_alloc_req_width + sw_alloc_gnt_width + 
	((sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE) ? 1 : 0)) : 
       ((sw_alloc_type >= `SW_ALLOC_TYPE_WF_BASE) && 
	(sw_alloc_type <= `SW_ALLOC_TYPE_WF_LIMIT)) ? 
       sw_alloc_req_width : 
       -1;
   
   // width of incoming allocator control signals
   localparam sw_alloc_in_width
     = (sw_alloc_type == `SW_ALLOC_TYPE_SEP_IF) ? 
       (sw_alloc_gnt_width + num_vcs*int_flow_ctrl_width) : 
       (sw_alloc_type == `SW_ALLOC_TYPE_SEP_OF) ? 
       (sw_alloc_gnt_width + num_vcs*int_flow_ctrl_width) :
       ((sw_alloc_type >= `SW_ALLOC_TYPE_WF_BASE) && 
	(sw_alloc_type <= `SW_ALLOC_TYPE_WF_LIMIT)) ? 
       (sw_alloc_gnt_width + num_vcs*int_flow_ctrl_width) : 
       -1;
   
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
   
   // destination port
   output [0:num_vcs*num_ports-1] route_ivc_op;
   wire [0:num_vcs*num_ports-1]   route_ivc_op;
   
   // select next resource class
   output [0:num_vcs*num_resource_classes-1] route_ivc_orc;
   wire [0:num_vcs*num_resource_classes-1]   route_ivc_orc;
   
   // request VC allocation
   output [0:num_vcs-1] 		     vc_req_ivc;
   wire [0:num_vcs-1] 			     vc_req_ivc;
   
   // VC allocation successful
   input [0:num_vcs-1] 			     vc_gnt_ivc;
   
   // granted output VC
   input [0:num_vcs*num_vcs_per_class-1]     vc_gnt_ivc_ocvc;
   
   // outgoing allocator contorl signals
   output [0:num_ports*sw_alloc_out_width-1] sw_alloc_out_op;
   wire [0:num_ports*sw_alloc_out_width-1]   sw_alloc_out_op;
   
   // incoming allocator control signals
   input [0:num_ports*sw_alloc_in_width-1]   sw_alloc_in_op;
   
   // crossbar enable signal
   output 				     xbr_active;
   wire 				     xbr_active;
   
   // outgoing flit control signals
   output [0:int_flit_ctrl_width-1] 	     int_flit_ctrl_out;
   wire [0:int_flit_ctrl_width-1] 	     int_flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] 	     flit_data_out;
   wire [0:flit_data_width-1] 		     flit_data_out;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] 	     flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 		     flow_ctrl_out;
   
   // internal error condition detected
   output 				     error;
   wire 				     error;
   
   
   //---------------------------------------------------------------------------
   // pack / unpack switch allocator control signals
   //---------------------------------------------------------------------------
   
   // non-speculative switch allocation requests to output-side arbitration 
   // stage / wavefront block
   wire [0:num_ports-1] 		     sw_oreq_nonspec_op;
   
   // speculative switch allocation requests to output-side arbitration stage or
   // wavefront block
   wire [0:num_ports-1] 		     sw_oreq_spec_op;
   
   // non-speculative switch allocation grants from output-side arbitration 
   // stage / wavefront block
   wire [0:num_ports-1] 		     sw_ognt_nonspec_op;
   
   // speculative switch allocation grants from output-side arbitration stage or
   // wavefront block
   wire [0:num_ports-1] 		     sw_ognt_spec_op;
   
   // non-speculative switch allocation grants to output-side arbitration stage 
   // or wavefront block
   wire [0:num_ports-1] 		     sw_ignt_nonspec_op;
   
   // speculative switch allocation grants to output-side arbitration stage or 
   // wavefront block
   wire [0:num_ports-1] 		     sw_ignt_spec_op;
   
   // internal flow control signalling from output controller to input 
   // controllers
   wire [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   genvar 					    op;
   
   generate
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:sw_alloc_in_width-1] sw_alloc_in;
	   assign sw_alloc_in
	     = sw_alloc_in_op[op*sw_alloc_in_width:
			      (op+1)*sw_alloc_in_width-1];
	   
	   wire [0:sw_alloc_out_width-1] sw_alloc_out;
	   
	   assign sw_alloc_out[0] = sw_oreq_nonspec_op[op];
	   
	   if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	     assign sw_alloc_out[1] = sw_oreq_spec_op[op];
	   
	   assign sw_ognt_nonspec_op[op] = sw_alloc_in[0];
	   
	   if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	     assign sw_ognt_spec_op[op] = sw_alloc_in[1];
	   else
	     assign sw_ognt_spec_op[op] = 1'b0;
	   
	   if(sw_alloc_type == `SW_ALLOC_TYPE_SEP_IF)
	     begin
		
		assign int_flow_ctrl_op_ovc[op*num_vcs*
					    int_flow_ctrl_width:
					    (op+1)*num_vcs*
					    int_flow_ctrl_width-1]
			 = sw_alloc_in[sw_alloc_gnt_width:
				       sw_alloc_gnt_width+
				       num_vcs*int_flow_ctrl_width-1];
		
	     end
	   else if(sw_alloc_type == `SW_ALLOC_TYPE_SEP_OF)
	     begin
		
		assign sw_alloc_out[sw_alloc_req_width]
			 = sw_ignt_nonspec_op[op];
		
		if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
		  assign sw_alloc_out[sw_alloc_req_width+1]
			   = sw_ignt_spec_op[op];
		
		assign int_flow_ctrl_op_ovc[op*num_vcs*
					    int_flow_ctrl_width:
					    (op+1)*num_vcs*
					    int_flow_ctrl_width-1]
			 = sw_alloc_in[sw_alloc_gnt_width:
				       sw_alloc_gnt_width+
				       num_vcs*int_flow_ctrl_width-1];
		
		if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
		  begin
		     
		     wire sw_gnt;
		     assign sw_gnt
		       = sw_ignt_nonspec_op[op] | sw_ignt_spec_op[op];
		     
		     assign sw_alloc_out[sw_alloc_req_width+sw_alloc_gnt_width]
			      = sw_gnt;
		     
		  end
		
	     end
	   else if((sw_alloc_type >= `SW_ALLOC_TYPE_WF_BASE) &&
		   (sw_alloc_type <= `SW_ALLOC_TYPE_WF_LIMIT))
	     begin
		
		assign int_flow_ctrl_op_ovc[op*num_vcs*
					    int_flow_ctrl_width:
					    (op+1)*num_vcs*
					    int_flow_ctrl_width-1]
			 = sw_alloc_in[sw_alloc_gnt_width:
				       sw_alloc_gnt_width+
				       num_vcs*int_flow_ctrl_width-1];
		
	     end
	   
	   assign sw_alloc_out_op[op*sw_alloc_out_width:
				  (op+1)*sw_alloc_out_width-1]
		    = sw_alloc_out;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] fbc_full_ivc;
   
   wire 	      input_stage_active;
   assign input_stage_active = ~&fbc_full_ivc;
   
   wire 	      flit_valid_in;
   wire 	      flit_head_in;
   wire 	      flit_tail_in;
   wire [0:flit_data_width-1] flit_data_in;
   wire [0:num_vcs-1] 	      flit_sel_in_ivc;
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
      .active(input_stage_active),
      .channel_in(channel_in),
      .flit_valid_out(flit_valid_in),
      .flit_head_out(flit_head_in),
      .flit_tail_out(flit_tail_in),
      .flit_data_out(flit_data_in),
      .flit_sel_out_ivc(flit_sel_in_ivc));
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   wire 		      buffer_active;
   assign buffer_active = flit_valid_in;
   
   // extract header information from header data
   wire [0:header_info_width-1] header_info_in;
   assign header_info_in = flit_data_in[0:header_info_width-1];
   
   // non-speculative switch allocator requests
   wire [0:num_vcs-1] 		sw_req_nonspec_ivc;
   
   // non-speculative switch allocator grants
   wire [0:num_vcs-1] 		sw_gnt_nonspec_ivc;
   
   // speculative switch allocator requests
   wire [0:num_vcs-1] 		sw_req_spec_ivc;
   
   // speculative switch allocator grants
   wire [0:num_vcs-1] 		sw_gnt_spec_ivc;
   
   wire [0:num_vcs-1] 		flit_valid_in_ivc;
   assign flit_valid_in_ivc = {num_vcs{flit_valid_in}} & flit_sel_in_ivc;
   
   wire [0:num_vcs-1] 		flit_sent_prev_ivc;
   wire [0:num_vcs-1] 		flit_head_ivc;
   wire [0:num_vcs-1] 		flit_tail_ivc;
   wire [0:num_vcs*header_info_width-1] header_info_ivc;
   wire [0:num_vcs*fbf_addr_width-1] 	fbc_push_addr_ivc;
   wire [0:num_vcs*fbf_addr_width-1] 	fbc_pop_addr_ivc;
   wire [0:num_vcs-1] 			fbc_empty_ivc;
   wire [0:num_vcs-1] 			allocated_ivc;
   wire [0:num_vcs*num_vcs-1] 		allocated_ivc_ovc;
   wire [0:num_vcs-1] 			free_unallocated_ivc;
   wire [0:num_vcs-1] 			free_allocated_ivc;
   wire [0:num_vcs*8-1] 		ivcc_errors_ivc;
   
   genvar 				ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire flit_valid_in;
	   assign flit_valid_in = flit_valid_in_ivc[ivc];
	   
	   wire vc_gnt;
	   assign vc_gnt = vc_gnt_ivc[ivc];
	   
	   wire [0:num_vcs_per_class-1] vc_gnt_ocvc;
	   assign vc_gnt_ocvc = vc_gnt_ivc_ocvc[ivc*num_vcs_per_class:
						(ivc+1)*num_vcs_per_class-1];
	   
	   wire 			sw_gnt_nonspec;
	   assign sw_gnt_nonspec = sw_gnt_nonspec_ivc[ivc];
	   
	   wire 			sw_gnt_spec;
	   assign sw_gnt_spec = sw_gnt_spec_ivc[ivc];
	   
	   wire 			flit_sent_prev;
	   assign flit_sent_prev = flit_sent_prev_ivc[ivc];
	   
	   wire [0:num_ports-1] 	route_op;
	   wire [0:num_resource_classes-1] route_orc;
	   wire 			   vc_req;
	   wire 			   sw_req_nonspec;
	   wire 			   sw_req_spec;	   
	   wire 			   flit_head;
	   wire 			   flit_tail;
	   wire [0:header_info_width-1]    header_info_out;
	   wire [0:fbf_addr_width-1] 	   fbc_push_addr;
	   wire [0:fbf_addr_width-1] 	   fbc_pop_addr;
	   wire 			   fbc_empty;
	   wire 			   fbc_full;
	   wire 			   allocated;
	   wire [0:num_vcs-1] 		   allocated_ovc;
	   wire 			   free_unallocated;
	   wire 			   free_allocated;
	   wire [0:7] 			   ivcc_errors;
	   vcr_ivc_ctrl
	     #(.num_flits_per_vc(num_flits_per_vc),
	       .num_packets_per_vc(num_packets_per_vc),
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
	       .track_vcs_at_output(track_vcs_at_output),
	       .restrict_turns(restrict_turns),
	       .lookahead_routing(lookahead_routing),
	       .routing_type(routing_type),
	       .dim_order(dim_order),
	       .int_flow_ctrl_type(int_flow_ctrl_type),
	       .vc_alloc_type(vc_alloc_type),
	       .vc_alloc_requires_credit(vc_alloc_requires_credit),
	       .sw_alloc_spec_type(sw_alloc_spec_type),
	       .htff_regfile_type(htff_regfile_type),
	       .hdff_regfile_type(hdff_regfile_type),
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
	      .header_info_in(header_info_in),
	      .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
	      .route_op(route_op),
	      .route_orc(route_orc),
	      .vc_req(vc_req),
	      .vc_gnt(vc_gnt),
	      .vc_gnt_ocvc(vc_gnt_ocvc),
	      .sw_req_nonspec(sw_req_nonspec),
	      .sw_req_spec(sw_req_spec),
	      .sw_gnt_nonspec(sw_gnt_nonspec),
	      .sw_gnt_spec(sw_gnt_spec),
	      .flit_sent_prev(flit_sent_prev),
	      .flit_head(flit_head),
	      .flit_tail(flit_tail),
	      .header_info_out(header_info_out),
	      .fbc_push_addr(fbc_push_addr),
	      .fbc_pop_addr(fbc_pop_addr),
	      .fbc_empty(fbc_empty),
	      .fbc_full(fbc_full),
	      .allocated(allocated),
	      .allocated_ovc(allocated_ovc),
	      .free_unallocated(free_unallocated),
	      .free_allocated(free_allocated),
	      .errors(ivcc_errors));
	   
	   assign route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
	     = route_op;
	   assign route_ivc_orc[ivc*num_resource_classes:
				(ivc+1)*num_resource_classes-1]
	     = route_orc;
	   assign vc_req_ivc[ivc] = vc_req;
	   assign sw_req_nonspec_ivc[ivc] = sw_req_nonspec;
	   assign sw_req_spec_ivc[ivc] = sw_req_spec;
	   assign flit_head_ivc[ivc] = flit_head;
	   assign flit_tail_ivc[ivc] = flit_tail;
	   assign header_info_ivc[ivc*header_info_width:
				  (ivc+1)*header_info_width-1]
	     = header_info_out;
	   assign fbc_push_addr_ivc[ivc*fbf_addr_width:
				     (ivc+1)*fbf_addr_width-1]
	     = fbc_push_addr;
	   assign fbc_pop_addr_ivc[ivc*fbf_addr_width:
				    (ivc+1)*fbf_addr_width-1]
	     = fbc_pop_addr;
	   assign fbc_empty_ivc[ivc] = fbc_empty;
	   assign fbc_full_ivc[ivc] = fbc_full;
	   assign allocated_ivc[ivc] = allocated;
	   assign allocated_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]
	     = allocated_ovc;
	   assign free_unallocated_ivc[ivc] = free_unallocated;
	   assign free_allocated_ivc[ivc] = free_allocated;
	   assign ivcc_errors_ivc[ivc*8:(ivc+1)*8-1] = ivcc_errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // switch allocation
   //---------------------------------------------------------------------------
   
   wire 				flit_valid;
   assign flit_valid = flit_valid_in | ~&fbc_empty_ivc;
   
   wire 				alloc_active;
   assign alloc_active = flit_valid;
   
   wire [0:num_vcs-1] 			sw_req_nonspec_qual_ivc;
   assign sw_req_nonspec_qual_ivc = sw_req_nonspec_ivc & free_allocated_ivc;
   
   wire [0:num_vcs-1] 			vc_sel_nonspec_ivc;
   
   vcr_sw_alloc_ip
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .allocator_type(sw_alloc_type),
       .arbiter_type(sw_alloc_arbiter_type),
       .reset_type(reset_type))
   swa_nonspec
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .route_ivc_op(route_ivc_op),
      .req_in_ivc(sw_req_nonspec_qual_ivc),
      .req_out_op(sw_oreq_nonspec_op),
      .gnt_in_op(sw_ognt_nonspec_op),
      .gnt_out_ivc(sw_gnt_nonspec_ivc),
      .gnt_out_op(sw_ignt_nonspec_op),
      .sel_ivc(vc_sel_nonspec_ivc),
      .allow_update(1'b1));
   
   
   //---------------------------------------------------------------------------
   // speculative switch allocation support
   //---------------------------------------------------------------------------
   
   // any non-speculative grants?
   wire 				sw_ognt_nonspec;
   assign sw_ognt_nonspec = |sw_ognt_nonspec_op;
   
   wire [0:num_vcs-1] 			vc_sel_spec_ivc;
   wire [0:num_vcs-1] 			vc_sel_ivc;
   wire 				flit_sent;
   
   generate
      
      if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	begin
	   
	   // any non-speculative requests?
	   wire sw_req_nonspec;
	   assign sw_req_nonspec = |sw_req_nonspec_ivc;
	   
	   wire [0:num_ports-1] sw_oreq_spec_unqual_op;
	   wire [0:num_vcs-1] 	sw_gnt_spec_unqual_ivc;
	   wire [0:num_ports-1] sw_ignt_spec_unqual_op;
	   wire 		allow_update_spec;
	   vcr_sw_alloc_ip
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .allocator_type(sw_alloc_type),
	       .arbiter_type(sw_alloc_arbiter_type),
	       .reset_type(reset_type))
	   swa_spec
	     (.clk(clk),
	      .reset(reset),
	      .active(alloc_active),
	      .route_ivc_op(route_ivc_op),
	      .req_in_ivc(sw_req_spec_ivc),
	      .req_out_op(sw_oreq_spec_unqual_op),
	      .gnt_in_op(sw_ognt_spec_op),
	      .gnt_out_ivc(sw_gnt_spec_unqual_ivc),
	      .gnt_out_op(sw_ignt_spec_unqual_op),
	      .sel_ivc(vc_sel_spec_ivc),
	      .allow_update(allow_update_spec));
	   
	   wire [0:num_vcs-1] 	sw_gnt_spec_qual_ivc;
	   if(vc_alloc_requires_credit)
	     assign sw_gnt_spec_qual_ivc = sw_gnt_spec_unqual_ivc;
	   else
	     assign sw_gnt_spec_qual_ivc
	       = sw_gnt_spec_unqual_ivc & free_unallocated_ivc;
	   
	   if(sw_alloc_type == `SW_ALLOC_TYPE_SEP_IF)
	     begin
		
		// no additional masking is required for speculative grants
		assign sw_gnt_spec_ivc = sw_gnt_spec_qual_ivc;
		assign sw_ignt_spec_op = sw_ignt_spec_unqual_op;
		
		// updates are masked indirectly via output-side grants
		assign allow_update_spec = 1'b1;
		
		case(sw_alloc_spec_type)
		  
		  `SW_ALLOC_SPEC_TYPE_REQS_MASK_REQS,
		  `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS:
		    begin
		       
		       // do not propagate speculative requests if any 
		       // non-speculative requests were issued by this input's 
		       // VCs
		       assign sw_oreq_spec_op = {num_ports{~sw_req_nonspec}} & 
						sw_oreq_spec_unqual_op;
		       
		       // flit buffer read address can be determined early
		       assign vc_sel_ivc = sw_req_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_GNTS_MASK_REQS,
		  `SW_ALLOC_SPEC_TYPE_GNTS_MASK_GNTS:
		    begin
		       
		       // do not propagate requests if a non-speculative grant 
		       // was generated for this input
		       assign sw_oreq_spec_op = {num_ports{~sw_ognt_nonspec}} & 
						sw_oreq_spec_unqual_op;
		       
		       // we only know whether to use non-speculative or 
		       // speculative flits once the output-side grants are 
		       // known
		       assign vc_sel_ivc = sw_ognt_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		    end
		  
		endcase
		
	     end
	   else if(sw_alloc_type == `SW_ALLOC_TYPE_SEP_OF)
	     begin
		
		case(sw_alloc_spec_type)
		  
		  `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS:
		    begin
		       
		       // propagate all speculative requests
		       assign sw_oreq_spec_op = sw_oreq_spec_unqual_op;
		       
		       // suppress speculative grants if any non-speculative 
		       // requests were issued by this input's VCs
		       assign sw_gnt_spec_ivc = {num_vcs{~sw_req_nonspec}} & 
						sw_gnt_spec_qual_ivc;
		       assign sw_ignt_spec_op = {num_ports{~sw_req_nonspec}} & 
						sw_ignt_spec_unqual_op;
		       
		       // flit buffer read address can be determined early
		       assign vc_sel_ivc = sw_req_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		       // inhibit updates if non-speculative requests are 
		       // present
		       assign allow_update_spec = ~sw_req_nonspec;
		       
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_REQS_MASK_REQS:
		    begin
		       
		       // do not propagate speculative requests if any 
		       // non-speculative requests were issued by this input's 
		       // VCs
		       assign sw_oreq_spec_op = {num_ports{~sw_req_nonspec}} & 
						sw_oreq_spec_unqual_op;
		       
		       // no additional masking is required for speculative 
		       // grants
		       assign sw_gnt_spec_ivc = sw_gnt_spec_qual_ivc;
		       assign sw_ignt_spec_op = sw_ignt_spec_unqual_op;
		       
		       // flit buffer read address can be determined early
		       assign vc_sel_ivc = sw_req_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		       // updates are masked indirectly via output-side grants
		       assign allow_update_spec = 1'b1;
		       
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_GNTS_MASK_GNTS:
		    begin
		       
		       // propagate all speculative requests
		       assign sw_oreq_spec_op = sw_oreq_spec_unqual_op;
		       
		       // suppress speculative grants if any non-speculative 
		       // grants were generated for this input
		       assign sw_gnt_spec_ivc = {num_vcs{~sw_ognt_nonspec}} & 
						sw_gnt_spec_qual_ivc;
		       assign sw_ignt_spec_op = {num_ports{~sw_ognt_nonspec}} & 
						sw_ignt_spec_unqual_op;
		       
		       // we only know whether to use non-speculative or 
		       // speculative flits once the output-side grants are 
		       // known
		       assign vc_sel_ivc = sw_ognt_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		       // inhibit updates if non-speculative grants are present
		       assign allow_update_spec = ~sw_ognt_nonspec;
		       
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_GNTS_MASK_REQS:
		    begin
		       
		       // do not propagate requests if a non-speculative grant 
		       // was generated for this input
		       assign sw_oreq_spec_op = {num_ports{~sw_ognt_nonspec}} & 
						sw_oreq_spec_unqual_op;
		       
		       // no additional masking requiured for grants
		       assign sw_gnt_spec_ivc = sw_gnt_spec_qual_ivc;
		       assign sw_ignt_spec_op = sw_ignt_spec_unqual_op;
		       
		       // we only know whether to use non-speculative or 
		       // speculative flits once the output-side grants are 
		       // known
		       assign vc_sel_ivc = sw_ognt_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		       // updates are masked indirectly via output-side grants
		       assign allow_update_spec = 1'b1;
		       
		    end
		  
		endcase
		
	     end
	   else if((sw_alloc_type >= `SW_ALLOC_TYPE_WF_BASE) &&
		   (sw_alloc_type <= `SW_ALLOC_TYPE_WF_LIMIT))
	     begin
		
		// propagate all speculative requests
		assign sw_oreq_spec_op = sw_oreq_spec_unqual_op;
		
		// all masking is done inside the wavefront block, so we can 
		// just propagate grants
		assign sw_gnt_spec_ivc = sw_gnt_spec_qual_ivc;
		assign sw_ignt_spec_op = sw_ignt_spec_unqual_op;
		
		case(sw_alloc_spec_type)
		  
		  `SW_ALLOC_SPEC_TYPE_REQS_MASK_REQS,
		  `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS:
		    begin
		       
		       // flit buffer read address can be determined early
		       assign vc_sel_ivc = sw_req_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		       // inhibit updates if non-speculative requests are 
		       // present
		       assign allow_update_spec = ~sw_req_nonspec;
		       
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_GNTS_MASK_REQS,
		  `SW_ALLOC_SPEC_TYPE_GNTS_MASK_GNTS:
		    begin
		       
		       // flit buffer read address depends on whether a 
		       // non-speculative grant was generated
		       assign vc_sel_ivc = sw_ognt_nonspec ? 
					   vc_sel_nonspec_ivc : 
					   vc_sel_spec_ivc;
		       
		       // inhibit updates if non-speculative grant was generated
		       assign allow_update_spec = ~sw_ognt_nonspec;
		       
		    end
		  
		endcase
		
	     end
	   
	   // if any output port was granted to this input port 
	   // non-speculatively, we know that a flit will be sent out
	   wire flit_sent_nonspec;
	   assign flit_sent_nonspec = sw_ognt_nonspec;
	   
	   // for speculative grants, on the other hand, we must make sure that 
	   // no misspeculation occurred
	   wire flit_sent_spec;
	   
	   if(sw_alloc_type == `SW_ALLOC_TYPE_SEP_IF)
	     begin
		
		// for the separable input-first case, we can use a shortcut by 
		// exploiting the fact that the VC select signal is available 
		// early
		if(vc_alloc_requires_credit)
		  assign flit_sent_spec
		    = |sw_ognt_spec_op & |(vc_gnt_ivc & vc_sel_spec_ivc);
		else
		  assign flit_sent_spec
		    = |sw_ognt_spec_op & 
		      |(vc_gnt_ivc & vc_sel_spec_ivc & free_unallocated_ivc);
		
	     end
	   else if((sw_alloc_type == `SW_ALLOC_TYPE_SEP_OF) || 
		   ((sw_alloc_type >= `SW_ALLOC_TYPE_WF_BASE) && 
		    (sw_alloc_type <= `SW_ALLOC_TYPE_WF_LIMIT)))
	     begin
		
		// for separable output-first and wavefront allocation, we don't
		// know until the end of allocation which input-side VC was 
		// selected
		assign flit_sent_spec = |(vc_gnt_ivc & sw_gnt_spec_ivc);
		
	     end
	   
	   // at most one of the two should ever be active
	   assign flit_sent = flit_sent_nonspec | flit_sent_spec;
	   
	end
      else
	begin
	   
	   // if speculation is disabled, tie controls signals to zero
	   assign sw_gnt_spec_ivc = {num_vcs{1'b0}};
	   assign sw_oreq_spec_op = {num_ports{1'b0}};
	   assign sw_ignt_spec_op = {num_ports{1'b0}};
	   
	   // selector for flit buffer read address
	   assign vc_sel_spec_ivc = {num_vcs{1'b0}};
	   assign vc_sel_ivc = vc_sel_nonspec_ivc;
	   
	   // in the absence of speculation, if any output port was granted to 
	   // this input port, we know that a flit will be sent out
	   assign flit_sent = sw_ognt_nonspec;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire [0:header_info_width-1] header_info_out;
   c_select_1ofn
     #(.num_ports(num_vcs),
       .width(header_info_width))
   header_info_out_sel
     (.select(flit_sel_in_ivc),
      .data_in(header_info_ivc),
      .data_out(header_info_out));
   
   wire [0:flit_data_width-1] 	fbf_write_data;
   assign fbf_write_data[0:header_info_width-1]
     = flit_head_in ? header_info_out : header_info_in;
   assign fbf_write_data[header_info_width:flit_data_width-1]
     = flit_data_in[header_info_width:flit_data_width-1];
   
   wire [0:fbf_addr_width-1] 	fbc_push_addr;
   wire [0:fbf_addr_width-1] 	fbc_pop_addr;
   wire 			fbf_write_enable;
   wire 			fbf_read_active;
   wire 			fbf_read_enable;
   wire [0:fbf_addr_width-1] 	fbf_read_addr;
   wire [0:flit_data_width-1] 	fbf_read_data;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(fbf_addr_width))
	   fbc_push_addr_sel
	     (.select(flit_sel_in_ivc),
	      .data_in(fbc_push_addr_ivc),
	      .data_out(fbc_push_addr));
	   
	   c_select_1ofn
	     #(.num_ports(num_vcs),
	       .width(fbf_addr_width))
	   fbc_pop_addr_sel
	     (.select(vc_sel_ivc),
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
	   assign fbf_bypass = |(vc_sel_ivc & fbc_empty_ivc);
	   
	   assign fbf_write_enable = flit_valid_in & ~(fbf_bypass & flit_sent);
	   
	   assign fbf_read_active = alloc_active;
	   
	   assign fbf_read_enable = flit_sent;
	   
	   assign fbf_read_addr = fbc_pop_addr;
	   
	   wire [0:flit_data_width-1] flit_data_muxed;
	   assign flit_data_muxed = fbf_bypass ? fbf_write_data : fbf_read_data;
	   
	   wire [0:flit_data_width-1] flit_data_s, flit_data_q;
	   assign flit_data_s = flit_sent ? flit_data_muxed : flit_data_q;
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
	   
	   assign fbf_write_enable = flit_valid_in;
	   
	   wire fbf_read_enable_s, fbf_read_enable_q;
	   assign fbf_read_enable_s = flit_sent;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   fbf_read_enableq
	     (.clk(clk),
	      .reset(reset),
	      .active(alloc_active),
	      .d(fbf_read_enable_s),
	      .q(fbf_read_enable_q));
	   
	   assign fbf_read_active = fbf_read_enable_q;
	   assign fbf_read_enable = fbf_read_enable_q;
	   
	   wire [0:fbf_addr_width-1] fbf_read_addr_s, fbf_read_addr_q;
	   assign fbf_read_addr_s = flit_sent ? fbc_pop_addr : fbf_read_addr_q;
	   c_dff
	     #(.width(fbf_addr_width),
	       .reset_type(reset_type))
	   fbf_read_addrq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
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
   // generate signals to crossbar module
   //---------------------------------------------------------------------------
   
   // NOTE: Because we need to clear it in the cycle after a flit / credit has 
   // been transmitted, this register cannot be included in any of the other 
   // clock gating domains. If we could change things such that flits are 
   // transmitted using edge-based signaling (i.e., transitions), they could be 
   // included in the clock gating domain controlled by alloc_active.
   // Alternatively, we could include the flit_valid_out_q term in alloc_active;
   // this would allow us to include flit_valid_outq in the gating domain at 
   // the cost of some unnecessary activity. As synthesis will probably not 
   // create a clock gating domain for just these two registers, they currently 
   // will most likely end up being free-running, so this may be a reasonable 
   // tradeoff.
   
   wire 			     flit_valid_out_q;
   
   wire 			     valid_out_active;
   assign valid_out_active = flit_valid | flit_valid_out_q;
   
   wire 			     flit_valid_out_s;
   assign flit_valid_out_s = flit_sent;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_valid_outq
     (.clk(clk),
      .reset(reset),
      .active(valid_out_active),
      .d(flit_valid_out_s),
      .q(flit_valid_out_q));
   
   assign int_flit_ctrl_out[0] = flit_valid_out_q;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc;
	   c_encode
	     #(.num_ports(num_vcs))
	   flit_vc_enc
	     (.data_in(vc_sel_ivc),
	      .data_out(flit_vc));
	   
	   wire [0:vc_idx_width-1] vc_sel_s, vc_sel_q;
	   assign vc_sel_s = flit_vc;
	   c_dff
	     #(.width(vc_idx_width),
	       .reset_type(reset_type))
	   vc_selq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
	      .d(vc_sel_s),
	      .q(vc_sel_q));
	   
	   wire [0:num_vcs-1] 	   prev_vc_sel_ivc;
	   c_decode
	     #(.num_ports(num_vcs))
	   prev_vc_sel_ivc_dec
	     (.data_in(vc_sel_q),
	      .data_out(prev_vc_sel_ivc));
	   
	   assign flit_sent_prev_ivc
	     = {num_vcs{flit_valid_out_q}} & prev_vc_sel_ivc;
	   
	   if(track_vcs_at_output)
	     assign int_flit_ctrl_out[1:1+vc_idx_width-1] = vc_sel_q;
	   else
	     begin
		
		wire [0:num_vcs-1] allocated_ovc;
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(num_vcs))
		allocated_ovc_sel
		  (.select(vc_sel_ivc),
		   .data_in(allocated_ivc_ovc),
		   .data_out(allocated_ovc));
		
		wire [0:vc_idx_width-1] dest_vc_sel;
		c_encode
		  #(.num_ports(num_vcs))
		dest_vc_sel_enc
		  (.data_in(allocated_ovc),
		   .data_out(dest_vc_sel));
		
		wire [0:vc_idx_width-1] dest_vc_sel_s, dest_vc_sel_q;
		assign dest_vc_sel_s = dest_vc_sel;
		c_dff
		  #(.width(vc_idx_width),
		    .reset_type(reset_type))
		dest_vc_selq
		  (.clk(clk),
		   .reset(reset),
		   .active(alloc_active),
		   .d(dest_vc_sel_s),
		   .q(dest_vc_sel_q));
		
		assign int_flit_ctrl_out[1:1+vc_idx_width-1] = dest_vc_sel_q;
		
	     end
	   
	end
      else
	assign flit_sent_prev_ivc = flit_valid_out_q;
      
   endgenerate
   
   wire 					  flit_head_muxed;
   c_select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   flit_head_muxed_sel
     (.select(vc_sel_ivc),
      .data_in(flit_head_ivc),
      .data_out(flit_head_muxed));
   
   wire 					  flit_head_out_s, 
						  flit_head_out_q;
   assign flit_head_out_s = flit_head_muxed;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_head_outq
     (.clk(clk),
      .reset(1'b0),
      .active(alloc_active),
      .d(flit_head_out_s),
      .q(flit_head_out_q));
   
   assign int_flit_ctrl_out[1+vc_idx_width] = flit_head_out_q;
   
   wire 					  flit_tail_muxed;
   c_select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   flit_tail_muxed_sel
     (.select(vc_sel_ivc),
      .data_in(flit_tail_ivc),
      .data_out(flit_tail_muxed));
   
   wire 					  flit_tail_out_s, 
						  flit_tail_out_q;
   assign flit_tail_out_s = flit_tail_muxed;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_tail_outq
     (.clk(clk),
      .reset(1'b0),
      .active(alloc_active),
      .d(flit_tail_out_s),
      .q(flit_tail_out_q));
   
   assign int_flit_ctrl_out[1+vc_idx_width+1] = flit_tail_out_q;
   
   assign xbr_active = flit_valid;
   
   
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
      .fc_event_sel_in_ivc(vc_sel_ivc),
      .flow_ctrl_out(flow_ctrl_out));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_vcs*8-1] errors_s, errors_q;
	   assign errors_s = ivcc_errors_ivc;
	   c_err_rpt
	     #(.num_errors(num_vcs*8),
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
