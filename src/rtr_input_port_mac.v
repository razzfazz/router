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


// input port module
module rtr_input_port_mac
  (clk, reset, router_address, flow_ctrl_in, flow_ctrl_out, flit_ctrl_in, 
   flit_data_in, elig_op_ovc, free_op_ovc, act_op, req_op, req_ovc, req_head, 
   req_tail, gnt_op, flit_data_out, error);
   
   
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
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
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
   
   // select implementation variant for flit buffer
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
`include "c_functions.v"
`include "rtr_functions.v"
   
   
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
   
   // offset of lookahead routing information in header info
   localparam la_route_info_offset = 0;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // offset of routing information in header info
   localparam route_info_offset = la_route_info_offset + la_route_info_width;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // offset of payload length field (if present) in header info
   localparam payload_length_offset = route_info_offset + route_info_width;

   // total width of header data
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) :
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ?
       (la_route_info_width + route_info_width + payload_length_width) :
       -1;
   
   // offset of header info in flit data
   localparam header_info_offset = 0;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 2 : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 1 : 
       -1;
   
   // width of downstream flow control signals
   localparam ds_flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ?
       (1 + vc_idx_width) :
       -1;
   
   // width of upstream flow control signals
   localparam us_flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ?
       (1 + vc_idx_width) :
       -1;
   
   // width of flit buffer addresses
   localparam fbf_addr_width = clogb(num_flit_buffers);
   
   // width of flit buffer entries
   localparam fbf_data_width = 1 + 1 + flit_data_width;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming downstream flow control
   input [0:ds_flow_ctrl_width-1] flow_ctrl_in;
   
   // outgoing upstream flow control
   output [0:us_flow_ctrl_width-1] flow_ctrl_out;
   wire [0:us_flow_ctrl_width-1] flow_ctrl_out;
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // bit mask indicating which out VCs are available for allocation
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // credit availability indicator for each output VCs
   input [0:num_ports*num_vcs*2-1] free_op_ovc;
   
   // activity indicator to output port controllers
   output [0:num_ports-1] act_op;
   wire [0:num_ports-1] 	 act_op;
   
   // request indicator to individual outpout ports
   output [0:num_ports-1] req_op;
   wire [0:num_ports-1]       req_op;
   
   // output VC selector for current request
   output [0:num_vcs-1] req_ovc;
   wire [0:num_vcs-1] 	      req_ovc;
   
   // head indicator for current request
   output req_head;
   wire 		      req_head;
   
   // tail indicator for current request
   output req_tail;
   wire 		      req_tail;
   
   // grant indicators from all output ports
   input [0:num_ports-1] gnt_op;
   
   // 
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // error indicator
   output error;
   wire 		      error;
   
   
   //---------------------------------------------------------------------------
   // forward declarations
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	      fbc_full_ivc;
   
   wire [0:num_vcs-1] 	      oai_gnt_ivc;
   wire 		      oai_gnt;
   
   
   //---------------------------------------------------------------------------
   // downstream flow control
   //---------------------------------------------------------------------------
   
   wire 		      dfc_active;
   assign dfc_active = ~&fbc_full_ivc;
   
   wire 		      dfc_flit_valid;
   wire [0:num_vcs-1] 	      dfc_flit_sel_ivc;
   rtr_flow_ctrl_rx
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   dfc
     (.clk(clk),
      .reset(reset),
      .active(dfc_active),
      .flow_ctrl(flow_ctrl_in),
      .valid(dfc_flit_valid),
      .sel_ivc(dfc_flit_sel_ivc));
   
   
   //---------------------------------------------------------------------------
   // input register stage
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	      irs_flit_valid_ivc;
   wire 		      irs_flit_valid;
   
   wire 		      irs_active;
   assign irs_active = dfc_active | |irs_flit_valid_ivc;
   
   wire [0:flit_ctrl_width-1] irs_flit_ctrl;
   wire [0:flit_data_width-1] irs_flit_data;
   wire [0:header_info_width-1] irs_header_info;
   wire [0:la_route_info_width-1] irs_la_route_info;
   wire [0:route_info_width-1] 	  irs_route_info;
   
   generate
      
      begin:irs

	 wire [0:num_vcs-1] flit_valid_ivc_s, flit_valid_ivc_q;
	 assign flit_valid_ivc_s = {num_vcs{dfc_flit_valid}} & dfc_flit_sel_ivc;
	 c_dff
	   #(.width(num_vcs),
	     .reset_type(reset_type))
	 flit_valid_ivcq
	   (.clk(clk),
	    .reset(reset),
	    .active(irs_active),
	    .d(flit_valid_ivc_s),
	    .q(flit_valid_ivc_q));
	 
	 assign irs_flit_valid_ivc = flit_valid_ivc_q;
	 assign irs_flit_valid = |flit_valid_ivc_q;
	 	 
	 wire [0:flit_ctrl_width-1] flit_ctrl_s, flit_ctrl_q;
	 assign flit_ctrl_s = flit_ctrl_in;
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
	 assign irs_header_info
	   = irs_flit_data[header_info_offset:
			   header_info_offset+header_info_width-1];
	 assign irs_la_route_info
	   = irs_header_info[la_route_info_offset:
			     la_route_info_offset+la_route_info_width-1];
	 assign irs_route_info
	   = irs_header_info[route_info_offset:
			     route_info_offset+route_info_width-1];
	 
      end
      
   endgenerate
   
   
   //-------------------------------------------------------------------
   // head bit decoder for input register stage
   //-------------------------------------------------------------------
   
   wire 			    ihd_active;
   assign ihd_active = irs_flit_valid;
   
   wire 			    ihd_flit_head;
   rtr_flit_head_dec
     #(.packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .reset_type(reset_type))
   ihd
     (.clk(clk),
      .reset(reset),
      .active(ihd_active),
      .flit_ctrl(irs_flit_ctrl),
      .header_info(irs_header_info),
      .flit_done(irs_flit_valid),
      .flit_head(ihd_flit_head));
   
   
   //---------------------------------------------------------------------------
   // decode lookahead routing info for input register
   //---------------------------------------------------------------------------
   
   wire [0:port_idx_width-1] 	    ild_route_port;
   wire 			    ild_inc_rc;
   rtr_la_route_dec
     #(.num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity))
   ild
     (.la_route_info(irs_la_route_info),
      .route_port(ild_route_port),
      .inc_rc(ild_inc_rc));
   
   
   //---------------------------------------------------------------------------
   // route port decoder for input register
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] 	  ipd_route_op;
   c_decode
     #(.num_ports(num_ports))
   ipd
     (.data_in(ild_route_port),
      .data_out(ipd_route_op));
   
   
   //---------------------------------------------------------------------------
   // buffers and control flow for each input VC
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 		    fct_flit_valid_ivc;
   
   wire [0:num_vcs-1] 		    fcm_flit_valid_ivc;
   wire [0:num_vcs-1] 		    fcm_flit_head_ivc;
   wire [0:num_vcs-1] 		    fcm_flit_tail_ivc;
   
   wire [0:num_vcs-1] 		    rit_valid_ivc;
   wire [0:num_vcs*num_ports-1]     vpd_route_ivc_op;
   
   wire [0:num_vcs*num_ports-1]     pf_route_ivc_op;
   wire [0:num_vcs*num_vcs-1] 	    ovt_route_ivc_ovc;
   
   wire [0:num_vcs*la_route_info_width-1] lar_la_route_info_ivc;
   
   wire [0:num_vcs-1] 			  pst_prio_ivc;
   
   wire [0:num_vcs*flit_data_width-1] 	  fbf_flit_data_ivc;
   
   wire [0:num_vcs*4-1] 		  ivcs_errors_ivc;
   
   genvar 				  ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   //-------------------------------------------------------------------
	   // forward declarations
	   //-------------------------------------------------------------------
	   
	   wire fcm_flit_valid;
	   
	   
	   //-------------------------------------------------------------------
	   // connect inputs to top level
	   //-------------------------------------------------------------------
	   
	   wire irs_flit_valid;
	   assign irs_flit_valid = irs_flit_valid_ivc[ivc];
	   
	   wire oai_gnt;
	   assign oai_gnt = oai_gnt_ivc[ivc];
	   
	   
	   //-------------------------------------------------------------------
	   // decode flit control signals to generate head and tail markers
	   //-------------------------------------------------------------------
	   
	   wire fcd_active;
	   assign fcd_active = irs_flit_valid;
	   
	   wire fcd_flit_head;
	   wire fcd_flit_tail;
	   rtr_flit_ctrl_dec
	     #(.packet_format(packet_format),
	       .max_payload_length(max_payload_length),
	       .min_payload_length(min_payload_length),
	       .reset_type(reset_type))
	   fcd
	     (.clk(clk),
	      .reset(reset),
	      .active(fcd_active),
	      .flit_ctrl(irs_flit_ctrl),
	      .header_info(irs_header_info),
	      .flit_done(irs_flit_valid),
	      .flit_head(fcd_flit_head),
	      .flit_tail(fcd_flit_tail));
	   
	   
	   //-------------------------------------------------------------------
	   // flit buffer
	   //-------------------------------------------------------------------
	   
	   wire fbc_active;
	   assign fbc_active = fcm_flit_valid;
	   
	   wire 			fbc_push;
	   assign fbc_push = irs_flit_valid;
	   
	   wire 			fbc_pop;
	   assign fbc_pop = oai_gnt;
	   
	   wire [0:fbf_addr_width-1] fbc_write_addr;
	   wire [0:fbf_addr_width-1] fbc_read_addr;
	   wire [0:fbf_addr_width-1] fbc_peek_addr;
	   wire 		     fbc_almost_empty;
	   wire 		     fbc_empty;
	   wire 		     fbc_almost_full;
	   wire 		     fbc_full;
	   wire [0:1] 		     fbc_errors;
	   c_fifo_ctrl
	     #(.addr_width(fbf_addr_width),
	       .offset(0),
	       .depth(num_flit_buffers),
	       .reset_type(reset_type))
	   fbc
	     (.clk(clk),
	      .reset(reset),
	      .active(fbc_active),
	      .push(fbc_push),
	      .pop(fbc_pop),
	      .write_addr(fbc_write_addr),
	      .read_addr(fbc_read_addr),
	      .peek_addr(fbc_peek_addr),
	      .almost_empty(fbc_almost_empty),
	      .empty(fbc_empty),
	      .almost_full(fbc_almost_full),
	      .full(fbc_full),
	      .errors(fbc_errors));
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		if(fbc_errors[0])
		  $display({"ERROR: Flit buffer underflow at input port %d, ", 
			    "VC %d."}, port_id, ivc);
		
		if(fbc_errors[1])
		  $display({"ERROR: Flit buffer overflow at input port %d, ",
			    "VC %d."}, port_id, ivc);
	     end
	   // synopsys translate_on
	   
	   wire [0:fbf_addr_width-1] fbf_read_addr;
	   
	   // NOTE: Instead of using a separate pipeline register to hold flits 
	   // that have been granted switch access, we can just keep them in 
	   // the flit buffer for an additional cycle; i.e., the flit data is 
	   // read from the buffer in the cycle after the one in which switch 
	   // allocation takes place. This can be achieved by just delaying the 
	   // read pointer by one cycle. It should be noted that this approach 
	   // increases buffer utilization, but does not affect the buffer size 
	   // requirements. This is because any given buffer entry is reused at 
	   // the earliest after one complete credit round-trip delay has 
	   // elapsed, so keeping the flit in the buffer for one additional 
	   // cycle is safe as it will not be overwritten during this time.
	   wire [0:fbf_addr_width-1] fbc_read_addr_s, fbc_read_addr_q;
	   assign fbc_read_addr_s = fbc_read_addr;
	   c_dff
	     #(.width(fbf_addr_width),
	       .reset_type(reset_type))
	   fbc_read_addrq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(fbc_active),
	      .d(fbc_read_addr_s),
	      .q(fbc_read_addr_q));
	   
	   assign fbf_read_addr = fbc_read_addr_q;
	   
	   wire 		     fbf_active;
	   assign fbf_active = irs_flit_valid;
	   
	   wire [0:fbf_data_width-1] fbf_write_data;
	   assign fbf_write_data
	     = {fcd_flit_head, fcd_flit_tail, irs_flit_data};
	   
	   wire [0:fbf_data_width-1] fbf_read_data;
	   wire [0:fbf_data_width-1] fbf_peek_data;
	   c_regfile
	     #(.depth(num_flit_buffers),
	       .width(fbf_data_width),
	       .num_read_ports(2),
	       .regfile_type(regfile_type))
	   fbf
	     (.clk(clk),
	      .active(fbf_active),
	      .write_enable(fbc_push),
	      .write_address(fbc_write_addr),
	      .write_data(fbf_write_data),
	      .read_address({fbc_peek_addr, fbf_read_addr}),
	      .read_data({fbf_peek_data, fbf_read_data}));
	   
	   wire 		     fbf_peek_flit_head;
	   assign fbf_peek_flit_head = fbf_peek_data[0];
	   
	   wire 		     fbf_peek_flit_tail;
	   assign fbf_peek_flit_tail = fbf_peek_data[1];
	   
	   wire [0:flit_data_width-1] fbf_peek_flit_data;
	   assign fbf_peek_flit_data = fbf_peek_data[2:2+flit_data_width-1];
	   
	   wire [0:header_info_width-1] fbf_peek_header_info;
	   assign fbf_peek_header_info
	     = fbf_peek_flit_data[header_info_offset:
				  header_info_offset+header_info_width-1];
	   
	   wire [0:la_route_info_width-1] fbf_peek_la_route_info;
	   assign fbf_peek_la_route_info
	     = fbf_peek_header_info[la_route_info_offset:
				    la_route_info_offset+la_route_info_width-1];
	   
	   wire [0:route_info_width-1] 	  fbf_peek_route_info;
	   assign fbf_peek_route_info
	     = fbf_peek_header_info[route_info_offset:
				    route_info_offset+route_info_width-1];
	   
	   wire [0:flit_data_width-1] 	  fbf_read_flit_data;
	   assign fbf_read_flit_data = fbf_read_data[2:2+flit_data_width-1];
	   
	   
	   //-------------------------------------------------------------------
	   // track control info for front-most flit in buffer
	   //-------------------------------------------------------------------
	   
	   wire 			  fct_active;
	   assign fct_active = fcm_flit_valid;
	   
	   wire 			  fct_flit_valid;
	   wire 			  fct_flit_head;
	   wire 			  fct_flit_tail;
	   
	   begin:fct
	      
	      assign fct_flit_valid = ~fbc_empty;
	      
	      wire hold;
	      assign hold = ~fbc_empty & ~oai_gnt;
	      
	      wire capture_fbf;
	      assign capture_fbf = ~fbc_almost_empty & oai_gnt;
	      
	      wire muxed_flit_head;
	      assign muxed_flit_head
		= capture_fbf ? fbf_peek_flit_head : fcd_flit_head;
	      
	      wire flit_head_s, flit_head_q;
	      assign flit_head_s = hold ? flit_head_q : muxed_flit_head;
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      flit_headq
		(.clk(clk),
		 .reset(1'b0),
		 .active(fct_active),
		 .d(flit_head_s),
		 .q(flit_head_q));
	      
	      assign fct_flit_head = flit_head_q;
	      
	      wire muxed_flit_tail;
	      assign muxed_flit_tail
		= capture_fbf ? fbf_peek_flit_tail : fcd_flit_tail;
	      
	      wire flit_tail_s, flit_tail_q;
	      assign flit_tail_s = hold ? flit_tail_q : muxed_flit_tail;
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      flit_tailq
		(.clk(clk),
		 .reset(1'b0),
		 .active(fct_active),
		 .d(flit_tail_s),
		 .q(flit_tail_q));
	      
	      assign fct_flit_tail = flit_tail_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // control info bypass mux
	   //-------------------------------------------------------------------

	   wire    fcm_flit_head;
	   wire    fcm_flit_tail;
	   
	   begin:fcm
	      
	      wire flit_valid;
	      assign flit_valid = irs_flit_valid | fct_flit_valid;
	      
	      assign fcm_flit_valid = flit_valid;
	      
	      wire flit_head;
	      assign flit_head = fct_flit_valid ? fct_flit_head : fcd_flit_head;
	      
	      assign fcm_flit_head = flit_head;
	      
	      wire flit_tail;
	      assign flit_tail = fct_flit_valid ? fct_flit_tail : fcd_flit_tail;
	      
	      assign fcm_flit_tail = flit_tail;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // track route info for current packet
	   //-------------------------------------------------------------------
	   
	   wire 			rit_active;
	   assign rit_active = fcm_flit_valid;
	   
	   wire [0:la_route_info_width-1] rit_la_route_info;
	   wire [0:route_info_width-1] 	  rit_route_info;
	   wire 			  rit_valid;
	   
	   begin:rit
	      
	      wire valid_q;
	      
	      wire hold;
	      assign hold = valid_q & (~oai_gnt | ~fcm_flit_tail);
	      
	      wire capture_fbf;
	      assign capture_fbf = ~fbc_empty & ~fbc_almost_empty;
	      
	      wire muxed_valid;
	      assign muxed_valid = (capture_fbf | irs_flit_valid) &
				   ~(fbc_empty & oai_gnt & fcm_flit_tail);
	      
	      wire valid_s;
	      assign valid_s = hold ? valid_q : muxed_valid;
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      validq
		(.clk(clk),
		 .reset(reset),
		 .active(rit_active),
		 .d(valid_s),
		 .q(valid_q));
	      
	      assign rit_valid = valid_q;
	      
	      wire [0:la_route_info_width-1] muxed_la_route_info;
	      assign muxed_la_route_info
		= capture_fbf ? fbf_peek_la_route_info : irs_la_route_info;
	      
	      wire [0:la_route_info_width-1] la_route_info_s, la_route_info_q;
	      assign la_route_info_s
		= hold ? la_route_info_q : muxed_la_route_info;
	      c_dff
		#(.width(la_route_info_width),
		  .reset_type(reset_type))
	      la_route_infoq
		(.clk(clk),
		 .reset(1'b0),
		 .active(rit_active),
		 .d(la_route_info_s),
		 .q(la_route_info_q));
	      
	      assign rit_la_route_info = la_route_info_q;
	      
	      wire [0:route_info_width-1]    muxed_route_info;
	      assign muxed_route_info
		= capture_fbf ? fbf_peek_route_info : irs_route_info;
	      
	      wire [0:route_info_width-1]    route_info_s, route_info_q;
	      assign route_info_s
		= hold ? route_info_q : muxed_route_info;
	      c_dff
		#(.width(route_info_width),
		  .reset_type(reset_type))
	      route_infoq
		(.clk(clk),
		 .reset(1'b0),
		 .active(rit_active),
		 .d(route_info_s),
		 .q(route_info_q));
	      
	      assign rit_route_info = route_info_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // decode lookahead routing info for this VC
	   //-------------------------------------------------------------------
	   
	   wire [0:port_idx_width-1] 	    vld_route_port;
	   wire 			    vld_inc_rc;
	   rtr_la_route_dec
	     #(.num_resource_classes(num_resource_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity),
	       .vc_id(ivc))
	   vld
	     (.la_route_info(rit_la_route_info),
	      .route_port(vld_route_port),
	      .inc_rc(vld_inc_rc));
	   
	   
	   //-------------------------------------------------------------------
	   // route port decoder for this VC
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	  vpd_route_op;
	   c_decode
	     #(.num_ports(num_ports))
	   vpd
	     (.data_in(vld_route_port),
	      .data_out(vpd_route_op));
	   
	   
	   //-------------------------------------------------------------------
	   // route info mux
	   //-------------------------------------------------------------------
	   
	   wire [0:route_info_width-1] rim_route_info;
	   wire [0:port_idx_width-1]   rim_route_port;
	   wire [0:num_ports-1]        rim_route_op;
	   wire 		       rim_inc_rc;
	   wire 		       rim_valid;
	   wire 		       rim_error;
	   
	   begin:rim
	      
	      wire [0:route_info_width-1] route_info;
	      assign route_info = rit_valid ? rit_route_info : irs_route_info;
	      
	      assign rim_route_info = route_info;
	      
	      wire [0:port_idx_width-1]   route_port;
	      assign route_port = rit_valid ? vld_route_port : ild_route_port;
	      
	      assign rim_route_port = route_port;
	      
	      wire [0:num_ports-1] 	  route_op;
	      assign route_op = rit_valid ? vpd_route_op : ipd_route_op;
	      
	      assign rim_route_op = route_op;
	      
	      wire 			  inc_rc;
	      assign inc_rc = rit_valid ? vld_inc_rc : ild_inc_rc;
	      
	      assign rim_inc_rc = inc_rc;
	      
	      // NOTE: At the input register, we're really only interested in 
	      // head flits; however, if rit_valid is false (i.e., routing info 
	      // hasn't been set yet for the current VC), the next flit to 
	      // arrive for this VC must be a head flit. Thus, to simplify the 
	      // logic, we just assume the correct case, and flag an error 
	      // otherwise.
	      wire 			  valid;
	      assign valid = rit_valid | (irs_flit_valid /*& fcd_flit_head*/);
	      
	      assign rim_valid = valid;
	      
	      // check for stray body/tail flit at input
	      wire 			  error;
	      assign error = ~rit_valid & irs_flit_valid & ~fcd_flit_head;
	      
	      assign rim_error = error;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // filter out illegal port requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	  pf_route_op;
	   wire 			  pf_error_unmasked;
	   rtr_port_filter
	     #(.num_message_classes(num_message_classes),
	       .num_resource_classes(num_resource_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_ports(num_ports),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .num_nodes_per_router(num_nodes_per_router),
	       .restrict_turns(restrict_turns),
	       .connectivity(connectivity),
	       .routing_type(routing_type),
	       .port_id(port_id),
	       .vc_id(ivc))
	   pf
	     (.route_in_op(rim_route_op),
	      .inc_rc(rim_inc_rc),
	      .route_out_op(pf_route_op),
	      .error(pf_error_unmasked));
	   
	   wire 			  pf_error;
	   assign pf_error = rim_valid & pf_error_unmasked;
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		if(pf_error)
		  $display({"ERROR: Invalid output port selected at input ", 
			    "port %d, VC %d."}, port_id, ivc);
	     end
	   // synopsys translate_on
	   
	   
	   //-------------------------------------------------------------------
	   // decode and update lookahead routing info
	   //-------------------------------------------------------------------
	   
	   wire lar_active;
	   assign lar_active = irs_flit_valid | fct_flit_valid;// FIXME: this really only needs to be activated for head flits!
	   
	   wire [0:la_route_info_width-1] lar_la_route_info;
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
	       .vc_id(ivc),
	       .reset_type(reset_type))
	   lar
	     (.clk(clk),
	      .reset(reset),
	      .active(lar_active),
	      .router_address(router_address),
	      .route_port(rim_route_port),
	      .inc_rc(rim_inc_rc),
	      .route_info(rim_route_info),
	      .la_route_info(lar_la_route_info));
	   
	   
	   //-------------------------------------------------------------------
	   // mux for selecting eligible VCs in destination packet class
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs_per_class-1]   vem_elig_ocvc;
	   
	   begin:vem
	      
	      wire [0:num_vcs-1] elig_ovc;
	      assign elig_ovc = elig_op_ovc[rim_route_port*num_vcs +: num_vcs];
	      
	      wire [0:num_vcs_per_class-1] elig_ocvc;
	      if(vc_resource_class(ivc) == (num_resource_classes - 1))
		assign elig_ocvc = elig_ovc[vc_packet_class(ivc)*
					    num_vcs_per_class:
					    (vc_packet_class(ivc)+1)*
					    num_vcs_per_class-1];
	      else
		   assign elig_ocvc = rim_inc_rc ? 
				      elig_ovc[(vc_packet_class(ivc)+1)*
					       num_vcs_per_class:
					       (vc_packet_class(ivc)+2)*
					       num_vcs_per_class-1] : 
				      elig_ovc[vc_packet_class(ivc)*
					       num_vcs_per_class:
					       (vc_packet_class(ivc)+1)*
					       num_vcs_per_class-1];
	      
	      assign vem_elig_ocvc = elig_ocvc;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // arbitrate among all eligible VCs for selected packet class
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs_per_class-1]   vea_next_elig_ocvc;
	   
	   begin:vea
	      
	      wire [0:num_vcs_per_class-1] req;
	      assign req = vem_elig_ocvc;

	      wire [0:num_vcs_per_class-1] gnt;
	      c_fp_arbiter
		#(.num_ports(num_vcs_per_class))
	      vea
		(.req(req),
		 .gnt(gnt));

	      assign vea_next_elig_ocvc = gnt;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // 
	   //-------------------------------------------------------------------
	   
	   //-------------------------------------------------------------------
	   // track which output VC this input VC is assigned to
	   //-------------------------------------------------------------------
	   
	   wire 			  ovt_active;
	   assign ovt_active = fcm_flit_valid;
	   
	   wire [0:num_vcs_per_class-1]   ovt_assigned_ocvc;
	   wire [0:num_vcs-1] 		  ovt_route_ovc;
	   
	   begin:ovt
	      
	      wire [0:num_vcs_per_class-1] assigned_ocvc_s, assigned_ocvc_q;
	      assign assigned_ocvc_s
		= fcm_flit_head ? vea_next_elig_ocvc : assigned_ocvc_q;
	      c_dff
		#(.width(num_vcs_per_class),
		  .reset_type(reset_type))
	      assigned_ocvcq
		(.clk(clk),
		 .reset(1'b0),
		 .active(ovt_active),
		 .d(assigned_ocvc_s),
		 .q(assigned_ocvc_q));
	      
	      assign ovt_assigned_ocvc = assigned_ocvc_q;
	      
	      wire [0:num_vcs_per_class-1] vcmask_ocvc;
	      assign vcmask_ocvc
		= {num_vcs_per_class{fcm_flit_head}} | ovt_assigned_ocvc;
	      
	      rtr_vc_align
		#(.num_message_classes(num_message_classes),
		  .num_resource_classes(num_resource_classes),
		  .num_vcs_per_class(num_vcs_per_class),
		  .vc_id(ivc))
	      ovt_route_ovc_vagn
		(.flag_ocvc(vcmask_ocvc),
		 .inc_rc(rim_inc_rc),
		 .flag_ovc(ovt_route_ovc));
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // track priority status
	   //-------------------------------------------------------------------
	   
	   wire 			   pst_active;
	   assign pst_active = rim_valid;
	   
	   wire 			   pst_prio;
	   
	   begin:pst
	      
	      wire [0:num_vcs*2-1] free_ovc;
	      assign free_ovc
		= free_op_ovc[rim_route_port*num_vcs*2 +: num_vcs*2];
	      
	      wire [0:num_vcs_per_class*2-1] free_ocvc;
	      if(vc_resource_class(ivc) == (num_resource_classes - 1))
		assign free_ocvc = free_ovc[vc_packet_class(ivc)*
					    num_vcs_per_class*2:
					    (vc_packet_class(ivc)+1)*
					    num_vcs_per_class*2-1];
	      else
		   assign free_ocvc = rim_inc_rc ? 
				      free_ovc[(vc_packet_class(ivc)+1)*
					       num_vcs_per_class*2:
					       (vc_packet_class(ivc)+2)*
					       num_vcs_per_class*2-1] :
				      free_ovc[vc_packet_class(ivc)*
					       num_vcs_per_class*2:
					       (vc_packet_class(ivc)+1)*
					       num_vcs_per_class*2-1];
	      
	      wire [0:1] 		     free;
	      
	      if(num_vcs_per_class > 1)
		begin
		   
		   wire [0:num_vcs_per_class-1] sel_ocvc;
		   assign sel_ocvc
		     = fcm_flit_head ? vem_elig_ocvc : ovt_assigned_ocvc;
		   
		   c_select_1ofn
		     #(.num_ports(num_vcs_per_class),
		       .width(2))
		   free_sel
		     (.select(sel_ocvc),
		      .data_in(free_ocvc),
		      .data_out(free));
		   
		end
	      else
		begin
		   assign free = free_ocvc;
		end
	      
	      wire free_1plus;
	      assign free_1plus = |free;
	      
	      wire free_2plus;
	      assign free_2plus = free[0];
	      
	      
	      wire prio_s, prio_q;
	      assign prio_s = fcm_flit_valid ?
			      :
			      free_1plus;
	      
			      /*
			       FIXME:
			       packet valid and flit valid and head and not sent --> elig
			       packet valid and flit valid and head and not tail and sent --> free_2p
			       packet valid and flit valid and head and tail and sent --> 0
			       packet valid and flit valid and not head and not sent --> free_1p
			       packet valid and flit valid and not head and not tail and sent --> free_2p
			       packet valid and flit valid and not head and tail and sent --> 0
			       packet valid and flit not valid --> free_1p
			       packet not valid --> 0
			       */
	      c_dff
		#(.width(1),
		  .reset_type(reset_type))
	      prioq
		(.clk(clk),
		 .reset(1'b0),
		 .active(pst_active),
		 .d(prio_s),
		 .q(prio_q));
	      
	      assign pst_prio = prio_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // collect errors
	   //-------------------------------------------------------------------
	   
	   wire [0:3] ivcs_errors;
	   assign ivcs_errors[0:1] = fbc_errors;
	   assign ivcs_errors[2] = rim_error;
	   assign ivcs_errors[3] = pf_error;
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs to top level
	   //-------------------------------------------------------------------
	   
	   assign fct_flit_valid_ivc[ivc] = fct_flit_valid;
	   
	   assign fcm_flit_valid_ivc[ivc] = fcm_flit_valid;
	   assign fcm_flit_head_ivc[ivc] = fcm_flit_head;
	   assign fcm_flit_tail_ivc[ivc] = fcm_flit_tail;
	   
	   assign rit_valid_ivc[ivc] = rit_valid;
	   assign vpd_route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = vpd_route_op;
	   
	   assign pf_route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = pf_route_op;
	   assign ovt_route_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]
		    = ovt_route_ovc;
	   
	   assign fbc_full_ivc[ivc] = fbc_full;
	   
	   assign pst_prio_ivc[ivc] = pst_prio;
	   
	   assign lar_la_route_info_ivc[ivc*la_route_info_width:
					(ivc+1)*la_route_info_width-1]
		    = lar_la_route_info;
	   
	   assign fbf_flit_data_ivc[ivc*flit_data_width:
				    (ivc+1)*flit_data_width-1]
		    = fbf_read_flit_data;
	   
	   assign ivcs_errors_ivc[ivc*4:(ivc+1)*4-1] = ivcs_errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // perform input VC arbitration
   //---------------------------------------------------------------------------
   
   wire 				     iva_active;
   assign iva_active = irs_flit_valid | |fct_flit_valid_ivc;
   
   wire [0:num_vcs-1] 			     iva_sel_ivc;
   
   generate
      
      begin:iva
	 
	 //---------------------------------------------------------------------
	 // arbitrate among high-priority requests
	 //---------------------------------------------------------------------
	 
	 wire [0:num_vcs-1] req_hp_ivc;
	 assign req_hp_ivc = fcm_flit_valid_ivc & pst_prio_ivc;
	 
	 wire 		    gnt_hp;
	 assign gnt_hp = |req_hp_ivc;
	 
	 wire 		    update_hp;
	 assign update_hp = gnt_hp & oai_gnt;
	 
	 wire [0:num_vcs-1] gnt_hp_ivc;
	 c_arbiter
	   #(.num_ports(num_vcs),
	     .arbiter_type(arbiter_type))
	 gnt_hp_ivc_arb
	   (.clk(clk),
	    .reset(reset),
	    .active(iva_active),
	    .req(req_hp_ivc),
	    .gnt(gnt_hp_ivc),
	    .update(update_hp));
	 
	 
	 //---------------------------------------------------------------------
	 // arbitrate among low-priority requests
	 //---------------------------------------------------------------------
	 
	 wire [0:num_vcs-1] req_lp_ivc;
	 assign req_lp_ivc = fcm_flit_valid_ivc;
	 
	 wire 		    gnt_lp;
	 assign gnt_lp = |req_lp_ivc & ~gnt_hp;
	 
	 wire 		    update_lp;
	 assign update_lp = gnt_lp & oai_gnt;
	 
	 wire [0:num_vcs-1] gnt_lp_raw_ivc;
	 c_arbiter
	   #(.num_ports(num_vcs),
	     .arbiter_type(arbiter_type))
	 gnt_lp_raw_ivc_arb
	   (.clk(clk),
	    .reset(reset),
	    .active(iva_active),
	    .req(req_lp_ivc),
	    .gnt(gnt_lp_raw_ivc),
	    .update(update_lp));
	 
	 wire [0:num_vcs-1] gnt_lp_ivc;
	 assign gnt_lp_ivc = gnt_lp_raw_ivc & {num_vcs{~gnt_hp}};
	 
	 
	 //---------------------------------------------------------------------
	 // combine grants
	 //---------------------------------------------------------------------
	 
	 assign iva_sel_ivc = gnt_hp_ivc | gnt_lp_ivc;
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output-side power management logic
   //---------------------------------------------------------------------------
   
   generate
      
      begin:opm
	 
	 wire [0:num_ports-1] iact_op;
	 assign iact_op
	   = ipd_route_op & {num_ports{irs_flit_valid & ihd_flit_head}};
	 
	 wire [0:num_ports-1] vact_op;
	 c_select_mofn
	   #(.num_ports(num_vcs),
	     .width(num_ports))
	 vact_op_sel
	   (.select(rit_valid_ivc),
	    .data_in(vpd_route_ivc_op),
	    .data_out(vact_op));
	 
	 // NOTE: Enable clocks for output modules whenever that output is 
	 // selected by one or more VCs, or if a new head flit arrives whose 
	 // lookahead routing information indicates it is destined for it.
	 // Note that this is pessimistic in both cases: For the VCs, there may
	 // not currently be a flit available, so a request may not be 
	 // generated; likewise, a newly arriving head flit may end up getting 
	 // buffered behind another packet, so it too may not cause a request
	 // to be generated. The reason we opt to use the pessimistic approach 
	 // is that this allows us to generate the timing-sensitive clock 
	 // enable signals relatively early on in the clock cycle.
	 assign act_op = iact_op | vact_op;
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output-side arbitration interface
   //---------------------------------------------------------------------------
   
   wire 		    oai_head;
   
   generate
      
      begin:oai
	 
	 wire head;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(1))
	 head_sel
	   (.select(iva_sel_ivc),
	    .data_in(fcm_flit_head_ivc),
	    .data_out(head));
	 
	 assign oai_head = head;
	 
	 wire tail;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(1))
	 tail_sel
	   (.select(iva_sel_ivc),
	    .data_in(fcm_flit_tail_ivc),
	    .data_out(tail));
	 
	 wire [0:num_ports-1] route_op;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(num_ports))
	 route_op_sel
	   (.select(iva_sel_ivc),
	    .data_in(pf_route_ivc_op),
	    .data_out(route_op));
	 
	 wire [0:num_vcs-1]   route_ovc;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(num_vcs))
	 route_ovc_sel
	   (.select(iva_sel_ivc),
	    .data_in(ovt_route_ivc_ovc),
	    .data_out(route_ovc));
	 
	 assign req_head = head;
	 assign req_tail = tail;
	 assign req_op = route_op;
	 assign req_ovc = route_ovc;
	 
	 wire 		      gnt;
	 assign gnt = |gnt_op;
	 
	 assign oai_gnt = gnt;
	 
	 assign oai_gnt_ivc = iva_sel_ivc & {num_vcs{gnt}};
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output multiplexer stage
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	      oms_gnt_ivc;
   
   wire 		      oms_active;
   assign oms_active = irs_flit_valid | |fct_flit_valid_ivc | |oms_gnt_ivc;
   
   wire [0:flit_data_width-1] oms_flit_data;
   
   generate
      
      begin:oms
	 
	 wire [0:num_vcs-1] gnt_ivc_s, gnt_ivc_q;
	 assign gnt_ivc_s = oai_gnt_ivc;
	 c_dff
	   #(.width(num_vcs),
	     .reset_type(reset_type))
	 gnt_ivcq
	   (.clk(clk),
	    .reset(reset),
	    .active(oms_active),
	    .d(gnt_ivc_s),
	    .q(gnt_ivc_q));
	 
	 assign oms_gnt_ivc = gnt_ivc_q;
	 
	 wire [0:flit_data_width-1] flit_data;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(flit_data_width))
	 flit_data_sel
	   (.select(gnt_ivc_q),
	    .data_in(fbf_flit_data_ivc),
	    .data_out(flit_data));
	 
	 assign oms_flit_data = flit_data;
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // lookahead routing info update
   //---------------------------------------------------------------------------
   
   wire 			    lau_active;
   assign lau_active = irs_flit_valid | |fct_flit_valid_ivc;// FIXME: this really only needs to be activated for head flits!
   
   generate
      
      begin:lau
	 
	 wire 		    flit_head_s, flit_head_q;
	 assign flit_head_s = oai_head;
	 c_dff
	   #(.width(1),
	     .reset_type(reset_type))
	 flit_headq
	   (.clk(clk),
	    .reset(1'b0),
	    .active(lau_active),
	    .d(flit_head_s),
	    .q(flit_head_q));
	 
	 wire [0:la_route_info_width-1] la_route_info_s, la_route_info_q;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(la_route_info_width))
	 la_route_info_s_sel
	   (.select(iva_sel_ivc),
	    .data_in(lar_la_route_info_ivc),
	    .data_out(la_route_info_s));
	 c_dff
	   #(.width(la_route_info_width),
	     .reset_type(reset_type))
	 la_route_infoq
	   (.clk(clk),
	    .reset(1'b0),
	    .active(lau_active),
	    .d(la_route_info_s),
	    .q(la_route_info_q));
	 
	 wire [0:la_route_info_width-1] orig_bits;
	 assign orig_bits = oms_flit_data[la_route_info_offset:
					  la_route_info_offset+
					  la_route_info_width-1];
	 
	 wire [0:la_route_info_width-1] muxed_bits;
	 assign muxed_bits = flit_head_q ? la_route_info_q : orig_bits;
	 
	 wire [0:flit_data_width-1] 	flit_data;
	 c_align
	   #(.in_width(la_route_info_width),
	     .out_width(flit_data_width),
	     .offset(la_route_info_offset))
	 flit_data_alg
	   (.data_in(muxed_bits),
	    .dest_in(oms_flit_data),
	    .data_out(flit_data));
	 
	 assign flit_data_out = flit_data;
	 
      end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // upstream flow control
   //---------------------------------------------------------------------------
   
   wire 		      ufc_active;
   assign ufc_active = irs_flit_valid | |fct_flit_valid_ivc | |oms_gnt_ivc;
   
   wire 		      ufc_cred_valid;
   assign ufc_cred_valid = oai_gnt;
   
   wire [0:num_vcs-1] 	      ufc_cred_sel_ivc;
   assign ufc_cred_sel_ivc = iva_sel_ivc;
   
   rtr_flow_ctrl_tx
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   ufc
     (.clk(clk),
      .reset(reset),
      .active(ufc_active),
      .flow_ctrl(flow_ctrl_out),
      .valid(ufc_cred_valid),
      .sel_ivc(ufc_cred_sel_ivc));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire chk_active;
	   assign chk_active = irs_flit_valid | |fct_flit_valid_ivc;
	   
	   wire [0:num_vcs*5-1]  errors_s, errors_q;
	   assign errors_s = ivcs_errors_ivc;
	   c_err_rpt
	     #(.num_errors(num_vcs*5),
	       .capture_mode(error_capture_mode),
	       .reset_type(reset_type))
	   chk
	     (.clk(clk),
	      .reset(reset),
	      .active(chk_active),
	      .errors_in(errors_s),
	      .errors_out(errors_q));
	   
	   assign error = |errors_q;
	   
	end
      else
	assign error = 1'b0;
      
   endgenerate
   
endmodule
