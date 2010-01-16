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
   flit_data_in, elig_op_ovc, free_op_ovc, free_plus1_op_ovc, req_op, req_ovc, 
   req_head, req_tail, gnt_op, flit_data_out, error);
   
   
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
   
   // bit mask indicating which output VCs have credits available
   input [0:num_ports*num_vcs-1] free_op_ovc;
   
   // bit mask indicating which output VCs have two or more credits available
   input [0:num_ports*num_vcs-1] free_plus1_op_ovc;
   
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
   
   wire [0:num_vcs-1] 	      fbc_empty_ivc;
   wire [0:num_vcs-1] 	      fbc_full_ivc;
   
   wire [0:num_vcs-1] 	      oai_gnt_ivc;
   wire 		      oai_gnt;
   wire [0:num_vcs-1] 	      oms_gnt_ivc;
   
   
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
	 
	 wire [0:flit_ctrl_width-1] flit_ctrl_s, flit_ctrl_q;
	 assign flit_ctrl_s = flit_ctrl_in;
	 c_dff
	   #(.width(flit_ctrl_width),
	     .reset_type(`RESET_TYPE_NONE))
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
	     .reset_type(`RESET_TYPE_NONE))
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
   
   
   //---------------------------------------------------------------------------
   // buffers and control flow for each input VC
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 		    fct_flit_valid_ivc;
   wire [0:num_vcs-1] 		    fct_flit_head_ivc;
   wire [0:num_vcs-1] 		    fct_flit_tail_ivc;
   
   wire [0:num_vcs*num_ports-1]     pf_route_ivc_op;
   wire [0:num_vcs*num_vcs-1] 	    ovt_route_ivc_ovc;
   
   wire [0:num_vcs*la_route_info_width-1] lar_la_route_info_ivc;
   
   wire [0:num_vcs-1] 			  oct_free_ivc;
   
   wire [0:num_vcs*flit_data_width-1] 	  fbf_flit_data_ivc;
   
   wire [0:num_vcs*5-1] 		  ivcs_errors_ivc;
   
   genvar 				  ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   //-------------------------------------------------------------------
	   // forward declarations
	   //-------------------------------------------------------------------
	   
	   wire fct_flit_valid;
	   
	   
	   //-------------------------------------------------------------------
	   // connect inputs to top level
	   //-------------------------------------------------------------------
	   
	   wire irs_flit_valid;
	   assign irs_flit_valid = irs_flit_valid_ivc[ivc];
	   
	   wire oai_gnt;
	   assign oai_gnt = oai_gnt_ivc[ivc];
	   
	   wire oms_gnt;
	   assign oms_gnt = oms_gnt_ivc[ivc];
	   
	   
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
	   assign fbc_active = fct_flit_valid;
	   
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
	       .reset_type(`RESET_TYPE_NONE))
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
	   // track control info for current flit
	   //-------------------------------------------------------------------
	   
	   wire 				fct_active;
	   assign fct_active = fct_flit_valid;
	   
	   wire 				fct_flit_head;
	   wire 				fct_flit_tail;
	   
	   begin:fct
	      
	      assign fct_flit_valid = irs_flit_valid | ~fbc_empty;
	      
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
		  .reset_type(`RESET_TYPE_NONE))
	      flit_headq
		(.clk(clk),
		 .reset(1'b0),
		 .active(fct_active),
		 .d(flit_head_s),
		 .q(flit_head_q));
	      
	      assign fct_flit_head = fbc_empty ? fcd_flit_head : flit_head_q;
	      
	      wire muxed_flit_tail;
	      assign muxed_flit_tail
		= capture_fbf ? fbf_peek_flit_tail : fcd_flit_tail;
	      
	      wire flit_tail_s, flit_tail_q;
	      assign flit_tail_s = hold ? flit_tail_q : muxed_flit_tail;
	      c_dff
		#(.width(1),
		  .reset_type(`RESET_TYPE_NONE))
	      flit_tailq
		(.clk(clk),
		 .reset(1'b0),
		 .active(fct_active),
		 .d(flit_tail_s),
		 .q(flit_tail_q));
	      
	      assign fct_flit_tail = fbc_empty ? fcd_flit_tail : flit_tail_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // track route info for current packet
	   //-------------------------------------------------------------------
	   
	   wire 			rit_active;
	   assign rit_active = fct_flit_valid;
	   
	   wire [0:la_route_info_width-1] rit_la_route_info;
	   wire [0:route_info_width-1] 	  rit_route_info;
	   wire 			  rit_valid;
	   wire 			  rit_error;
	   
	   begin:rit
	      
	      wire valid_q;
	      
	      wire hold;
	      assign hold = valid_q & (~oai_gnt | ~fct_flit_tail);
	      
	      wire capture_fbf;
	      assign capture_fbf = ~fbc_empty & ~fbc_almost_empty;
	      
	      wire muxed_valid;
	      assign muxed_valid = (capture_fbf | irs_flit_valid) &
				   ~(fbc_empty & oai_gnt & fct_flit_tail);
	      
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
	      
	      wire [0:la_route_info_width-1] muxed_la_route_info;
	      assign muxed_la_route_info
		= capture_fbf ? fbf_peek_la_route_info : irs_la_route_info;
	      
	      wire [0:la_route_info_width-1] la_route_info_s, la_route_info_q;
	      assign la_route_info_s
		= hold ? la_route_info_q : muxed_la_route_info;
	      c_dff
		#(.width(la_route_info_width),
		  .reset_type(`RESET_TYPE_NONE))
	      la_route_infoq
		(.clk(clk),
		 .reset(1'b0),
		 .active(rit_active),
		 .d(la_route_info_s),
		 .q(la_route_info_q));
	      
	      assign rit_la_route_info
		= valid_q ? la_route_info_q : irs_la_route_info;
	      
	      wire [0:route_info_width-1]    muxed_route_info;
	      assign muxed_route_info
		= capture_fbf ? fbf_peek_route_info : irs_route_info;
	      
	      wire [0:route_info_width-1]    route_info_s, route_info_q;
	      assign route_info_s
		= hold ? route_info_q : muxed_route_info;
	      c_dff
		#(.width(route_info_width),
		  .reset_type(`RESET_TYPE_NONE))
	      route_infoq
		(.clk(clk),
		 .reset(1'b0),
		 .active(rit_active),
		 .d(route_info_s),
		 .q(route_info_q));
	      
	      assign rit_route_info
		= valid_q ? route_info_q : irs_route_info;
	      
	      assign rit_valid = valid_q | (irs_flit_valid /*& fcd_flit_head*/);
	      
	      // check for stray body/tail flit at input
	      assign rit_error = ~valid_q & irs_flit_valid & ~fcd_flit_head;
	      
	   end
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		if(rit_error)
		  $display({"ERROR: Stray body/tail flit at input port %d, ", 
			    "VC %d."}, port_id, ivc);
	     end
	   // synopsys translate_on
	   
	   
	   //-------------------------------------------------------------------
	   // decode and update lookahead routing info
	   //-------------------------------------------------------------------
	   
	   wire 				lar_active;
	   assign lar_active = fct_flit_valid;
	   
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
	     (.router_address(router_address),
	      .la_route_info_in(rit_la_route_info),
	      .route_port(lar_route_port),
	      .inc_rc(lar_inc_rc),
	      .route_info_in(rit_route_info),
	      .la_route_info_out(lar_la_route_info),
	      .error(lar_error_unmasked));
	   
	   wire 			  lar_error;
	   assign lar_error = rit_valid & lar_error_unmasked;
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		if(lar_error)
		  $display({"ERROR: Invalid lookahead routing information ", 
			    "detected at input port %d, VC %d."}, 
			   port_id, ivc);
	     end
	   // synopsys translate_on
	   
	   
	   //-------------------------------------------------------------------
	   // route port decoder
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	  rpd_route_op;
	   c_decoder
	     #(.num_ports(num_ports))
	   rpd
	     (.data_in(lar_route_port),
	      .data_out(rpd_route_op));
	   
	   
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
	     (.route_in_op(rpd_route_op),
	      .inc_rc(lar_inc_rc),
	      .route_out_op(pf_route_op),
	      .error(pf_error_unmasked));
	   
	   wire 			  pf_error;
	   assign pf_error = rit_valid & pf_error_unmasked;
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		if(pf_error)
		  $display({"ERROR: Invalid output port selected at input ", 
			    "port %d, VC %d."}, port_id, ivc);
	     end
	   // synopsys translate_on
	   
	   
	   //-------------------------------------------------------------------
	   // mux for selecting next eligible VC for current VC's packet class
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs_per_class-1]   vem_elig_ocvc;
	   rtr_vc_flag_mux
	     #(.num_message_classes(num_message_classes),
	       .num_resource_classes(num_resource_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_dimensions(num_dimensions),
	       .num_nodes_per_router(num_nodes_per_router),
	       .connectivity(connectivity),
	       .vc_id(ivc))
	   vem
	     (.route_port(lar_route_port),
	      .inc_rc(lar_inc_rc),
	      .flag_op_ovc(elig_op_ovc),
	      .flag_ocvc(vem_elig_ocvc));
	   
	   
	   //-------------------------------------------------------------------
	   // track which output VC this input VC is assigned to
	   //-------------------------------------------------------------------
	   
	   wire 			  ovt_active;
	   assign ovt_active = fct_flit_valid;
	   
	   wire [0:num_vcs_per_class-1]   ovt_assigned_ocvc;
	   wire [0:num_vcs-1] 		  ovt_route_ovc;
	   
	   begin:ovt
	      
	      wire [0:num_vcs_per_class-1] assigned_ocvc_s, assigned_ocvc_q;
	      assign assigned_ocvc_s
		= fcd_flit_head ? vem_elig_ocvc : assigned_ocvc_q;
	      c_dff
		#(.width(num_vcs_per_class),
		  .reset_type(`RESET_TYPE_NONE))
	      assigned_ocvcq
		(.clk(clk),
		 .reset(1'b0),
		 .active(ovt_active),
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
	   // track assigned output VC's credit level
	   //-------------------------------------------------------------------
	   
	   wire 			   oct_active;
	   assign oct_active = fct_flit_valid;
	   
	   wire 			   oct_free;
	   
	   begin:oct
	      
	      wire [0:num_vcs-1] free_ovc;
	      assign free_ovc = free_op_ovc[lar_route_port*num_vcs +: num_vcs];
	      
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
		= free_plus1_op_ovc[lar_route_port*num_vcs +: num_vcs];
	      
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
		     = fcd_flit_head ? vem_elig_ocvc : ovt_assigned_ocvc;
		   
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
		  .reset_type(`RESET_TYPE_NONE))
	      free_earlyq
		(.clk(clk),
		 .reset(1'b0),
		 .active(oct_active),
		 .d(free_s),
		 .q(free_q));
	      
	      wire free_plus1_s, free_plus1_q;
	      assign free_plus1_s = free_plus1;
	      c_dff
		#(.width(1),
		  .reset_type(`RESET_TYPE_NONE))
	      free_plus1q
		(.clk(clk),
		 .reset(1'b0),
		 .active(oct_active),
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
	      assign oct_free = oms_gnt ? free_plus1_q : free_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // collect errors
	   //-------------------------------------------------------------------
	   
	   wire [0:4] 			     ivcs_errors;
	   assign ivcs_errors[0:1] = fbc_errors;
	   assign ivcs_errors[2] = rit_error;
	   assign ivcs_errors[3] = lar_error;
	   assign ivcs_errors[4] = pf_error;
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs to top level
	   //-------------------------------------------------------------------
	   
	   assign fct_flit_valid_ivc[ivc] = fct_flit_valid;
	   assign fct_flit_head_ivc[ivc] = fct_flit_head;
	   assign fct_flit_tail_ivc[ivc] = fct_flit_tail;
	   
	   assign pf_route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = pf_route_op;
	   assign ovt_route_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]
		    = ovt_route_ovc;
	   
	   assign fbc_empty_ivc[ivc] = fbc_empty;
	   assign fbc_full_ivc[ivc] = fbc_full;
	   
	   assign oct_free_ivc[ivc] = oct_free;
	   
	   assign lar_la_route_info_ivc[ivc*la_route_info_width:
					(ivc+1)*la_route_info_width-1]
		    = lar_la_route_info;
	   
	   assign fbf_flit_data_ivc[ivc*flit_data_width:
				    (ivc+1)*flit_data_width-1]
		    = fbf_read_flit_data;
	   
	   assign ivcs_errors_ivc[ivc*5:(ivc+1)*5-1] = ivcs_errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // perform input VC arbitration
   //---------------------------------------------------------------------------
   
   wire 				     iva_active;
   assign iva_active = |(irs_flit_valid_ivc | ~fbc_empty_ivc);
   
   wire [0:num_vcs-1] 			     iva_sel_ivc;
   
   generate
      
      begin:iva
	 
	 //---------------------------------------------------------------------
	 // arbitrate among high-priority requests (body/tail flits with credit)
	 //---------------------------------------------------------------------
	 
	 wire [0:num_vcs-1] req_hp_ivc;
	 assign req_hp_ivc
	   = fct_flit_valid_ivc & ~fct_flit_head_ivc & oct_free_ivc;
	 
	 wire 		    gnt_hp;
	 assign gnt_hp = |req_hp_ivc;
	 
	 wire 		    update_hp;
	 assign update_hp = gnt_hp;
	 
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
	 // arbitrate among low-priority requests (head flits or no credit)
	 //---------------------------------------------------------------------
	 
	 wire [0:num_vcs-1] req_lp_ivc;
	 assign req_lp_ivc
	   = fct_flit_valid_ivc & (fct_flit_head_ivc | ~oct_free_ivc);
	 
	 wire 		    gnt_lp;
	 assign gnt_lp = |req_lp_ivc;
	 
	 wire 		    update_lp;
	 assign update_lp = gnt_lp & ~gnt_hp;
	 
	 wire [0:num_vcs-1] gnt_lp_ivc;
	 c_arbiter
	   #(.num_ports(num_vcs),
	     .arbiter_type(arbiter_type))
	 gnt_lp_ivc_arb
	   (.clk(clk),
	    .reset(reset),
	    .active(iva_active),
	    .req(req_lp_ivc),
	    .gnt(gnt_lp_ivc),
	    .update(update_lp));
	 
	 
	 //---------------------------------------------------------------------
	 // combine grants
	 //---------------------------------------------------------------------
	 
	 assign iva_sel_ivc = gnt_hp ? gnt_hp_ivc : gnt_lp_ivc;
	 
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
	    .data_in(fct_flit_head_ivc),
	    .data_out(head));
	 
	 assign oai_head = head;
	 
	 wire tail;
	 c_select_1ofn
	   #(.num_ports(num_vcs),
	     .width(1))
	 tail_sel
	   (.select(iva_sel_ivc),
	    .data_in(fct_flit_tail_ivc),
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
   
   wire 		      oms_active;
   assign oms_active = |(irs_flit_valid_ivc | ~fbc_empty_ivc | oms_gnt_ivc);
   
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
   assign lau_active = |(irs_flit_valid_ivc | ~fbc_empty_ivc);
   
   generate
      
      begin:lau
	 
	 wire 		    flit_head_s, flit_head_q;
	 assign flit_head_s = oai_head;
	 c_dff
	   #(.width(1),
	     .reset_type(`RESET_TYPE_NONE))
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
	     .reset_type(`RESET_TYPE_NONE))
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
	   #(.data_width(la_route_info_width),
	     .dest_width(flit_data_width),
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
   assign ufc_active = |(irs_flit_valid_ivc | ~fbc_empty_ivc | oms_gnt_ivc);
   
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
	   assign chk_active = |(irs_flit_valid_ivc | ~fbc_empty_ivc);
	   
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
