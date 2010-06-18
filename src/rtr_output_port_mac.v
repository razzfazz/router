// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
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


// output port module
module rtr_output_port_mac
  (clk, reset, flow_ctrl_out, flow_ctrl_in, flit_data_in, elig_ovc, free_ovc, 
   free_plus1_ovc, act_ip, req_ip, req_ip_ovc, req_head_ip, req_tail_ip, gnt_ip,
   flit_ctrl_out, flit_data_out, error);
   
   
`include "c_functions.v"
`include "c_constants.v"
   
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // paramters
   //---------------------------------------------------------------------------
   
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
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_CREDIT;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
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
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // select which arbiter type to use for input-side arbitration
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
      
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
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
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = port_idx_width + ((num_resource_classes > 1) ? 1 : 0);
   
   // offset of lookahead routing information in flit data
   localparam la_route_info_offset = 0;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // offset of routing information in flit data
   localparam route_info_offset = la_route_info_offset + la_route_info_width;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // offset of payload length field (if present) in flit data
   localparam payload_length_offset = route_info_offset + route_info_width;
   
   // total width of header data
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) :
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ?
       (la_route_info_width + route_info_width + payload_length_width) :
       -1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 2 : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 1 : 
       -1;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ?
       (1 + vc_idx_width) :
       -1;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // incoming downstream flow control
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // outgoing upstream flow control
   output [0:flow_ctrl_width-1] flow_ctrl_out;
   wire [0:flow_ctrl_width-1] flow_ctrl_out;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // bit mask indicating which out VCs are available for allocation
   output [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs-1] 	      elig_ovc;
   
   // bit mask indicating which output VCs have credits available
   output [0:num_vcs-1] free_ovc;
   wire [0:num_vcs-1] 	      free_ovc;
   
   // bit mask indicating which output VCs have two or more credits available
   output [0:num_vcs-1] free_plus1_ovc;
   wire [0:num_vcs-1] 	      free_plus1_ovc;
   
   // activity indicator from input port controllers
   input [0:num_ports-1] act_ip;
   
   // request indicator from individual input ports
   input [0:num_ports-1] req_ip;
   
   // output VC selector for current request
   input [0:num_ports*num_vcs-1] req_ip_ovc;
   
   // head indicator for current request
   input [0:num_ports-1] req_head_ip;
   
   // tail indicator for current request
   input [0:num_ports-1] req_tail_ip;
   
   // grant indicators to individual input ports
   input [0:num_ports-1] gnt_ip;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // error indicator
   output error;
   wire 		      error;
   
   
   //---------------------------------------------------------------------------
   // forward declarations
   //---------------------------------------------------------------------------
   
   
   //---------------------------------------------------------------------------
   // input-side arbitration interface
   //---------------------------------------------------------------------------
   
   wire 		      iai_active;
   assign iai_active = |act_ip;
   
   generate
      
      begin:iai
	 
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // credit checking logic
   //---------------------------------------------------------------------------
   
   generate
      
      begin:cck
	 
	 wire [0:num_vcs*num_ports-1] req_ovc_ip;
	 c_interleaver
	   #(.width(num_ports*num_vcs),
	     .num_blocks(num_ports))
	 req_ovc_ip_intl
	   (.data_in(req_ip_ovc),
	    .data_out(req_ovc_ip));
	 
	 wire [0:num_ports-1] 	      free_ip;
	 c_select_mofn
	   #(.num_ports(num_vcs),
	     .width(num_ports))
	 free_ip_sel
	   (.select(free_ovc),
	    .data_in(req_ovc_ip),
	    .data_out(free_ip));
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // downstream flow control
   //---------------------------------------------------------------------------
   
   wire 		      idf_active;
   assign idf_active = ~&fbf_full_ivc;
   
   wire 		      idf_activity;
   wire 		      idf_flit_valid;
   wire [0:num_vcs-1] 	      idf_flit_sel;
   rtr_input_ds_flow_ctrl
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .link_pm_enable(link_pm_enable),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   idf
     (.clk(clk),
      .reset(reset),
      .active(idf_active),
      .ds_flow_ctrl(ds_flow_ctrl_in),
      .activity(idf_activity),
      .flit_valid(idf_flit_valid),
      .flit_sel_ivc(idf_flit_sel_ivc));
   
   wire [0:num_vcs-1] 	      idf_flit_valid_ivc;
   assign idf_flit_valid_ivc = {num_vcs{idf_flit_valid}} & idf_flit_sel_ivc;
   
   
   //---------------------------------------------------------------------------
   // upstream flow control
   //---------------------------------------------------------------------------
   
   wire 		      iuf_active;
   assign iuf_active = idf_activity | ~&fbf_empty_ivc;
   
   wire 		      iuf_activity;
   wire 		      iuf_flit_done;
   wire [0:num_vcs-1] 	      iuf_flit_sel_ivc;
   rtr_input_us_flow_ctrl
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .link_pm_enable(link_pm_enable),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   ifc
     (.clk(clk),
      .reset(reset),
      .active(iuf_active),
      .us_flow_ctrl(us_flow_ctrl_out),
      .flit_done(XXX),// FIXME
      .flit_sel_ivc(XXX));// FIXME
   
   
   //---------------------------------------------------------------------------
   // input register stage
   //---------------------------------------------------------------------------
   
   wire 		      irs_active;
   assign irs_active = ifc_ds_activity;
   
   wire [0:flit_ctrl_width-1] irs_flit_ctrl;
   wire [0:flit_data_width-1] irs_flit_data;
   wire [0:header_info_width-1] irs_header_info;
   
   begin:irs
      
      wire [0:flit_ctrl_width-1] flit_ctrl_s, flit_ctrl_q;
      assign flit_ctrl_s = ds_flit_ctrl_in;
      c_dff
	#(.width(flit_ctrl_width),
	  .reset_type(reset_type))
      flit_ctrlq
	(.clk(clk),
	 .reset(1'b0),
	 .active(irs_active),
	 .d(flit_ctrl_s),
	 .q(flit_ctrl_q));
      
      assign irs_flit_ctrl = flit_ctrl_q;
      
      wire [0:flit_data_width-1] flit_data_s, flit_data_q;
      assign flit_data_s = flit_data_in;
      c_dff
	#(.width(flit_data_width),
	  .reset_type(reset_type))
      flit_dataq
	(.clk(clk),
	 .reset(1'b0),
	 .active(irs_active),
	 .d(flit_data_s),
	 .q(flit_data_q));
      
      assign irs_flit_data = flit_data_q;
      assign irs_header_info = flit_data_q[0:header_info_width-1];
      
   end
   
   
   //---------------------------------------------------------------------------
   // buffers and control flow for each input VC
   //---------------------------------------------------------------------------
   
   genvar 			 ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   //-------------------------------------------------------------------
	   // forward declarations
	   //-------------------------------------------------------------------
	   
	   wire fbf_empty;
	   wire fcd_flit_valid;
	   wire fcd_flit_head;
	   wire fcd_flit_tail;
	   
	   
	   //-------------------------------------------------------------------
	   // connect inputs to top level
	   //-------------------------------------------------------------------
	   
	   wire idf_flit_valid;
	   assign idf_flit_valid = idf_flit_valid_ivc[ivc];
	   
	   wire ivc_active;
	   assign ivc_active = idf_flit_valid | ~fbf_empty;
	   
	   wire arb_flit_done;
	   assign arb_flit_done = arb_flit_done_ivc[ivc];
	   
	   wire arb_flit_done_prev;
	   assign arb_flit_done_prev = arb_flit_done_prev_ivc[ivc];
	   
	   
	   //-------------------------------------------------------------------
	   // flit buffer
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_buffer_width-1] fbf_write_data;
	   assign fbf_write_data = {irs_flit_data, irs_flit_ctrl};
	   
	   wire 			fbf_push;
	   assign fbf_push = idf_flit_valid & (~fbf_empty | ~arb_flit_done);
	   
	   wire 			fbf_pop;
	   assign fbf_pop = ~fbf_empty & arb_flit_done;
	   
	   wire 			fbf_almost_full;
	   wire 			fbf_full;
	   wire 			fbf_almost_empty;
	   wire [0:flit_buffer_width-1] fbf_read_data;
	   wire [0:flit_buffer_width-1] fbf_peek_data;
	   wire [0:1] 			fbf_errors;
	   c_regfile
	     #(.depth(flit_buffer_depth),
	       .width(flit_buffer_width),
	       .fifo_type(flit_buffer_fifo_type),
	       .reset_type(reset_type))
	   fbf
	     (.clk(clk),
	      .reset(reset),
	      .active(ivc_active),
	      .almost_full(fbf_almost_full),
	      .full(fbf_full),
	      .write_data(fbf_write_data),
	      .push(fbf_push),
	      .almost_empty(fbf_almost_empty),
	      .empty(fbf_empty),
	      .read_data(fbf_read_data),
	      .peek_data(fbf_peek_data),
	      .pop(fbf_pop),
	      .errors(fbf_errors));
	   
	   assign ivc_errors_ivc[ivc*4+0:ivc*4+1] = fbf_errors;
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		if(fbf_errors[0])
		  $display({"ERROR: Flit buffer underflow at input port %d, ", 
			    "VC %d."}, port_id, ivc);
		
		if(fbf_errors[1])
		  $display({"ERROR: Flit buffer overflow at input port %d, ",
			    "VC %d."}, port_id, ivc);
	     end
	   // synopsys translate_on
	   
	   wire [0:flit_ctrl_width-1] 	fbf_flit_ctrl;
	   assign fbf_flit_ctrl = fbf_read_data[0:flit_ctrl_width-1];
	   
	   wire [0:flit_data_width-1] 	fbf_flit_data;
	   assign fbf_flit_data
	     = fbf_read_data[flit_ctrl_width:flit_ctrl_width+flit_data_width-1];
	   
	   wire [0:flit_ctrl_width-1] 	fbf_peek_flit_ctrl;
	   assign fbf_peek_flit_ctrl = fbf_peek_data[0:flit_ctrl_width-1];
	   
	   wire [0:flit_data_width-1] 	fbf_peek_flit_data;
	   assign fbf_peek_flit_data
	     = fbf_peek_data[flit_ctrl_width:flit_ctrl_width+flit_data_width-1];
	   
	   wire [0:header_info_width-1] fbf_peek_header_info;
	   assign fbf_peek_header_info
	     = fbf_peek_flit_data[0:header_info_width-1];
	   
	   
	   //-------------------------------------------------------------------
	   // flit data bypass mux
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_data_width-1] 	fdbm_flit_data;
	   
	   begin:fdbm
	      assign fdbm_flit_data = fbf_empty ? irs_flit_data : fbf_flit_data;
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // track header info for current packet
	   //-------------------------------------------------------------------
	   
	   wire hit_packet_valid;
	   wire [0:header_info_width-1] hit_header_info;
	   
	   begin:hit
	      
	      wire hold;
	      assign hold
		= hit_packet_valid & (~arb_flit_done | ~fcd_flit_tail);
	      
	      wire capture_fbf;
	      assign capture_fbf = ~fbf_empty & ~fbf_almost_empty;
	      
	      wire muxed_packet_valid;
	      assign muxed_packet_valid
		= (capture_fbf | idf_flit_valid) &
		  ~(fbf_empty & arb_flit_done & fcd_flit_tail);
	      
	      wire packet_valid_s, packet_valid_q;
	      assign packet_valid_s
		= hold ? packet_valid_q : muxed_packet_valid;
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      packet_validq
		(.clk(clk),
		 .reset(reset),
		 .active(ivc_active),
		 .d(packet_valid_s),
		 .q(packet_valid_q));
	      
	      assign hit_packet_valid = packet_valid_q;
	      
	      wire [0:header_info_width-1] muxed_header_info;
	      assign muxed_header_info
		= capture_fbf ? fbf_peek_header_info : irs_header_info;
	      
	      wire [0:header_info_info_width-1] header_info_s, header_info_q;
	      assign header_info_s = hold ? header_info_q : muxed_header_info;
	      c_dff
		#(.width(la_route_info_width),
		  .reset_type(reset_type))
	      header_infoq
		(.clk(clk),
		 .reset(1'b0),
		 .active(ivc_active),
		 .d(header_info_s),
		 .q(header_info_q));
	      
	      assign hit_header_info = header_info_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // header info bypass mux
	   //-------------------------------------------------------------------
	   
	   wire [0:header_info_width-1] header_info;
	   
	   begin:hibm
	      assign header_info
		= hit_packet_valid ? hit_header_info : irs_header_info;
	   end
	   
	   wire [0:la_route_info_width-1] hibm_la_route_info;
	   assign hibm_la_route_info = hibm_header_info[la_route_info_offset:
							la_route_info_offset+
							la_route_info_width-1];
	   
	   wire [0:route_info_width-1] 	  hibm_route_info;
	   assign hibm_route_info = hibm_header_info[route_info_offset:
						     route_info_offset+
						     route_info_width-1];
	   
	   
	   //-------------------------------------------------------------------
	   // decode and update lookahead routing info
	   //-------------------------------------------------------------------
	   
	   wire [0:port_idx_width-1] 	  lar_route_port;
	   wire 			  lar_inc_rc;
	   wire [0:la_route_info_width-1] lar_la_route_info;
	   wire 			  lar_error_unmasked;
	   rtr_la_routing_logic
	     #(.num_message_classes(num_message_classes),
	       .num_resource_classes(num_resource_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity),
	       .routing_type(routing_type),
	       .dim_order(dim_order),
	       .port_id(port_id),
	       .vc_id(ivc))
	   lar
	     (.clk(clk),
	      .reset(reset),
	      .active(ivc_active),
	      .router_address(router_address),
	      .la_route_info_in(hibm_la_route_info),
	      .route_port(lar_route_port),
	      .inc_rc(lar_inc_rc),
	      .route_info_in(hibm_route_info),
	      .la_route_info_out(lar_la_route_info),
	      .error(lar_error_unmasked));
	   
	   wire 			  lar_error;
	   assign lar_error = fcd_flit_valid & lar_error_unmasked;
	   
	   assign ivc_errors_ivc[ivc*4+2] = lar_error;
	   
	   wire [0:num_ports-1] 	  lar_route_op;
	   c_decode
	     #(.num_ports(num_ports))
	   lar_route_op_dec
	     (.data_in(lar_route_port),
	      .data_out(lar_route_op));
	   
	   
	   //-------------------------------------------------------------------
	   // inhibit illegal port requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	  pf_route_op;
	   wire 			  pf_error_unmasked;
	   c_port_filter
	     #(.num_message_classes(num_message_classes),
	       .num_resource_classes(num_resource_classes),
	       .num_ports(num_ports),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .num_nodes_per_router(num_nodes_per_router),
	       .restrict_turns(restrict_turns),
	       .connectivity(connectivity),
	       .routing_type(routing_type),
	       .port_id(port_id),
	       .vc_id(ivc))
	   pf
	     (.route_in_op(lar_route_unmasked_op),
	      .inc_rc(lar_inc_rc),
	      .route_out_op(pf_route_op),
	      .error(pf_error_unmasked));
	   
	   wire 			  pf_error;
	   assign pf_error = fcd_flit_valid & pf_error_unmasked;
	   
	   assign ivc_errors_ivc[ivc*4+3] = pf_error;
	   
	   
	   //-------------------------------------------------------------------
	   // mux for selecting next eligible VC for current VC's packet class
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs_per_class-1]   next_elig_ocvc;
	   rtr_vc_flag_mux
	     #(.num_message_classes(num_message_classes),
	       .num_resource_classes(num_resource_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity),
	       .vc_id(ivc))
	   next_elig_ocvc_fm
	     (.route_port(lar_route_port),
	      .inc_rc(lar_inc_rc),
	      .flag_op_ovc(next_elig_op_ovc),
	      .flag_ocvc(next_elig_ocvc));
	   
	   
	   //-------------------------------------------------------------------
	   // track which output VC this input VC is assigned to
	   //-------------------------------------------------------------------
	   
	   wire 			  ovt_assigned;
	   wire [0:num_vcs_per_class-1]   ovt_assigned_ocvc;
	   wire [0:num_vcs-1] 		  ovt_route_ovc;
	   
	   begin:ovt
	      
	      if(0 /* separate VC and switch allocation */)
		begin
		   
		   wire assigned_s, assigned_q;
		   assign assigned_s
		     = (assigned_q | XXX) & ~(tail & done);// FIXME
		   c_dff
		     #(.width(1),
		       .reset_type(reset_type))
		   assignedq
		     (.clk(clk),
		      .reset(reset),
		      .active(ivc_active),
		      .d(assigned_s),
		      .q(assigned_q));
		   
		   assign ovt_assigned = assigned_q;
		   
		end
	      else
		assign ovt_assigned = ~fcd_flit_head;
	      
	      wire [0:num_vcs_per_class-1] route_ocvc_s, route_ocvc_q;
	      assign assigned_ocvc_s
		= ovt_assigned ? assigned_ocvc_q : next_elig_ocvc;
	      c_dff
		#(.width(num_vcs_per_class)
		  .reset_type(reset_type))
	      assigned_ocvcq
		(.clk(clk),
		 .reset(1'b0),
		 .active(ivc_active),
		 .d(assigned_ocvc_s),
		 .q(assigned_ocvc_q));
	      
	      assign ovt_assigned_ocvc = assigned_ocvc_q;
	      
	      wire [0:num_vcs_per_class-1] vcmask_ocvc;
	      assign vcmask_ocvc
		= {num_vcs_per_class{fcd_flit_head}} | ovt_assigned_ocvc;
	      
	      rtr_vc_align
		#(.num_message_classes(num_message_classes),
		  .num_resource_classes(num_resource_classes),
		  .num_vcs_per_class(num_vcs_per_class),
		  .vc_id(ivc))
	      ovt_route_ovc_vagn
		(.flag_ocvc(vcmask_ocvc),
		 .inc_rc(lar_inc_rc),
		 .flag_ovc(ovt_route_ovc));
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // track control data for current flit
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_ctrl_width-1] 	  fct_flit_ctrl;
	   
	   begin:fct
	      
	      wire hold;
	      assign hold = ~fbf_empty & ~arb_flit_done;
	      
	      wire capture_fbf;
	      assign capture_fbf = ~fbf_almost_empty & arb_flit_done;
	      
	      wire muxed_flit_ctrl;
	      assign muxed_flit_ctrl
		= capture_fbf ? fbf_peek_flit_ctrl : irs_flit_ctrl;
	      
	      wire [0:flit_ctrl_width-1] flit_ctrl_s, flit_ctrl_q;
	      assign flit_ctrl_s = hold ? flit_ctrl_q : muxed_flit_ctrl;
	      c_dff
		#(.width(flit_ctrl_width),
		  .reset_type(reset_type))
	      flit_ctrlq
		(.clk(clk),
		 .reset(1'b0),
		 .active(ivc_active),
		 .d(flit_ctrl_s),
		 .q(flit_ctrl_q));
	      
	      assign fct_flit_ctrl = flit_ctrl_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // flit control data bypass mux
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_ctrl_width-1] 	 fcbm_flit_ctrl;
	   
	   begin:fcbm
	      assign fcbm_flit_ctrl = fbf_empty ? irs_flit_ctrl : fct_flit_ctrl;
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // decode flit control signals
	   //-------------------------------------------------------------------
	   
	   assign fcd_flit_valid = idf_flit_valid | ~fbf_empty;
	   
	   rtr_flit_ctrl_dec
	     #(.packet_format(packet_format),
	       .max_payload_length(max_payload_length),
	       .min_payload_length(min_payload_length),
	       .reset_type(reset_type))
	   fcd
	     (.clk(clk),
	      .reset(reset),
	      .active(ivc_active),
	      .flit_ctrl(fcbm_flit_ctrl),
	      .flit_data(fdbm_flit_data),
	      .flit_done(arb_flit_done),
	      .flit_head(fcd_flit_head),
	      .flit_tail(fcd_flit_tail));
	   
	   
	   //-------------------------------------------------------------------
	   // update header info fields for head flits
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_data_width-1] 	 lau_flit_data;
	   
	   begin:lau
	      
	      wire [0:la_route_info_width-1] orig_bits;
	      assign orig_bits = fdbm_flit_data[la_route_info_offset:
						la_route_info_offset+
						la_route_info_width-1];
	      
	      wire [0:la_route_info_width-1] muxed_bits;
	      assign muxed_bits = fcd_flit_head ? lar_la_route_info : orig_bits;
	      
	      wire [0:flit_data_width-1]     flit_data;
	      c_align
		#(.in_width(la_route_info_width),
		  .out_width(flit_data_width),
		  .offset(la_route_info_offset))
	      flit_data_alg
		(.data_in(muxed_data),
		 .dest_in(fdbm_flit_data),
		 .data_out(flit_data));
	      
	      assign lau_flit_data = flit_data;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // track assigned output VC's credit level
	   //-------------------------------------------------------------------
	   
	   wire 			     oct_free_early;
	   
	   begin:oct
	      
	      wire [0:num_vcs-1] free_ovc;
	      assign free_ovc = free_op_ovc[route_port*num_vcs +: num_vcs];
	      
	      wire [0:num_vcs_per_class-1] free_ocvc;
	      rtr_vc_flag_mux
		#(.num_message_classes(num_message_classes),
		  .num_resource_classes(num_resource_classes),
		  .num_vcs_per_class(num_vcs_per_class),
		  .num_routers_per_dim(num_routers_per_dim),
		  .num_dimensions(num_dimensions),
		  .num_nodes_per_router(num_nodes_per_router),
		  .connectivity(connectivity),
		  .vc_id(ivc))
	      free_ocvc_fm
		(.route_port(lar_route_port),
		 .inc_rc(lar_inc_rc),
		 .flag_op_ovc(free_op_ovc),
		 .flag_ocvc(free_ocvc));
	      
	      wire [0:num_vcs-1] 	   free_plus1_ovc;
	      assign free_plus1_ovc
		= free_plus1_op_ovc[route_port*num_vcs +: num_vcs];
	      
	      wire [0:num_vcs_per_class-1] free_plus1_ocvc;
	      rtr_vc_flag_mux
		#(.num_message_classes(num_message_classes),
		  .num_resource_classes(num_resource_classes),
		  .num_vcs_per_class(num_vcs_per_class),
		  .num_routers_per_dim(num_routers_per_dim),
		  .num_dimensions(num_dimensions),
		  .num_nodes_per_router(num_nodes_per_router),
		  .connectivity(connectivity),
		  .vc_id(ivc))
	      free_plus1_ocvc_fm
		(.route_port(lar_route_port),
		 .inc_rc(lar_inc_rc),
		 .flag_op_ovc(free_plus1_op_ovc),
		 .flag_ocvc(free_plus1_ocvc));
	      
	      wire 			   free;
	      wire 			   free_plus1;
	      
	      if(num_vcs_per_class > 1)
		begin
		   
		   wire [0:num_vcs_per_class-1] sel_ocvc;
		   assign sel_ocvc
		     = fcd_flit_head ? next_free_ocvc : ovt_assigned_ocvc;
		   
		   assign free = |(sel_ocvc & free_ocvc);
		   assign free_plus1 = |(sel_ocvc & free_plus1_ocvc);
		   
		end
	      else
		begin
		   assign free = free_ocvc;
		   assign free_plus1 = free_plus1_ocvc;
		end
	      
	      wire free_s, free_q;
	      assign free_s = free;
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      free_earlyq
		(.clk(clk),
		 .reset(1'b0),
		 .active(ivc_active),
		 .d(free_s),
		 .q(free_q));
	      
	      wire free_plus1_s, free_plus1_q;
	      assign free_plus1_s = free_plus1;
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      free_plus1q
		(.clk(clk),
		 .reset(1'b0),
		 .active(ivc_active),
		 .d(free_plus1_s),
		 .q(free_plus1_q));
	      
	      // If we did not send a flit in the previous cycle, the credit 
	      // status for the current cycle will be the same as that for the 
	      // previous cycle; otherwise, we only know for sure that credits 
	      // are still available in the current cycle if there were two or 
	      // more credits available in the previous cycle. Note, however, 
	      // that this is pessimistic, as it does not account for any 
	      // additional credits that may have been received in the previous 
	      // cycle. Also, the result is only valid once VC allocation has
	      // been performed; in particular, it is not valid for head flits.
	      assign oct_free_early
		= arb_flit_done_prev ? free_plus1_q : free_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs to top level
	   //-------------------------------------------------------------------
	   
	   assign fcd_flit_valid_ivc[ivc] = fcd_flit_valid;
	   assign fcd_flit_head_ivc[ivc] = fcd_flit_head;
	   assign fcd_flit_tail_ivc[ivc] = fcd_flit_tail;
	   
	   assign pf_route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = pf_route_op;
	   assign ovt_route_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]
		    = ovt_route_ovc;
	   
	   assign fbf_empty_ivc[ivc] = fbf_empty;
	   assign fbf_full_ivc[ivc] = fbf_full;
	   
	   assign oct_free_ivc[ivc] = oct_free_early;
	   
	   assign lau_flit_data_ivc[ivc*flit_data_width:
				    (ivc+1)*flit_data_width-1]
		    = lau_flit_data;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // arbitrate among high-priority requests (body/tail flits w/ credit)
   //---------------------------------------------------------------------------
   
   wire 	   hpa_active;
   assign hpa_active = idf_activity | ~&fbf_empty_ivc;
   
   wire [0:num_vcs-1] hpa_gnt_ivc;
   wire 	      hpa_gnt;
   
   begin:hpa
      
      wire [0:num_vcs-1] req_ivc;
      assign req_ivc = fcd_flit_valid_ivc & ~fcd_flit_head_ivc & oct_free_ivc;
      
      wire 		 gnt;
      assign gnt = |req_ivc;
      
      wire 		 update;
      assign update = gnt;
      
      wire [0:num_vcs-1] gnt_ivc;
      c_arbiter
	#(.num_ports(num_vcs),
	  .arbiter_type(arbiter_type))
      arb
	(.clk(clk),
	 .reset(reset),
	 .active(hpa_active),
	 .req(req_ivc),
	 .gnt(gnt_ivc),
	 .update(update));
      
      assign hpa_gnt_ivc = gnt_ivc;
      assign hpa_gnt = gnt;
      
   end
   
   
   //---------------------------------------------------------------------------
   // arbitrate among low-priority requests (head flits, body/tail flits w/o 
   // credit)
   //---------------------------------------------------------------------------
   
   wire 		 lpa_active;
   assign lpa_active = idf_activity | ~&fbf_empty_ivc;
   
   wire [0:num_vcs-1] 	 lpa_gnt_ivc;
   wire 		 lpa_gnt;
   
   begin:lpa
      
      wire [0:num_vcs-1] req_ivc;
      assign req_ivc = fcd_flit_valid_ivc & (fcd_flit_head_ivc | ~oct_free_ivc);
      
      wire 		 gnt;
      assign gnt = |req_ivc;
      
      wire 		 update;
      assign update = gnt & ~hpa_gnt;
      
      wire [0:num_vcs-1] gnt_ivc;
      c_arbiter
	#(.num_ports(num_vcs),
	  .arbiter_type(arbiter_type))
      arb
	(.clk(clk),
	 .reset(reset),
	 .active(lpa_active),
	 .req(req_ivc),
	 .gnt(gnt_ivc),
	 .update(update));
      
      assign lpa_gnt_ivc = gnt_ivc;
      assign lpa_gnt = gnt;
      
   end
   
   
   //---------------------------------------------------------------------------
   // VC select mux
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	 vsm_sel_ivc;
   assign vsm_sel_ivc = hpa_gnt ? hpa_gnt_ivc : lpa_gnt_ivc;
   
   wire [0:num_ports-1]  vsm_route_op;
   wire [0:num_vcs-1] 	 vsm_route_ovc;
   wire [0:flit_data_width-1] vsm_flit_data;
   
   begin:vsm
      
      wire [0:num_ports-1] route_op;
      c_select_1ofn
	#(.num_ports(num_vcs),
	  .width(num_ports))
      route_op_sel
	(.select(vcm_sel_ivc),
	 .data_in(pf_route_ivc_op),
	 .data_out(route_op));
      
      assign vsm_route_op = route_op;
      
      wire [0:num_vcs-1]   route_ovc;
      c_select_1ofn
	#(.num_ports(num_vcs),
	  .width(num_vcs))
      route_ovc_sel
	(.select(vcm_sel_ivc),
	 .data_in(ovt_route_ivc_ovc),
	 .data_out(route_ovc));
      
      assign vsm_route_ovc = route_ovc;
      
      wire [0:flit_data_width-1] flit_data;
      c_select_1ofn
	#(.num_ports(num_vcs),
	  .width(flit_data_width))
      flit_data_sel
	(.select(vsm_sel_ivc),
	 .data_in(lau_flit_data_ivc),
	 .data_out(flit_data));
      
      assign vsm_flit_data = flit_data;
      
   end
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_vcs*4-1]  errors_s, errors_q;
	   assign errors_s = ivcc_errors_ivc;
	   c_err_rpt
	     #(.num_errors(num_vcs*4),
	       .capture_mode(error_capture_mode),
	       .reset_type(reset_type))
	   chk
	     (.clk(clk),
	      .reset(reset),
	      .errors_in(errors_s),
	      .errors_out(errors_q));
	   
	   assign error = |errors_q;
	   
	end
      else
	assign error = 1'b0;
      
   endgenerate
   
endmodule
