// $Id$

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
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



// input port controller
module vcr_ip_ctrl_mac
  (clk, reset, router_address, flit_ctrl_in, flit_data_in, 
   int_flow_ctrl_op_ovc, route_port_ivc, inc_rc_ivc, sw_oreq_nonspec_op, 
   sw_oreq_spec_op, sw_ognt_nonspec_op, sw_ognt_spec_op, sw_ignt_nonspec_op, 
   sw_ignt_spec_op, vc_req_ivc, vc_gnt_ivc, vc_gnt_ivc_ovc, int_flit_ctrl_out, 
   flit_data_out, flow_ctrl_out, fbf_write_addr, fbf_write_enable, 
   fbf_write_data, fbf_read_addr, fbf_read_enable, fbf_read_data, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width required to select individual buffer slot
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
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
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = port_idx_width + ((num_resource_classes > 1) ? 1 : 0);
   
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

   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width
     = 1 + vc_idx_width + 1 + 1;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (credit_handling_type == `CREDIT_HANDLING_TYPE_LEVEL) ?
       2 :
       (credit_handling_type == `CREDIT_HANDLING_TYPE_PUSH) ?
       1 :
       -1;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // number of entries in flit buffer
   localparam fbf_depth = num_vcs*num_flit_buffers;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
   // select implementation variant for VC allocator
   parameter vc_alloc_type = `VC_ALLOC_TYPE_SEP_IF;
   
   // select implementation variant for switch allocator
   parameter sw_alloc_type = `SW_ALLOC_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_alloc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type for switch allocator
   parameter sw_alloc_spec_type = `SW_ALLOC_SPEC_TYPE_REQ;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // width of sum of event signals from all VCs
   localparam event_width = clogb(num_vcs + 1);
   
   parameter reset_type = `RESET_TYPE_ASYNC;
      
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // internal flow control signalling from output controller to input 
   // controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   // destination port
   output [0:num_vcs*port_idx_width-1] route_port_ivc;
   wire [0:num_vcs*port_idx_width-1] route_port_ivc;
   
   // transition to next resource class
   output [0:num_vcs-1] inc_rc_ivc;
   wire [0:num_vcs-1] 		     inc_rc_ivc;
   
   // non-speculative switch allocation requests to output-side arbitration 
   // stage / wavefront block
   output [0:num_ports-1] sw_oreq_nonspec_op;
   wire [0:num_ports-1] 	     sw_oreq_nonspec_op;
   
   // speculative switch allocation requests to output-side arbitration stage or
   // wavefront block
   output [0:num_ports-1] sw_oreq_spec_op;
   wire [0:num_ports-1] 	     sw_oreq_spec_op;
   
   // non-speculative switch allocation grants from output-side arbitration 
   // stage / wavefront block
   input [0:num_ports-1] sw_ognt_nonspec_op;
   
   // speculative switch allocation grants from output-side arbitration stage or
   // wavefront block
   input [0:num_ports-1] sw_ognt_spec_op;
   
   // non-speculative switch allocation grants to output-side arbitration stage 
   // or wavefront block
   output [0:num_ports-1] sw_ignt_nonspec_op;
   wire [0:num_ports-1] 	     sw_ignt_nonspec_op;
   
   // speculative switch allocation grants to output-side arbitration stage or 
   // wavefront block
   output [0:num_ports-1] sw_ignt_spec_op;
   wire [0:num_ports-1] 	     sw_ignt_spec_op;
   
   // request VC allocation
   output [0:num_vcs-1] vc_req_ivc;
   wire [0:num_vcs-1] 		     vc_req_ivc;
   
   // VC allocation successful
   input [0:num_vcs-1] vc_gnt_ivc;
   
   // granted output VC
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   // outgoing flit control signals
   output [0:int_flit_ctrl_width-1] int_flit_ctrl_out;
   wire [0:int_flit_ctrl_width-1]    int_flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] 	     flit_data_out;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 	     flow_ctrl_out;
   
   // flit buffer write address
   output [0:fbf_addr_width-1] fbf_write_addr;
   wire [0:fbf_addr_width-1] 	     fbf_write_addr;
   
   // flit buffer write enable
   output fbf_write_enable;
   wire 			     fbf_write_enable;
   
   // flit buffer write data
   output [0:flit_data_width-1] fbf_write_data;
   wire [0:flit_data_width-1] 	     fbf_write_data;
   
   // flit buffer read address
   output [0:fbf_addr_width-1] fbf_read_addr;
   wire [0:fbf_addr_width-1] 	     fbf_read_addr;
   
   // flit buffer read enable
   output fbf_read_enable;
   wire 			     fbf_read_enable;
   
   // flit buffer read data
   input [0:flit_data_width-1] fbf_read_data;
   
   // internal error condition detected
   output error;
   wire 			     error;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   wire 			     flit_valid_in;
   
   wire [0:flit_ctrl_width-1] 	     flit_ctrl_in_s, flit_ctrl_in_q;
   assign flit_ctrl_in_s = flit_ctrl_in;
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     wire flit_valid_in_s, flit_valid_in_q;
	     assign flit_valid_in_s = flit_ctrl_in_s[0];
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_valid_inq
	       (.clk(clk),
		.reset(reset),
		.d(flit_valid_in_s),
		.q(flit_valid_in_q));
	     
	     assign flit_valid_in = flit_valid_in_q;
	     
	     assign flit_ctrl_in_q[0] = flit_valid_in_q;
	     
	     c_dff
	       #(.width(flit_ctrl_width-1),
		 .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	     flit_ctrl_inq
	       (.clk(clk),
	      .reset(reset),
		.d(flit_ctrl_in_s[1:flit_ctrl_width-1]),
		.q(flit_ctrl_in_q[1:flit_ctrl_width-1]));
	     
	  end
	
      endcase
      
   endgenerate
   
   wire [0:flit_data_width-1] flit_data_in_s, flit_data_in_q;
   assign flit_data_in_s = flit_data_in;
   c_dff
     #(.width(flit_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_data_inq
     (.clk(clk),
      .reset(reset),
      .d(flit_data_in_s),
      .q(flit_data_in_q));
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   // extract header information from header data
   wire [0:header_info_width-1] header_info_in_q;
   assign header_info_in_q = flit_data_in_q[0:header_info_width-1];
   
   // non-speculative switch allocator requests
   wire [0:num_vcs-1] 		sw_req_nonspec_ivc;
   
   // non-speculative switch allocator grants
   wire [0:num_vcs-1] 		sw_gnt_nonspec_ivc;
   
   // speculative switch allocator requests
   wire [0:num_vcs-1] 		sw_req_spec_ivc;
   
   // speculative switch allocator grants
   wire [0:num_vcs-1] 		sw_gnt_spec_ivc;

   wire [0:num_vcs-1] 		flit_valid_out_ivc;
   wire [0:num_vcs*int_flit_ctrl_width-1] int_flit_ctrl_out_ivc;
   wire [0:num_vcs*fbf_addr_width-1] 	  fbf_write_addr_ivc;
   wire [0:num_vcs*fbf_addr_width-1] 	  fbf_read_addr_ivc;
   wire [0:num_vcs*la_route_info_width-1] la_route_info_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] fbf_write_offset_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] fbf_read_offset_ivc;
   wire [0:num_vcs-1] 			    ivcc_error_ivc;
   wire [0:num_vcs*6-1] 		    events_ivc;
   wire [0:num_vcs*num_ports-1] 	    route_ivc_op;
   
   generate
      
      genvar 				    mc;
      
      for(mc = 0; mc < num_message_classes; mc = mc + 1)
	begin:mcs
	   
	   genvar irc;
	   
	   for(irc = 0; irc < num_resource_classes; irc = irc + 1)
	     begin:ircs
		
		genvar ivc;
		
		for(ivc = (mc*num_resource_classes+irc)*num_vcs_per_class;
		    ivc < (mc*num_resource_classes+irc+1)*num_vcs_per_class;
		    ivc = ivc + 1)
		  begin:ivcs
		     
		     wire vc_gnt;
		     assign vc_gnt = vc_gnt_ivc[ivc];
		     
		     wire [0:num_vcs-1] vc_gnt_ovc;
		     assign vc_gnt_ovc
		       = vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
		     
		     wire 		sw_gnt_nonspec;
		     assign sw_gnt_nonspec = sw_gnt_nonspec_ivc[ivc];
		     
		     wire               sw_gnt_spec;
		     assign sw_gnt_spec = sw_gnt_spec_ivc[ivc];
		     
		     wire [0:port_idx_width-1] route_port;
		     wire 		       inc_rc;
		     wire 		       vc_req;
		     wire 		       sw_req_nonspec;
		     wire 		       sw_req_spec;
		     wire [0:int_flit_ctrl_width-1] int_flit_ctrl_out;
		     wire [0:la_route_info_width-1] la_route_info;
		     wire [0:fbf_addr_width-1] 	    fbf_write_addr;
		     wire [0:fbf_addr_width-1] 	    fbf_read_addr;
		     wire 			    ivcc_error;
		     wire [0:5] 		    events;
		     vcr_ivc_ctrl
		       #(.num_flit_buffers(num_flit_buffers),
			 .num_header_buffers(num_header_buffers),
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
			 .routing_type(routing_type),
			 .dim_order(dim_order),
			 .credit_handling_type(credit_handling_type),
			 .header_fifo_type(header_fifo_type),
			 .vc_alloc_type(vc_alloc_type),
			 .sw_alloc_spec_type(sw_alloc_spec_type),
			 .perf_ctr_enable(perf_ctr_enable),
			 .checker_enable(checker_enable),
			 .checker_capture_mode(checker_capture_mode),
			 .vc_id(ivc),
			 .message_class(mc),
			 .resource_class(irc),
			 .reset_type(reset_type))
		     ivcc
		       (.clk(clk),
			.reset(reset),
			.router_address(router_address),
			.flit_ctrl_in(flit_ctrl_in_q),
			.header_info_in(header_info_in_q),
			.int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
			.route_port(route_port),
			.inc_rc(inc_rc),
			.vc_req(vc_req),
			.vc_gnt(vc_gnt),
			.vc_gnt_ovc(vc_gnt_ovc),
			.sw_req_nonspec(sw_req_nonspec),
			.sw_req_spec(sw_req_spec),
			.sw_gnt_nonspec(sw_gnt_nonspec),
			.sw_gnt_spec(sw_gnt_spec),
			.int_flit_ctrl_out(int_flit_ctrl_out),
			.la_route_info_out(la_route_info),
			.fbf_write_addr(fbf_write_addr),
			.fbf_read_addr(fbf_read_addr),
			.error(ivcc_error),
			.events(events));
		     
		     wire [0:num_ports-1] 	    route_op;
		     c_decoder
		       #(.num_ports(num_ports))
		     route_op_dec
		       (.data_in(route_port),
			.data_out(route_op));
		     
		     assign route_port_ivc[ivc*port_idx_width:
					   (ivc+1)*port_idx_width-1]
			      = route_port;
		     assign route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
			      = route_op;
		     assign inc_rc_ivc[ivc] = inc_rc;
		     assign vc_req_ivc[ivc] = vc_req;
		     assign sw_req_nonspec_ivc[ivc] = sw_req_nonspec;
		     assign sw_req_spec_ivc[ivc] = sw_req_spec;
		     assign flit_valid_out_ivc[ivc] = int_flit_ctrl_out[0];
		     assign int_flit_ctrl_out_ivc[ivc*int_flit_ctrl_width:
						  (ivc+1)*int_flit_ctrl_width-1]
			      = int_flit_ctrl_out;
		     assign la_route_info_ivc[ivc*la_route_info_width:
					      (ivc+1)*la_route_info_width-1]
			      = la_route_info;
		     assign fbf_write_addr_ivc[ivc*fbf_addr_width:
					       (ivc+1)*fbf_addr_width-1]
			      = fbf_write_addr;
		     assign fbf_read_addr_ivc[ivc*fbf_addr_width:
					      (ivc+1)*fbf_addr_width-1]
			      = fbf_read_addr;
		     assign fbf_write_offset_ivc[ivc*
						 flit_buffer_idx_width:
						 (ivc+1)*
						 flit_buffer_idx_width-1]
			      = fbf_write_addr[fbf_addr_width-
					       flit_buffer_idx_width:
					       fbf_addr_width-1];
		     assign fbf_read_offset_ivc[ivc*flit_buffer_idx_width:
						(ivc+1)*flit_buffer_idx_width-1]
			      = fbf_read_addr[fbf_addr_width-
					      flit_buffer_idx_width:
					      fbf_addr_width-1];
		     assign ivcc_error_ivc[ivc] = ivcc_error;
		     assign events_ivc[ivc*6:(ivc+1)*6-1] = events;
		     
		  end
		
	     end
	   
	end
      
   endgenerate
   
   assign error = |ivcc_error_ivc;
   
   
   //---------------------------------------------------------------------------
   // switch allocation
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 				    flit_sel_nonspec_ivc;
   
   vcr_sw_alloc_ip
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .allocator_type(sw_alloc_type),
       .arbiter_type(sw_alloc_arbiter_type),
       .reset_type(reset_type))
   swip_nonspec
     (.clk(clk),
      .reset(reset),
      .route_ivc_op(route_ivc_op),
      .req_in_ivc(sw_req_nonspec_ivc),
      .req_out_op(sw_oreq_nonspec_op),
      .gnt_in_op(sw_ognt_nonspec_op),
      .gnt_out_ivc(sw_gnt_nonspec_ivc),
      .gnt_out_op(sw_ignt_nonspec_op),
      .sel_ivc(flit_sel_nonspec_ivc));
   
   
   //---------------------------------------------------------------------------
   // speculative switch allocation support
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 				    flit_sel_ivc;
   
   wire 					    flit_valid_out;
   
   generate
      
      if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	begin
	   
	   // any non-speulative requests?
	   wire sw_req_nonspec;
	   assign sw_req_nonspec = |sw_req_nonspec_ivc;
	   
	   // any non-speculative grants?
	   wire sw_ognt_nonspec;
	   assign sw_ognt_nonspec = |sw_ognt_nonspec_op;
	   
	   wire [0:num_ports-1] sw_oreq_spec_unqual_op;
	   
	   case(sw_alloc_spec_type)
	     `SW_ALLOC_SPEC_TYPE_REQ:
	       begin
		  
		  // propagate all requests
		  assign sw_oreq_spec_op = sw_oreq_spec_unqual_op;
		  
	       end
	     `SW_ALLOC_SPEC_TYPE_GNT:
	       begin
		  
		  // do not propagate requests if a non-speculative grant was
		  // generated for this input
		  assign sw_oreq_spec_op
		    = {num_ports{~sw_ognt_nonspec}} & sw_oreq_spec_unqual_op;
		  
	       end
	     `SW_ALLOC_SPEC_TYPE_INT:
	       begin
		  
		  // do not propagate requests if any non-speculative requests
		  // were issued by this input's VCs
		  assign sw_oreq_spec_op
		    = {num_ports{~sw_req_nonspec}} & sw_oreq_spec_unqual_op;
		  
	       end
	   endcase
	   
	   wire [0:num_vcs-1] 	sw_gnt_spec_unqual_ivc;
	   wire [0:num_ports-1] sw_ignt_spec_unqual_op;
	   
	   case(sw_alloc_spec_type)
	     `SW_ALLOC_SPEC_TYPE_REQ:
	       begin
		  
		  // suppress grants if any non-speculative requests were issued
		  // by this input's VCs
		  assign sw_gnt_spec_ivc
		    = {num_vcs{~sw_req_nonspec}} & sw_gnt_spec_unqual_ivc;
		  assign sw_ignt_spec_op
		    = {num_ports{~sw_req_nonspec}} & sw_ignt_spec_unqual_op;
		  
	       end
	     `SW_ALLOC_SPEC_TYPE_GNT, `SW_ALLOC_SPEC_TYPE_INT:
	       begin
		  
		  // no additional masking requiured for grants
		  assign sw_gnt_spec_ivc = sw_gnt_spec_unqual_ivc;
		  assign sw_ignt_spec_op = sw_ignt_spec_unqual_op;
		  
	       end
	   endcase
	   
	   wire [0:num_vcs-1] flit_sel_spec_ivc;
	   
	   vcr_sw_alloc_ip
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .allocator_type(sw_alloc_type),
	       .arbiter_type(sw_alloc_arbiter_type),
	       .reset_type(reset_type))
	   swip_spec
	     (.clk(clk),
	      .reset(reset),
	      .route_ivc_op(route_ivc_op),
	      .req_in_ivc(sw_req_spec_ivc),
	      .req_out_op(sw_oreq_spec_unqual_op),
	      .gnt_in_op(sw_ognt_spec_op),
	      .gnt_out_ivc(sw_gnt_spec_unqual_ivc),
	      .gnt_out_op(sw_ignt_spec_unqual_op),
	      .sel_ivc(flit_sel_spec_ivc));
	   
	   case(sw_alloc_spec_type)
	     `SW_ALLOC_SPEC_TYPE_REQ, `SW_ALLOC_SPEC_TYPE_INT:
	       begin
		  
		  //------------------------------------------------------------
		  // In these cases, we know that any non-speculative requests 
		  // suppress speculative ones, so we can determine the read 
		  // address early.
		  //------------------------------------------------------------
		  
		  assign flit_sel_ivc
		    = sw_req_nonspec ? flit_sel_nonspec_ivc : flit_sel_spec_ivc;
		  
	       end
	     `SW_ALLOC_SPEC_TYPE_GNT:
	       begin
		  
		  //------------------------------------------------------------
		  // If masking based on grants, the speculative requests may
		  // end up going through even in the presence of 
		  // non-speculative requests, as the latter may not be granted.
		  //------------------------------------------------------------
		  
		  assign flit_sel_ivc = sw_ognt_nonspec ? 
					flit_sel_nonspec_ivc : 
					flit_sel_spec_ivc;
		  
	       end
	   endcase
	   
	   // if any output port was granted to this input port, a flit will be 
	   // sent out
	   assign flit_valid_out = sw_ognt_nonspec | |sw_ognt_spec_op;
	   
	end
      else
	begin
	   
	   /*
	   // if speculation is disabled, tie controls signals to zero
	   assign sw_gnt_spec_ivc = {num_vcs{1'b0}};
	   assign sw_oreq_spec_op = {num_ports{1'b0}};
	   assign sw_ignt_spec_op = {num_ports{1'b0}};
	   */
	   
	   // selector for flit buffer read address
	   assign flit_sel_ivc = flit_sel_nonspec_ivc;
	   
	   // if any output port was granted to this input port, a flit will be 
	   // sent out
	   assign flit_valid_out = |sw_ognt_nonspec_op;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // flit buffer control signals
   //---------------------------------------------------------------------------
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc_in_q;
	   assign flit_vc_in_q = flit_ctrl_in_q[1:1+vc_idx_width-1];
	   
	   // use optimized version for power-of-two buffer sizes
	   if(num_flit_buffers == (1 << flit_buffer_idx_width))
	     begin
		
		wire [0:flit_buffer_idx_width-1] fbf_write_offset;
		assign fbf_write_offset
		  = fbf_write_offset_ivc[flit_vc_in_q*flit_buffer_idx_width +:
					 flit_buffer_idx_width];
		
		wire [0:vc_idx_width-1] 	 fbf_write_base;
		assign fbf_write_base = flit_vc_in_q;
		
		assign fbf_write_addr = {fbf_write_base, fbf_write_offset};
		
		wire [0:flit_buffer_idx_width-1] fbf_read_offset;
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_buffer_idx_width))
		fbf_read_offset_sel
		  (.select(flit_sel_ivc),
		   .data_in(fbf_read_offset_ivc),
		   .data_out(fbf_read_offset));
		
		wire [0:vc_idx_width-1] 	 fbf_read_base;
		c_encoder
		  #(.num_ports(num_vcs))
		fbf_read_base_enc
		  (.data_in(flit_sel_ivc),
		   .data_out(fbf_read_base));
		
		assign fbf_read_addr = {fbf_read_base, fbf_read_offset};
		
	     end
	   
	   // in the general case, mux in the full address
	   else
	     begin
		
		assign fbf_write_addr
		  = fbf_write_addr_ivc[flit_vc_in_q*fbf_addr_width +:
				       fbf_addr_width];
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(fbf_addr_width))
		fbf_read_addr_sel
		  (.select(flit_sel_ivc),
		   .data_in(fbf_read_addr_ivc),
		   .data_out(fbf_read_addr));
		
	     end
	   
	end
      
      // if we only have a single VC, just use the address as is
      else
	begin
	   assign fbf_write_addr = fbf_write_addr_ivc;
	   assign fbf_read_addr = fbf_read_addr_ivc;
	end
      
   endgenerate
   
   assign fbf_write_enable = flit_valid_in;
   assign fbf_read_enable = flit_valid_out;
   assign fbf_write_data = flit_data_in_q;
   
   
   //---------------------------------------------------------------------------
   // generate outputs to switch
   //---------------------------------------------------------------------------
   
   wire 			     flit_valid_out_s, flit_valid_out_q;
   assign flit_valid_out_s = flit_valid_out;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_valid_outq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_out_s),
      .q(flit_valid_out_q));
   
   wire [0:int_flit_ctrl_width-1]    int_flit_ctrl_out_s, int_flit_ctrl_out_q;
   c_select_1ofn
     #(.num_ports(num_vcs),
       .width(int_flit_ctrl_width))
   int_flit_ctrl_out_s_sel
     (.select(flit_sel_ivc),
      .data_in(int_flit_ctrl_out_ivc),
      .data_out(int_flit_ctrl_out_s));
   
   c_dff
     #(.width(int_flit_ctrl_width-1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   int_flit_ctrl_outq
     (.clk(clk),
      .reset(reset),
      .d(int_flit_ctrl_out_s[1:int_flit_ctrl_width-1]),
      .q(int_flit_ctrl_out_q[1:int_flit_ctrl_width-1]));
   
   assign int_flit_ctrl_out_q[0] = flit_valid_out_q;
   
   wire flit_head_out_q;
   assign flit_head_out_q = int_flit_ctrl_out_q[1+vc_idx_width+0];
   
   assign int_flit_ctrl_out = int_flit_ctrl_out_q;
   
   wire [0:la_route_info_width-1] la_route_info_s, la_route_info_q;
   c_select_1ofn
     #(.num_ports(num_vcs),
       .width(la_route_info_width))
   la_route_info_sel
     (.select(flit_sel_ivc),
      .data_in(la_route_info_ivc),
      .data_out(la_route_info_s));
   c_dff
     #(.width(la_route_info_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   la_route_infoq
     (.clk(clk),
      .reset(reset),
      .d(la_route_info_s),
      .q(la_route_info_q));
   
   assign flit_data_out[0:la_route_info_width-1]
	    = flit_head_out_q ? 
	      la_route_info_q : 
	      fbf_read_data[0:la_route_info_width-1];
   assign flit_data_out[la_route_info_width:flit_data_width-1]
	    = fbf_read_data[la_route_info_width:flit_data_width-1];
   
   
   //---------------------------------------------------------------------------
   // generate outgoing credits
   //---------------------------------------------------------------------------
   
   wire 			     cred_valid_s, cred_valid_q;
   assign cred_valid_s = flit_valid_out;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign flow_ctrl_out[0] = cred_valid_q;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] cred_vc_s, cred_vc_q;
	   c_encoder
	     #(.num_ports(num_vcs))
	   cred_vc_out_enc
	     (.data_in(flit_sel_ivc),
	      .data_out(cred_vc_s));
	   c_dff
	     #(.width(vc_idx_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   cred_vcq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_vc_s),
	      .q(cred_vc_q));
	   
	   assign flow_ctrl_out[1:1+vc_idx_width-1] = cred_vc_q;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // performance counters
   //---------------------------------------------------------------------------
   
   wire [0:6*num_vcs-1] 	     events;
   c_interleaver
     #(.width(num_vcs*6),
       .num_blocks(num_vcs))
   events_intl
     (.data_in(events_ivc),
      .data_out(events));
   
   genvar 			     ctr;
   
   generate
      if(perf_ctr_enable > 0)
	begin
	   for(ctr = 0; ctr < 6; ctr = ctr + 1)
	     begin:ctrs
		
		wire [0:event_width-1] event_sum;
		c_add_nto1
		  #(.num_ports(num_vcs),
		    .width(1))
		event_sum_add
		  (.data_in(events[ctr*num_vcs:(ctr+1)*num_vcs-1]),
		   .data_out(event_sum));
		
		wire [0:perf_ctr_width-1] ctr_s, ctr_q;
		assign ctr_s = ctr_q + event_sum;
		c_dff
		  #(.width(perf_ctr_width),
		    .reset_type(reset_type))
		ctrq
		  (.clk(clk),
		   .reset(reset),
		   .d(ctr_s),
		   .q(ctr_q));
		
	     end
	end
   endgenerate
   
endmodule
