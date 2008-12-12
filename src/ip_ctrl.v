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
  (clk, reset, router_address, flit_ctrl_in, flit_data_in, flow_ctrl_op_ovc, 
   vc_req_ivc_op, vc_req_ivc_ovc, vc_gnt_ivc_ovc, sw_req_nonspec_ivc_op, 
   sw_req_spec_ivc_op, sw_gnt_nonspec_ivc, sw_gnt_spec_ivc, flit_ctrl_out, 
   flit_data_out, flow_ctrl_out, error);
   
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
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // width of sum of event signals from all VCs
   localparam event_width = clogb(num_vcs) + 1;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
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
   
   // total number of bits required for storing routing information
   localparam route_info_width = 2 * addr_width;
   
   // flit width
   parameter flit_data_width = 64;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_BY_RELATION;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_control_type = `INT_FLOW_CONTROL_TYPE_CREDIT_PUSH;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_control_type == `INT_FLOW_CONTROL_TYPE_CREDIT_LEVEL) ?
       2 :
       (int_flow_control_type == `INT_FLOW_CONTROL_TYPE_CREDIT_PUSH) ?
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
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_HEAD_TAIL;
   
   // width of control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ?
       // (valid + head/tail + vc_id)
       (1 + 2 + vc_idx_width) :
       -1;
   
   // select flow control type
   parameter flow_control_type = `FLOW_CONTROL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_control_type == `FLOW_CONTROL_TYPE_CREDIT) ?
       // (valid + vc_id)
       (1 + vc_idx_width) :
       -1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
      
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // internal flow control signalling from output controller to input 
   // controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] flow_ctrl_op_ovc;
   
   // request VC allocation for given port
   output [0:num_vcs*num_ports-1] vc_req_ivc_op;
   wire [0:num_vcs*num_ports-1] vc_req_ivc_op;
   
   // allowable VCs for VC allocation
   output [0:num_vcs*num_vcs-1] vc_req_ivc_ovc;
   wire [0:num_vcs*num_vcs-1] 	vc_req_ivc_ovc;
   
   // granted output VC
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   // non-speculative switch allocator requests
   output [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   
   // speculative switch allocator requests
   output [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   wire [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   
   // non-speculative switch allocator grants
   input [0:num_vcs-1] sw_gnt_nonspec_ivc;
   
   // speculative switch allocator grants
   input [0:num_vcs-1] sw_gnt_spec_ivc;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] 	flit_ctrl_out;
   
   // flit data for outgoing flit
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] 	flit_data_out;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] flow_ctrl_out;
   wire [0:flow_ctrl_width-1] 	flow_ctrl_out;
   
   // internal error condition detected
   output error;
   wire 			error;
   
   
   //---------------------------------------------------------------------------
   // for adaptive routing, must update route info if we're transitioning from
   // non-minimal to minimal at this hop!
   //---------------------------------------------------------------------------
   
   wire 			flit_head_in;
   
   wire [0:route_info_width-1] 	route_info;
   assign route_info = flit_data_in[0:route_info_width-1];
   
   wire [0:addr_width-1] 	next_address;
   assign next_address = route_info[0:addr_width-1];
   
   wire [0:addr_width-1] 	final_address;
   assign final_address = route_info[addr_width:2*addr_width-1];
   
   wire 			update_addr;
   assign update_addr = flit_head_in &&
			(router_address == next_address[0:router_addr_width-1]);
   
   wire [0:route_info_width-1] 	next_route_info;
   assign next_route_info
     = {update_addr ? final_address : next_address, final_address};
   
   wire [0:flit_data_width-1] 	flit_data_muxed;
   assign flit_data_muxed[0:route_info_width-1] = next_route_info;
   assign flit_data_muxed[route_info_width:flit_data_width-1]
	    = flit_data_in[route_info_width:flit_data_width-1];
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   // extract routing information from header data
   wire [0:route_info_width-1] 	route_info_in;
   assign route_info_in = flit_data_in[0:route_info_width-1];
   
   wire [0:num_vcs-1] 		flit_sent_ivc;
   wire [0:num_vcs*flit_ctrl_width-1] flit_ctrl_ivc;
   wire [0:num_vcs*fbf_addr_width-1]  fbf_write_addr_ivc;
   wire [0:num_vcs*fbf_addr_width-1]  fbf_read_addr_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] fbf_write_offset_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] fbf_read_offset_ivc;
   wire [0:num_vcs-1] 			    ivcc_error_ivc;
   wire [0:num_vcs*6-1] 		    events_ivc;
   
   generate
      
      genvar 				    ivc;
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire [0:num_vcs-1] 	vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
	   
	   wire 		sw_gnt_nonspec;
	   assign sw_gnt_nonspec = sw_gnt_nonspec_ivc[ivc];
	   
	   wire 		sw_gnt_spec;
	   assign sw_gnt_spec = sw_gnt_spec_ivc[ivc];
	   
	   wire [0:num_ports-1] vc_req_op;
	   wire [0:num_vcs-1] 	vc_req_ovc;
	   wire [0:num_ports-1] sw_req_nonspec_op;
	   wire [0:num_ports-1] sw_req_spec_op;
	   wire 		flit_sent;
	   wire [0:flit_ctrl_width-1] flit_ctrl_out;
	   wire [0:fbf_addr_width-1]  fbf_write_addr;
	   wire [0:fbf_addr_width-1]  fbf_read_addr;
	   wire 		      ivcc_error;
	   wire [0:5] 		      events;
	   ivc_ctrl
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_vcs(num_vcs),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_ports(num_ports),
	       .num_dimensions(num_dimensions),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .routing_function_type(routing_function_type),
	       .int_flow_control_type(int_flow_control_type),
	       .header_fifo_type(header_fifo_type),
	       .sw_spec_enable(sw_spec_enable),
	       .perf_ctr_enable(perf_ctr_enable),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .packet_format(packet_format),
	       .port_id(port_id),
	       .vc_id(ivc),
	       .reset_type(reset_type))
	   ivcc
	     (.clk(clk),
	      .reset(reset),
	      .router_address(router_address),
	      .flit_ctrl_in(flit_ctrl_in),
	      .route_info_in(route_info_in),
	      .flow_ctrl_op_ovc(flow_ctrl_op_ovc),
	      .vc_req_op(vc_req_op),
	      .vc_req_ovc(vc_req_ovc),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .sw_req_nonspec_op(sw_req_nonspec_op),
	      .sw_req_spec_op(sw_req_spec_op),
	      .sw_gnt_nonspec(sw_gnt_nonspec),
	      .sw_gnt_spec(sw_gnt_spec),
	      .flit_sent(flit_sent),
	      .flit_ctrl_out(flit_ctrl_out),
	      .fbf_write_addr(fbf_write_addr),
	      .fbf_read_addr(fbf_read_addr),
	      .error(ivcc_error),
	      .events(events));
	   
	   assign vc_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = vc_req_op;
	   assign vc_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1] = vc_req_ovc;
	   assign sw_req_nonspec_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = sw_req_nonspec_op;
	   assign sw_req_spec_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = sw_req_spec_op;
	   
	   assign flit_sent_ivc[ivc] = flit_sent;
	   assign flit_ctrl_ivc[ivc*flit_ctrl_width:(ivc+1)*flit_ctrl_width-1]
		    = flit_ctrl_out;
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
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire [0:fbf_addr_width-1] 	      fbf_write_addr;
   wire [0:fbf_addr_width-1] 	      fbf_read_addr;
   
   wire flit_valid_in;
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     assign flit_valid_in = flit_ctrl_in[0];
	     assign flit_head_in = flit_ctrl_in[1];
	  end
	
      endcase
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc_in;
	   
	   case(packet_format)
	     
	     `PACKET_FORMAT_HEAD_TAIL:
	       begin
		  assign flit_vc_in = flit_ctrl_in[3:3+vc_idx_width-1];
	       end
	     
	   endcase
	   
	   // use optimized version for power-of-two buffer sizes
	   if(num_vcs == (1 << vc_idx_width))
	     begin
		
		wire [0:flit_buffer_idx_width-1] fbf_write_offset;
		mux_nto1
		  #(.num_ports(num_vcs),
		    .width(flit_buffer_idx_width))
		fbf_write_offset_sel
		  (.select(flit_vc_in),
		   .data_in(fbf_write_offset_ivc),
		   .data_out(fbf_write_offset));
		
		wire [0:vc_idx_width-1] 	 fbf_write_base;
		assign fbf_write_base = flit_vc_in;
		
		assign fbf_write_addr = {fbf_write_base, fbf_write_offset};
		
		wire [0:flit_buffer_idx_width-1] fbf_read_offset;
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(flit_buffer_idx_width))
		fbf_read_offset_sel
		  (.select(flit_sent_ivc),
		   .data_in(fbf_read_offset_ivc),
		   .data_out(fbf_read_offset));
		
		wire [0:vc_idx_width-1] 	 fbf_read_base;
		encoder
		  #(.num_ports(num_vcs))
		fbf_read_base_enc
		  (.data_in(flit_sent_ivc),
		   .data_out(fbf_read_base));
		
		assign fbf_read_addr = {fbf_read_base, fbf_read_offset};
		
	     end
	   else
	     begin
		
		mux_nto1
		  #(.num_ports(num_vcs),
		    .width(fbf_addr_width))
		fbf_write_addr_sel
		  (.select(flit_vc_in),
		   .data_in(fbf_write_addr_ivc),
		   .data_out(fbf_write_addr));
		
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(fbf_addr_width))
		fbf_read_addr_sel
		  (.select(flit_sent_ivc),
		   .data_in(fbf_read_addr_ivc),
		   .data_out(fbf_read_addr));
		
	     end
	   
	end
      else
	begin
	   
	   assign fbf_write_addr = fbf_write_addr_ivc;
	   assign fbf_read_addr = fbf_read_addr_ivc;
	   
	end
      
   endgenerate
   
   wire 				    fbf_write_enable;
   assign fbf_write_enable = flit_valid_in;
   
   wire 				    fbf_read_enable;
   assign fbf_read_enable = |flit_sent_ivc;
   
   regfile
     #(.width(flit_data_width),
       .depth(fbf_depth),
       .regfile_type(fbf_regfile_type))
   fbf
     (.clk(clk),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(flit_data_muxed),
      .read_enable(fbf_read_enable),
      .read_address(fbf_read_addr),
      .read_data(flit_data_out));
   
   
   //---------------------------------------------------------------------------
   // generate outputs to switch
   //---------------------------------------------------------------------------
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     
	     wire flit_valid_s, flit_valid_q;
	     assign flit_valid_s = |flit_sent_ivc;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_validq
	       (.clk(clk),
		.reset(reset),
		.d(flit_valid_s),
		.q(flit_valid_q));
	     
	     assign flit_ctrl_out[0] = flit_valid_q;
	     
	     wire [0:flit_ctrl_width-1] flit_ctrl;
	     
	     if(num_vcs > 1)
	       begin
		  select_1ofn
		    #(.num_ports(num_vcs),
		      .width(flit_ctrl_width))
		  flit_ctrl_sel
		    (.select(flit_sent_ivc),
		     .data_in(flit_ctrl_ivc),
		     .data_out(flit_ctrl));
	       end
	     else
	       assign flit_ctrl = flit_ctrl_ivc;
	     
	     wire 			     flit_head_s, flit_head_q;
	     assign flit_head_s = flit_ctrl[1];
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_headq
	       (.clk(clk),
		.reset(reset),
		.d(flit_head_s),
		.q(flit_head_q));
	     
	     assign flit_ctrl_out[1] = flit_head_q;
	     
	     wire 			     flit_tail_s, flit_tail_q;
	     assign flit_tail_s = flit_ctrl[2];
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_tailq
	       (.clk(clk),
		.reset(reset),
		.d(flit_tail_s),
		.q(flit_tail_q));
	     
	     assign flit_ctrl_out[2] = flit_tail_q;
	     
	     if(num_vcs > 1)
	       begin
		  
		  // output VCs are tracked in input VC controllers, so we can 
		  // just reuse that information here
		  wire [0:vc_idx_width-1] flit_vc_s, flit_vc_q;
		  assign flit_vc_s = flit_ctrl[3:3+flit_ctrl_width-1];
		  dff
		    #(.width(vc_idx_width),
		      .reset_type(reset_type))
		  flit_vcq
		    (.clk(clk),
		     .reset(reset),
		     .d(flit_vc_s),
		     .q(flit_vc_q));
		  
		  assign flit_ctrl_out[3:3+flit_ctrl_width-1] = flit_vc_q;
		  
	       end
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate outgoing credits
   //---------------------------------------------------------------------------
   
   generate
      
      case(flow_control_type)
	
	`FLOW_CONTROL_TYPE_CREDIT:
	  begin
	     
	     wire cred_valid_s, cred_valid_q;
	     assign cred_valid_s = |flit_sent_ivc;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     cred_validq
	       (.clk(clk),
		.reset(reset),
		.d(cred_valid_s),
		.q(cred_valid_q));
	     
	     assign flow_ctrl_out[0] = cred_valid_q;
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] cred_vc_s, cred_vc_q;
		  encoder
		    #(.num_ports(num_vcs))
		  cred_vc_out_enc
		    (.data_in(flit_sent_ivc),
		     .data_out(cred_vc_s));
		  dff
		    #(.width(vc_idx_width),
		      .reset_type(reset_type))
		  cred_vcq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_vc_s),
		     .q(cred_vc_q));
		  
		  assign flow_ctrl_out[1:1+vc_idx_width-1] = cred_vc_q;
		  
	       end
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // performance counters
   //---------------------------------------------------------------------------
   
   wire [0:6*num_vcs-1]    events;
   interleaver
     #(.width(num_vcs*6),
       .num_blocks(num_vcs))
   events_intl
     (.data_in(events_ivc),
      .data_out(events));
   
   genvar 		   ctr;
   
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
