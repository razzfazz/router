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
module ip_ctrl
  (clk, reset, router_address, flit_ctrl_in, flit_data_in, 
   int_flow_ctrl_op_ovc, route_ivc_op, inc_rc_ivc, vc_req_ivc, vc_gnt_ivc, 
   vc_gnt_ivc_ovc, sw_req_nonspec_ivc, sw_req_spec_ivc, sw_gnt_nonspec_ivc, 
   sw_gnt_spec_ivc, flit_ctrl_out, flit_data_out, flow_ctrl_out, error);
   
`include "constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width required to select individual buffer slot
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = num_ports + ((num_routing_classes > 1) ? 1 : 0);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   localparam num_nodes_per_router
     = num_ports - num_dimensions * num_neighbors_per_dim;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
     = num_routing_classes * router_addr_width + node_addr_width;
   
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
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (credit_handling_type == `CREDIT_HANDLING_TYPE_LEVEL) ?
       2 :
       (credit_handling_type == `CREDIT_HANDLING_TYPE_PUSH) ?
       1 :
       -1;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // number of entries in flit buffer
   localparam fbf_depth = num_vcs*num_flit_buffers;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter sw_spec_enable = 1;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   // width of sum of event signals from all VCs
   localparam event_width = clogb(num_vcs) + 1;
   
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
   output [0:num_vcs*num_ports-1] route_ivc_op;
   wire [0:num_vcs*num_ports-1] route_ivc_op;
   
   // transition to next routing class
   output [0:num_vcs-1] inc_rc_ivc;
   wire [0:num_vcs-1] 		inc_rc_ivc;
   
   // request VC allocation
   output [0:num_vcs-1] vc_req_ivc;
   wire [0:num_vcs-1] 		vc_req_ivc;
   
   // VC allocation successful
   input [0:num_vcs-1] vc_gnt_ivc;
   
   // granted output VC
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   // non-speculative switch allocator requests
   output [0:num_vcs-1] sw_req_nonspec_ivc;
   wire [0:num_vcs-1] 		sw_req_nonspec_ivc;
   
   // speculative switch allocator requests
   output [0:num_vcs-1] sw_req_spec_ivc;
   wire [0:num_vcs-1] 		sw_req_spec_ivc;
   
   // non-speculative switch allocator grants
   input [0:num_vcs-1] sw_gnt_nonspec_ivc;
   
   // speculative switch allocator grants
   input [0:num_vcs-1] sw_gnt_spec_ivc;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] 	flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] 	flit_data_out;

   // outgoing flow control signals
   output [0:flow_ctrl_width-1] flow_ctrl_out;
   wire [0:flow_ctrl_width-1] flow_ctrl_out;
   
   // internal error condition detected
   output error;
   wire 			error;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   wire [0:flit_ctrl_width-1] 	flit_ctrl_in_s, flit_ctrl_in_q;
   assign flit_ctrl_in_s = flit_ctrl_in;

   wire 			flit_valid_in_s, flit_valid_in_q;
   assign flit_valid_in_s = flit_ctrl_in_s[0];
   dff
     #(.width(1),
       .reset_type(reset_type))
   flit_valid_inq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_in_s),
      .q(flit_valid_in_q));
   
   assign flit_ctrl_in_q[0] = flit_valid_in_q;
   
   generate
      
      if(flit_ctrl_width > 1)
	begin
	   
	   dff
	     #(.width(flit_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flit_ctrl_inq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_ctrl_in_s[1:flit_ctrl_width-1]),
	      .q(flit_ctrl_in_q[1:flit_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   wire [0:flit_data_width-1] 	      flit_data_in_s, flit_data_in_q;
   assign flit_data_in_s = flit_data_in;
   dff
     #(.width(flit_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_dataq
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
   
   wire [0:num_vcs-1] 		flit_valid_out_ivc;
   wire [0:num_vcs*flit_ctrl_width-1] flit_ctrl_out_ivc;
   wire [0:num_vcs*fbf_addr_width-1]  fbf_write_addr_ivc;
   wire [0:num_vcs*fbf_addr_width-1]  fbf_read_addr_ivc;
   wire [0:num_vcs*la_route_info_width-1] la_route_info_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] fbf_write_offset_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] fbf_read_offset_ivc;
   wire [0:num_vcs-1] 			    ivcc_error_ivc;
   wire [0:num_vcs*6-1] 		    events_ivc;
   generate
      
      genvar 				    ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire vc_gnt;
	   assign vc_gnt = vc_gnt_ivc[ivc];
	   
	   wire [0:num_vcs-1] vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
	   
	   wire 	      sw_gnt_nonspec;
	   assign sw_gnt_nonspec = sw_gnt_nonspec_ivc[ivc];
	   
	   wire 	      sw_gnt_spec;
	   assign sw_gnt_spec = sw_gnt_spec_ivc[ivc];
	   
	   wire [0:num_ports-1] route_op;
	   wire 		inc_rc;
	   wire 		vc_req;
	   wire 		sw_req_nonspec;
	   wire 		sw_req_spec;
	   wire [0:flit_ctrl_width-1] flit_ctrl_out;
	   wire [0:la_route_info_width-1] la_route_info;
	   wire [0:fbf_addr_width-1] 	  fbf_write_addr;
	   wire [0:fbf_addr_width-1] 	  fbf_read_addr;
	   wire 			  ivcc_error;
	   wire [0:5] 			  events;
	   ivc_ctrl
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_ports(num_ports),
	       .num_dimensions(num_dimensions),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .packet_format(packet_format),
	       .max_payload_length(max_payload_length),
	       .min_payload_length(min_payload_length),
	       .track_vcs_at_output(track_vcs_at_output),
	       .restrict_turns(restrict_turns),
	       .routing_function_type(routing_function_type),
	       .dimension_order(dimension_order),
	       .credit_handling_type(credit_handling_type),
	       .header_fifo_type(header_fifo_type),
	       .sw_spec_enable(sw_spec_enable),
	       .perf_ctr_enable(perf_ctr_enable),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .port_id(port_id),
	       .vc_id(ivc),
	       .reset_type(reset_type))
	   ivcc
	     (.clk(clk),
	      .reset(reset),
	      .router_address(router_address),
	      .flit_ctrl_in(flit_ctrl_in_q),
	      .header_info_in(header_info_in_q),
	      .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
	      .route_op(route_op),
	      .inc_rc(inc_rc),
	      .vc_req(vc_req),
	      .vc_gnt(vc_gnt),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .sw_req_nonspec(sw_req_nonspec),
	      .sw_req_spec(sw_req_spec),
	      .sw_gnt_nonspec(sw_gnt_nonspec),
	      .sw_gnt_spec(sw_gnt_spec),
	      .flit_ctrl_out(flit_ctrl_out),
	      .la_route_info_out(la_route_info),
	      .fbf_write_addr(fbf_write_addr),
	      .fbf_read_addr(fbf_read_addr),
	      .error(ivcc_error),
	      .events(events));
	   
	   assign route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = route_op;
	   assign inc_rc_ivc[ivc] = inc_rc;
	   assign vc_req_ivc[ivc] = vc_req;
	   assign sw_req_nonspec_ivc[ivc] = sw_req_nonspec;
	   assign sw_req_spec_ivc[ivc] = sw_req_spec;
	   assign flit_valid_out_ivc[ivc] = flit_ctrl_out[0];
	   assign flit_ctrl_out_ivc[ivc*flit_ctrl_width:
				    (ivc+1)*flit_ctrl_width-1]
		    = flit_ctrl_out;
	   assign la_route_info_ivc[ivc*la_route_info_width:
				    (ivc+1)*la_route_info_width-1]
		    = la_route_info;
	   assign fbf_write_addr_ivc[ivc*fbf_addr_width:
				     (ivc+1)*fbf_addr_width-1]
		    = fbf_write_addr;
	   assign fbf_read_addr_ivc[ivc*fbf_addr_width:
				    (ivc+1)*fbf_addr_width-1]
		    = fbf_read_addr;
	   assign fbf_write_offset_ivc[ivc*flit_buffer_idx_width:
				       (ivc+1)*flit_buffer_idx_width-1]
		    = fbf_write_addr[fbf_addr_width-flit_buffer_idx_width:
				     fbf_addr_width-1];
	   assign fbf_read_offset_ivc[ivc*flit_buffer_idx_width:
				      (ivc+1)*flit_buffer_idx_width-1]
		    = fbf_read_addr[fbf_addr_width-flit_buffer_idx_width:
				    fbf_addr_width-1];
	   assign ivcc_error_ivc[ivc] = ivcc_error;
	   assign events_ivc[ivc*6:(ivc+1)*6-1] = events;
	   
	end
      
   endgenerate
   
   assign error = |ivcc_error_ivc;
   
   
   //---------------------------------------------------------------------------
   // address computation
   //---------------------------------------------------------------------------
   
   wire [0:fbf_addr_width-1] 		  fbf_write_addr;
   wire [0:fbf_addr_width-1] 		  fbf_read_addr;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc_in_q;
	   assign flit_vc_in_q = flit_ctrl_in_q[1:1+vc_idx_width-1];
	   
	   // use optimized version for power-of-two buffer sizes
	   if(num_vcs == (1 << vc_idx_width))
	     begin
		
		wire [0:flit_buffer_idx_width-1] fbf_write_offset;
		assign fbf_write_offset
		  = fbf_write_offset_ivc[flit_vc_in_q*flit_buffer_idx_width +:
					 flit_buffer_idx_width];
		
		wire [0:vc_idx_width-1] 	 fbf_write_base;
		assign fbf_write_base = flit_vc_in_q;
		
		assign fbf_write_addr = {fbf_write_base, fbf_write_offset};
		
		wire [0:flit_buffer_idx_width-1] fbf_read_offset;
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_buffer_idx_width))
		fbf_read_offset_sel
		  (.select(flit_valid_out_ivc),
		   .data_in(fbf_read_offset_ivc),
		   .data_out(fbf_read_offset));
		
		wire [0:vc_idx_width-1] 	 fbf_read_base;
		encoder
		  #(.num_ports(num_vcs))
		fbf_read_base_enc
		  (.data_in(flit_valid_out_ivc),
		   .data_out(fbf_read_base));
		
		assign fbf_read_addr = {fbf_read_base, fbf_read_offset};
		
	     end
	   
	   // in the general case, mux in the full address
	   else
	     begin
		
		assign fbf_write_addr
		  = fbf_write_addr_ivc[flit_vc_in_q*fbf_addr_width +:
				       fbf_addr_width];
		
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(fbf_addr_width))
		fbf_read_addr_sel
		  (.select(flit_valid_out_ivc),
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
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire 			     fbf_write_enable;
   assign fbf_write_enable = flit_valid_in_q;
   
   wire 			     fbf_read_enable;
   assign fbf_read_enable = |flit_valid_out_ivc;
   
   wire [0:flit_data_width-1] 	     fbf_write_data;
   assign fbf_write_data = flit_data_in_q;
   
   wire [0:flit_data_width-1] 	     fbf_read_data;
   regfile
     #(.width(flit_data_width),
       .depth(fbf_depth),
       .regfile_type(fbf_regfile_type))
   fbf
     (.clk(clk),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(fbf_write_data),
      .read_enable(fbf_read_enable),
      .read_address(fbf_read_addr),
      .read_data(fbf_read_data));
   
   
   //---------------------------------------------------------------------------
   // generate outputs to switch
   //---------------------------------------------------------------------------
   
   wire 			     flit_valid_out_s, flit_valid_out_q;
   assign flit_valid_out_s = |flit_valid_out_ivc;
   dff
     #(.width(1),
       .reset_type(reset_type))
   flit_valid_outq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_out_s),
      .q(flit_valid_out_q));
   
   wire [0:flit_ctrl_width-1] 	     flit_ctrl_out_s, flit_ctrl_out_q;
   assign flit_ctrl_out_q[0] = flit_valid_out_q;
   
   generate
      
      if(flit_ctrl_width > 1)
	begin
	   
	   select_1ofn
	     #(.num_ports(num_vcs),
	       .width(flit_ctrl_width))
	   flit_ctrl_out_s_sel
	     (.select(flit_valid_out_ivc),
	      .data_in(flit_ctrl_out_ivc),
	      .data_out(flit_ctrl_out_s));
	   
	   dff
	     #(.width(flit_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flit_ctrl_outq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_ctrl_out_s[1:flit_ctrl_width-1]),
	      .q(flit_ctrl_out_q[1:flit_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   wire flit_head_out_q;
   assign flit_head_out_q = flit_ctrl_out_q[1+vc_idx_width+0];
   
   assign flit_ctrl_out = flit_ctrl_out_q;
   
   wire [0:la_route_info_width-1] la_route_info_s, la_route_info_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(la_route_info_width))
   la_route_info_sel
     (.select(flit_valid_out_ivc),
      .data_in(la_route_info_ivc),
      .data_out(la_route_info_s));
   dff
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
   assign cred_valid_s = |flit_valid_out_ivc;
   dff
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
	   encoder
	     #(.num_ports(num_vcs))
	   cred_vc_out_enc
	     (.data_in(flit_valid_out_ivc),
	      .data_out(cred_vc_s));
	   dff
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
   interleaver
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
		add_nto1
		  #(.num_ports(num_vcs),
		    .width(1))
		event_sum_add
		  (.data_in(events[ctr*num_vcs:(ctr+1)*num_vcs-1]),
		   .data_out(event_sum));
		
		wire [0:perf_ctr_width-1] ctr_s, ctr_q;
		assign ctr_s = ctr_q + event_sum;
		dff
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
