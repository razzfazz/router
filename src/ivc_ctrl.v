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

// input VC controller
module ivc_ctrl
  (clk, reset, router_address, flit_valid_in, flit_head_in, flit_tail_in, 
   header_info_in, flow_ctrl_op_ovc, vc_req, vc_req_op, vc_req_ovc, vc_gnt, 
   vc_gnt_ovc, sw_req_nonspec, sw_req_nonspec_op, sw_req_spec, sw_req_spec_op, 
   sw_gnt_nonspec, sw_gnt_spec, flit_valid_out, flit_head_out, flit_tail_out, 
   flit_vc_out, la_route_info_out, fbf_write_addr, fbf_read_addr, error, 
   events);
   
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
   
   // width of credit hold register
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_PUSH)
   localparam cred_hold_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs available for each class
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
   
   // width required to select individual router in network
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
   localparam route_info_width
     = num_routing_classes * router_addr_width + node_addr_width;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width = la_route_info_width + route_info_width;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
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
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter sw_spec_enable = 1;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   // function to extract traffic class from VC index
   // (this implementation handles the case where we have only a single traffic
   // class correctly)
   function integer get_traffic_class(input integer vc);
      begin
	 get_traffic_class
	   = (vc / (num_routing_classes * num_vcs_per_class)) %
	     num_traffic_classes;
      end
   endfunction
   
   // current traffic class
   localparam traffic_class = get_traffic_class(vc_id);
   
   // function to extract routing class from VC index
   // (this implementation handles the case where we have only a single routing
   // class correctly)
   function integer get_routing_class(input integer vc);
      begin
	 get_routing_class
	   = (vc / num_vcs_per_class) % num_routing_classes;
      end
   endfunction
   
   // current routing class
   localparam routing_class = get_routing_class(vc_id);
   
   // width of routing information required for each VC
   localparam vc_route_info_width
     = (routing_class == (num_routing_classes - 1)) ?
       addr_width :
       (routing_class == (num_routing_classes - 2)) ?
       (router_addr_width + addr_width) :
       (2 * router_addr_width);
   
   // total number of bits of header information required for each VC
   localparam hdff_width = la_route_info_width + vc_route_info_width;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(num_vcs*num_flit_buffers);
   
   // index of leftmost entry in shared flit buffer
   localparam fbf_min_addr = vc_id * num_flit_buffers;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // valid flit data available
   input flit_valid_in;
   
   // flit is head
   // (note: valid only when flit_valid_in=1)
   input flit_head_in;
   
   // flit is tail
   // (note: valid only when flit_valid_in=1)
   input flit_tail_in;
   
   // header information associated with current flit
   // (note: valid only when flit_valid_in=1 and flit_head_in=1)
   input [0:header_info_width-1] header_info_in;
   
   // internal flow control signalling from output controller to input 
   // controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] flow_ctrl_op_ovc;
   
   // request VC allocation
   output vc_req;
   wire vc_req;
   
   // desired port for VC allocation
   output [0:num_ports-1] vc_req_op;
   wire [0:num_ports-1] vc_req_op;
   
   // allowable VCs for VC allocation
   output [0:num_vcs-1] vc_req_ovc;
   wire [0:num_vcs-1] 	vc_req_ovc;
   
   // VC allocation successful
   input vc_gnt;
   
   // granted output VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // non-speculative switch allocator requests
   output sw_req_nonspec;
   wire 		sw_req_nonspec;
   
   // port selects for non-speculative switch allocator requests
   output [0:num_ports-1] sw_req_nonspec_op;
   wire [0:num_ports-1] sw_req_nonspec_op;
   
   // speculative switch allocator requests
   output sw_req_spec;
   wire 		sw_req_spec;
   
   // port selects for speculative switch allocator requests
   output [0:num_ports-1] sw_req_spec_op;
   wire [0:num_ports-1] sw_req_spec_op;
   
   // non-speculative switch allocator grants
   input sw_gnt_nonspec;
   
   // speculative switch allocator grants
   input sw_gnt_spec;
   
   // outgoing flit valid
   output flit_valid_out;
   wire 		flit_valid_out;
   
   // outgoing flit is head
   // (note: only valid if flit_valid_out=1)
   output flit_head_out;
   wire 		flit_head_out;
   
   // outgoing flit is tail
   // (note: only valid if flit_valid_out=1)
   output flit_tail_out;
   wire 		flit_tail_out;
   
   // destination VC for outgoing flit
   // (note: only valid if flit_valid_out=1)
   output [0:vc_idx_width-1] flit_vc_out;
   wire [0:vc_idx_width-1] flit_vc_out;
   
   // lookahead routing information for outgoing flit
   // (note: only valid if flit_valid_out=1 and flit_head_out=1)
   output [0:la_route_info_width-1] la_route_info_out;
   wire [0:la_route_info_width-1] la_route_info_out;
   
   // write pointer for shared flit buffer
   output [0:fbf_addr_width-1] fbf_write_addr;
   wire [0:fbf_addr_width-1] fbf_write_addr;
   
   // read pointer for shared flit buffer
   output [0:fbf_addr_width-1] fbf_read_addr;
   wire [0:fbf_addr_width-1] fbf_read_addr;
   
   // internal error condition detected
   output error;
   wire 		     error;
   
   // performance counter events
   // (note: only valid if perf_ctr_enable=1)
   output [0:5] events;
   wire [0:5] 		     events;
   
   
   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   
   wire 		     packet_done;
   assign packet_done = flit_valid_out & flit_tail_out;
   
   wire 		     vc_allocated_s, vc_allocated_q;
   assign vc_allocated_s = (vc_allocated_q | vc_gnt) & ~packet_done;
   dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocatedq
     (.clk(clk),
      .reset(reset),
      .d(vc_allocated_s),
      .q(vc_allocated_q));
   
   wire [0:num_vcs_per_class-1] vc_gnt_unchanged_ocvc;
   assign vc_gnt_unchanged_ocvc
     = vc_gnt_ovc[(traffic_class*num_routing_classes+routing_class)*
		  num_vcs_per_class:
		  (traffic_class*num_routing_classes+routing_class+1)*
		  num_vcs_per_class-1];
   
   wire 			rtl_inc_rc;
   wire [0:num_vcs_per_class-1] vc_gnt_ocvc;
   
   generate
      
      if(routing_class == (num_routing_classes - 1))
	assign vc_gnt_ocvc = vc_gnt_unchanged_ocvc;
      else
	begin
	   
	   wire [0:num_vcs_per_class-1] vc_gnt_changed_ocvc;
	   assign vc_gnt_changed_ocvc
	     = vc_gnt_ovc[(traffic_class*num_routing_classes+routing_class+1)*
			  num_vcs_per_class:
			  (traffic_class*num_routing_classes+routing_class+2)*
			  num_vcs_per_class-1];
	   
	   // only one of the two will have a bit set, so we can just OR them
	   assign vc_gnt_ocvc = vc_gnt_changed_ocvc | vc_gnt_unchanged_ocvc;
	   
	end
      
   endgenerate

   wire [0:num_vcs_per_class-1] 	vc_allocated_ocvc_q;
   wire [0:num_vcs_per_class-1] 	vc_allocated_hold_ocvc;
   assign vc_allocated_hold_ocvc = vc_allocated_ocvc_q | vc_gnt_ocvc;
   
   wire [0:num_vcs_per_class-1] 	vc_allocated_ocvc_s;
   assign vc_allocated_ocvc_s
     = vc_allocated_hold_ocvc & ~{num_vcs_per_class{packet_done}};
   dff
     #(.width(num_vcs_per_class),
       .reset_type(reset_type))
   vc_allocated_ocvcq
     (.clk(clk),
      .reset(reset),
      .d(vc_allocated_ocvc_s),
      .q(vc_allocated_ocvc_q));
   
   wire 				vc_allocated;
   wire 				sw_allocated;
   
   generate
      
      if(sw_spec_enable)
	begin
	   assign vc_allocated = vc_gnt | vc_allocated_q;
	   assign sw_allocated = sw_gnt_nonspec | sw_gnt_spec;
	end
      else
	begin
	   assign vc_allocated = vc_allocated_q;
	   assign sw_allocated = sw_gnt_nonspec;
	end
      
   endgenerate
   
   assign flit_valid_out = sw_allocated & vc_allocated;
   
   
   //---------------------------------------------------------------------------
   // generate head and tail indicators
   //---------------------------------------------------------------------------
   
   wire fbc_empty;
   
   generate
      
      if(num_header_buffers > 1)
	begin
	   
	   // keep track of location(s) of head and tail flits in flit buffer
	   wire [0:num_flit_buffers-1] head_queue;
	   wire [0:num_flit_buffers-1] tail_queue;
	   
	   wire [0:num_flit_buffers-1] write_sel;
	   wire [0:num_flit_buffers-1] read_sel;
	   
	   genvar 		       idx;
	   
	   for(idx = 0; idx < num_flit_buffers; idx = idx + 1)
	     begin:idxs
		
		assign write_sel[idx]
			 = (fbf_write_addr == (fbf_min_addr + idx));
		assign read_sel[idx]
			 = (fbf_read_addr == (fbf_min_addr + idx));
		
		wire capture;
		assign capture = flit_valid_in & write_sel[idx];
		
		reg  head_q, tail_q;
		always @(posedge clk)
		  if(capture)
		    begin
		       head_q <= flit_head_in;
		       tail_q <= flit_tail_in;
		    end
		
		assign head_queue[idx] = head_q;
		assign tail_queue[idx] = tail_q;
		
	     end
	   
	   wire head_queue_muxed;
	   select_1ofn
	     #(.num_ports(num_flit_buffers),
	       .width(1))
	   flit_head_out_sel
	     (.select(read_sel),
	      .data_in(head_queue),
	      .data_out(head_queue_muxed));
	   
	   assign flit_head_out = fbc_empty ? flit_head_in : head_queue_muxed;
	   
	   wire tail_queue_muxed;
	   select_1ofn
	     #(.num_ports(num_flit_buffers),
	       .width(1))
	   flit_tail_out_sel
	     (.select(read_sel),
	      .data_in(tail_queue),
	      .data_out(tail_queue_muxed));
	   
	   assign flit_tail_out = fbc_empty ? flit_tail_in : tail_queue_muxed;
	   
	end
      else
	begin
	   
	   wire head_in;
	   assign head_in = flit_valid_in & flit_head_in;
	   
	   wire head_valid_s, head_valid_q;
	   assign head_valid_s = (head_valid_q | head_in) & ~flit_valid_out;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   head_validq
	     (.clk(clk),
	      .reset(reset),
	      .d(head_valid_s),
	      .q(head_valid_q));
	   
	   assign flit_head_out = fbc_empty ? flit_head_in : head_valid_q;
	   
	   wire 		     tail_in;
	   assign tail_in = flit_valid_in & flit_tail_in;
	   
	   wire [0:fbf_addr_width-1] tail_idx_s, tail_idx_q;
	   assign tail_idx_s = tail_in ? fbf_write_addr : tail_idx_q;
	   dff
	     #(.width(fbf_addr_width),
	       .reset_type(reset_type))
	   tail_idxq
	     (.clk(clk),
	      .reset(reset),
	      .d(tail_idx_s),
	      .q(tail_idx_q));
	   
	   wire 		     tail_valid_s, tail_valid_q;
	   assign tail_valid_s
	     = (tail_valid_q | tail_in) & ~(flit_valid_out & flit_tail_out);
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   tail_validq
	     (.clk(clk),
	      .reset(reset),
	      .d(tail_valid_s),
	      .q(tail_valid_q));
	   
	   assign flit_tail_out
	     = fbc_empty ?
	       flit_tail_in :
	       (tail_valid_q && (fbf_read_addr == tail_idx_q));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // header buffer
   //---------------------------------------------------------------------------
   
   wire [0:la_route_info_width-1] la_route_info_in;
   assign la_route_info_in = header_info_in[0:la_route_info_width-1];
   
   wire [0:route_info_width-1] 	  route_info_in;
   assign route_info_in
     = header_info_in[la_route_info_width:
		      la_route_info_width+route_info_width-1];
   
   wire [0:vc_route_info_width-1] vc_route_info_in;
   
   wire 			  hdff_empty;
   wire 			  hdff_error;
   
   wire 			  hdff_push;
   assign hdff_push = flit_valid_in & flit_head_in;
   
   wire 			  hdff_pop;
   assign hdff_pop = flit_valid_out & flit_tail_out;
   
   wire [0:la_route_info_width-1] hdff_la_route_info;
   wire [0:vc_route_info_width-1] hdff_vc_route_info;
   
   generate
      
      if((routing_class == (num_routing_classes - 1)) ||
	 (routing_class == (num_routing_classes - 2)))
	assign vc_route_info_in
	  = route_info_in[route_info_width-vc_route_info_width:
			  route_info_width-1];
      else
	assign vc_route_info_in
	  = route_info_in[routing_class*router_addr_width:
			  (routing_class+2)*router_addr_width-1];
      
      if(num_header_buffers > 1)
	begin
	   
	   wire [0:hdff_width-1] 	  hdff_data_in;
	   assign hdff_data_in[0:la_route_info_width-1] = la_route_info_in;
	   assign hdff_data_in[la_route_info_width:
			       la_route_info_width+vc_route_info_width-1]
		    = vc_route_info_in;
	   
	   wire hdff_full;
	   wire [0:hdff_width-1] hdff_data_out;
	   
	   fifo
	     #(.depth(num_header_buffers),
	       .width(hdff_width),
	       .fifo_type(header_fifo_type),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type))
	   hdff
	     (.clk(clk),
	      .reset(reset),
	      .full(hdff_full),
	      .data_in(hdff_data_in),
	      .push(hdff_push),
	      .empty(hdff_empty),
	      .data_out(hdff_data_out),
	      .pop(hdff_pop),
	      .error(hdff_error));
	   
	   assign hdff_la_route_info
	     = hdff_empty ?
	       la_route_info_in :
	       hdff_data_out[0:la_route_info_width-1];
	   assign hdff_vc_route_info
	     = hdff_empty ?
	       vc_route_info_in :
	       hdff_data_out[la_route_info_width:
			     la_route_info_width+vc_route_info_width-1];
   
	end
      else
	begin
	   
	   wire [0:la_route_info_width-1] hdff_la_route_info_s,
					  hdff_la_route_info_q;
	   assign hdff_la_route_info_s
	     = hdff_push ? la_route_info_in : hdff_la_route_info_q;
	   dff
	     #(.width(la_route_info_width),
	       .reset_type(reset_type))
	   hdff_la_route_infoq
	     (.clk(clk),
	      .reset(reset),
	      .d(hdff_la_route_info_s),
	      .q(hdff_la_route_info_q));
	   
	   assign hdff_la_route_info
	     = hdff_empty ? la_route_info_in : hdff_la_route_info_q;
	   
	   wire [0:vc_route_info_width-1] hdff_vc_route_info_s,
					  hdff_vc_route_info_q;
	   assign hdff_vc_route_info_s
	     = hdff_push ? vc_route_info_in : hdff_vc_route_info_q;
	   dff
	     #(.width(vc_route_info_width),
	       .reset_type(reset_type))
	   hdff_vc_route_infoq
	     (.clk(clk),
	      .reset(reset),
	      .d(hdff_vc_route_info_s),
	      .q(hdff_vc_route_info_q));
	   
	   assign hdff_vc_route_info
	     = hdff_empty ? vc_route_info_in : hdff_vc_route_info_q;
	   
	   wire hdff_empty_s, hdff_empty_q;
	   assign hdff_empty_s = (hdff_empty_q | (hdff_pop & ~hdff_push)) &
				 ~(hdff_push & ~hdff_pop);
	   dff
	     #(.width(1),
	       .reset_value(1'b1),
	       .reset_type(reset_type))
	   hdff_emptyq
	     (.clk(clk),
	      .reset(reset),
	      .d(hdff_empty_s),
	      .q(hdff_empty_q));
	   
	   assign hdff_empty = hdff_empty_q;
	   
	   assign hdff_error = ~hdff_empty_q & hdff_push;
	   
	end
      
   endgenerate
   
   wire 	header_valid;
   assign header_valid = ~hdff_empty | hdff_push;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] rtl_route_unmasked_op;
   assign rtl_route_unmasked_op = hdff_la_route_info[0:num_ports-1];
   
   wire [0:num_classes-1] rtl_next_class;
   
   generate
      
      if(routing_class < (num_routing_classes - 1))
	assign rtl_inc_rc = hdff_la_route_info[num_ports];
      else
	assign rtl_inc_rc = 1'b0;
      
      genvar otc;
      
      for(otc = 0; otc < num_traffic_classes; otc = otc + 1)
	begin:otcs
	   
	   genvar orc;
	   
	   for(orc = 0; orc < num_routing_classes; orc = orc + 1)
	     begin:orcs
		
		if((otc == traffic_class) && (orc == routing_class))
		  assign rtl_next_class[otc*num_routing_classes+orc]
			   = ~rtl_inc_rc;
		else if((otc == traffic_class) && (orc == (routing_class + 1)))
		  assign rtl_next_class[otc*num_routing_classes+orc]
			   = rtl_inc_rc;
		else
		  assign rtl_next_class[otc*num_routing_classes+orc]
			   = 1'b0;
		
	     end
	   
	end
      
   endgenerate
   
   wire [0:num_ports-1] rtl_route_op;
   wire rtl_error_unmasked;
   
   port_filter
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .num_nodes_per_router(num_nodes_per_router),
       .routing_function_type(routing_function_type),
       .port_id(port_id),
       .traffic_class(traffic_class),
       .routing_class(routing_class))
   pf
     (.route_op_in(rtl_route_unmasked_op),
      .inc_rc(rtl_inc_rc),
      .route_op_out(rtl_route_op),
      .error(rtl_error_unmasked));
   
   wire 	      rtl_error;
   assign rtl_error = rtl_error_unmasked & header_valid;
   
   wire [0:num_vcs-1] rtl_next_vcs;
   replicator
     #(.width(num_classes),
       .count(num_vcs_per_class))
   rtl_next_vcs_repl
     (.data_in(rtl_next_class),
      .data_out(rtl_next_vcs));
   
   la_routing_logic
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .routing_function_type(routing_function_type),
       .dimension_order(dimension_order),
       .port_id(port_id),
       .traffic_class(traffic_class),
       .routing_class(routing_class))
   lar
     (.router_address(router_address),
      .route_op(rtl_route_op),
      .inc_rc(rtl_inc_rc),
      .vc_route_info(hdff_vc_route_info),
      .la_route_info(la_route_info_out));
   
   
   //---------------------------------------------------------------------------
   // credit tracking
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*int_flow_ctrl_width-1] flow_ctrl_ovc;
   select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs*int_flow_ctrl_width))
   flow_ctrl_ovc_sel
     (.select(rtl_route_op),
      .data_in(flow_ctrl_op_ovc),
      .data_out(flow_ctrl_ovc));
   
   wire 				  free_allocated;
   wire 				  cred_tracker_error;
   
   generate
      
      case(credit_handling_type)
	
	`CREDIT_HANDLING_TYPE_LEVEL:
	  begin
	     
	     wire [0:num_vcs_per_class*2-1] free_unchanged_ocvc;
	     assign free_unchanged_ocvc
	       = flow_ctrl_ovc[(traffic_class*num_routing_classes+
				routing_class)*num_vcs_per_class*2:
			       (traffic_class*num_routing_classes+
				routing_class+1)*num_vcs_per_class*2-1];
	     
	     wire [0:num_vcs_per_class*2-1] free_ocvc;
	     
	     if(routing_class == (num_routing_classes - 1))
	       assign free_ocvc = free_unchanged_ocvc;
	     else
	       begin
		  
		  wire [0:num_vcs_per_class*2-1] free_changed_ocvc;
		  assign free_changed_ocvc
		    = flow_ctrl_ovc[(traffic_class*num_routing_classes+
				     routing_class+1)*num_vcs_per_class*2:
				    (traffic_class*num_routing_classes+
				     routing_class+2)*num_vcs_per_class*2-1];
		  
		  assign free_ocvc = rtl_inc_rc ?
				     free_changed_ocvc :
				     free_unchanged_ocvc;
		  
	       end
	     
	     wire 				 flit_sent_prev_s,
						 flit_sent_prev_q;
	     assign flit_sent_prev_s = flit_valid_out & ~flit_tail_out;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_sent_prevq
	       (.clk(clk),
		.reset(reset),
		.d(flit_sent_prev_s),
		.q(flit_sent_prev_q));
	     
	     wire [0:2] 			 flit_sent_count;
	     assign flit_sent_count = {flit_sent_prev_q & flit_valid_out,
				       flit_sent_prev_q ^ flit_valid_out,
				       ~(flit_sent_prev_q | flit_valid_out)};
	     
	     wire [0:num_vcs_per_class-1] 	 next_free_ocvc;
	     
	     genvar 				 cvc;
	     
	     for(cvc = 0; cvc < num_vcs_per_class; cvc = cvc + 1)
	       begin:cvcs
		  
		  wire [0:1] free;
		  assign free = free_ocvc[cvc*2:(cvc+1)*2-1];
		  
		  wire [0:2] free_by_count;
		  assign free_by_count = {|free, free[0], &free};
		  
		  wire       next_free;
		  select_1ofn
		    #(.num_ports(3),
		      .width(1))
		  next_free_sel
		    (.select(flit_sent_count),
		     .data_in(free_by_count),
		     .data_out(next_free));
		  
		  assign next_free_ocvc[cvc] = next_free;
		  
	       end
	     
	     wire 	     free_allocated_s, free_allocated_q;
	     assign free_allocated_s
	       = |(next_free_ocvc & vc_allocated_hold_ocvc)/* & ~packet_done*/;
	     dff
	       #(.width(1),
		 .reset_value(1'b1),
		 .reset_type(reset_type))
	     free_allocatedq
	       (.clk(clk),
		.reset(reset),
		.d(free_allocated_s),
		.q(free_allocated_q));
	     
	     assign free_allocated = free_allocated_q;
	     
	     assign cred_tracker_error = 1'b0;
	     
	  end
	
	`CREDIT_HANDLING_TYPE_PUSH:
	  begin
	     
	     wire [0:num_vcs_per_class-1] cred_unchanged_ocvc;
	     assign cred_unchanged_ocvc
	       = flow_ctrl_ovc[(traffic_class*num_routing_classes+
				routing_class)*num_vcs_per_class:
			       (traffic_class*num_routing_classes+
				routing_class+1)*num_vcs_per_class-1];
	     
	     wire [0:num_vcs_per_class-1] cred_ocvc;
	     
	     if(routing_class == (num_routing_classes - 1))
	       assign cred_ocvc = cred_unchanged_ocvc;
	     else
	       begin
		  
		  wire [0:num_vcs_per_class-1] cred_changed_ocvc;
		  assign cred_changed_ocvc
		    = flow_ctrl_ovc[(traffic_class*num_routing_classes+
				     routing_class+1)*num_vcs_per_class:
				    (traffic_class*num_routing_classes+
				     routing_class+2)*num_vcs_per_class-1];
		  
		  assign cred_ocvc = rtl_inc_rc ?
				     cred_changed_ocvc :
				     cred_unchanged_ocvc;
		  
	       end
	     
	     wire 			       cred;
	     assign cred
	       = |(cred_ocvc & vc_allocated_hold_ocvc)/* & ~packet_done*/;
	     
	     wire [0:cred_hold_width-1]        cred_hold_q;
	     
	     wire 			       has_cred_s, has_cred_q;
	     assign has_cred_s
	       = (vc_gnt ?
		  ~sw_gnt_spec :
		  ((has_cred_q & ~sw_gnt_nonspec) | (|cred_hold_q))) | cred;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     has_credq
	       (.clk(clk),
		.reset(reset),
		.d(has_cred_s),
		.q(has_cred_q));
	     
	     assign free_allocated = has_cred_q;
	     
	     wire 			       incr_cred_hold;
	     assign incr_cred_hold = cred & ~sw_gnt_nonspec;
	     
	     wire 			       decr_cred_hold;
	     assign decr_cred_hold = ~cred & sw_gnt_nonspec & |cred_hold_q;
	     
	     wire [0:cred_hold_width-1]        cred_hold_s;
	     assign cred_hold_s
	       = vc_gnt ?
		 ({cred_hold_width{1'b0}} + (cred & ~sw_gnt_spec)) :
		 vc_allocated_q ?
		 (cred_hold_q + incr_cred_hold - decr_cred_hold) :
		 cred_hold_q;
	     dff
	       #(.width(cred_hold_width),
		 .reset_type(reset_type))
	     cred_holdq
	       (.clk(clk),
		.reset(reset),
		.d(cred_hold_s),
		.q(cred_hold_q));
	     
	     assign cred_tracker_error
	       = vc_allocated_q && (cred_hold_q == num_flit_buffers-1) &&
		 incr_cred_hold;
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate allocator control signals
   //---------------------------------------------------------------------------
   
   wire 				       flit_valid;
   
   assign sw_req_nonspec
     = header_valid & flit_valid & vc_allocated_q & free_allocated;
   assign sw_req_nonspec_op = rtl_route_op;
   
   generate
      
      if(sw_spec_enable)
	begin
	   assign sw_req_spec = header_valid & flit_valid & ~vc_allocated_q;
	   assign sw_req_spec_op = rtl_route_op;
	end
      else
	begin
	   assign sw_req_spec = 1'b0;
	   assign sw_req_spec_op = {num_ports{1'b0}};
	end
      
   endgenerate
   
   assign vc_req = header_valid & ~vc_allocated_q;
   assign vc_req_op = rtl_route_op;
   assign vc_req_ovc = rtl_next_vcs;
   
   
   //---------------------------------------------------------------------------
   // generate target output VC to send along with flit data
   // (valid when flit_valid_out=1)
   //---------------------------------------------------------------------------
   
   generate
      
      if(track_vcs_at_output)
	assign flit_vc_out = vc_id;
      else
	begin
	   
	   wire [0:num_vcs_per_class-1] flit_ocvc;
	   
	   if(sw_spec_enable)
	     assign flit_ocvc = vc_allocated_hold_ocvc;
	   else
	     assign flit_ocvc = vc_allocated_ocvc_q;
	   
	   wire [0:num_vcs-1] flit_ovc;
	   
	   if(traffic_class > 0)
	     assign flit_ovc[0:traffic_class*num_routing_classes*
			     num_vcs_per_class-1]
		      = {(traffic_class*num_routing_classes*
			  num_vcs_per_class){1'b0}};
	   
	   if(routing_class > 0)
	     assign flit_ovc[traffic_class*num_routing_classes*
			     num_vcs_per_class:
			     (traffic_class*num_routing_classes+routing_class)*
			     num_vcs_per_class-1]
		      = {(routing_class*num_vcs_per_class){1'b0}};
	   
	   assign flit_ovc[(traffic_class*num_routing_classes+routing_class)*
			   num_vcs_per_class:
			   (traffic_class*num_routing_classes+routing_class+1)*
			   num_vcs_per_class-1]
		    = flit_ocvc & {num_vcs_per_class{~rtl_inc_rc}};
	   
	   if(routing_class < (num_routing_classes - 1))
	     assign flit_ovc[(traffic_class*num_routing_classes+
			      routing_class+1)*num_vcs_per_class:
			     (traffic_class*num_routing_classes+
			      routing_class+2)*num_vcs_per_class-1]
		      = flit_ocvc & {num_vcs_per_class{rtl_inc_rc}};

	   if(routing_class < (num_routing_classes - 2))
	     assign flit_ovc[(traffic_class*num_routing_classes+
			      routing_class+2)*num_vcs_per_class:
			     (traffic_class+1)*num_routing_classes*
			     num_vcs_per_class-1]
		      = {((num_routing_classes-routing_class-2)*
			  num_vcs_per_class){1'b0}};
	   
	   if(traffic_class < (num_traffic_classes - 1))
	     assign flit_ovc[(traffic_class+1)*num_routing_classes*
			     num_vcs_per_class:
			     num_traffic_classes*num_routing_classes*
			     num_vcs_per_class-1]
		      = {((num_traffic_classes-traffic_class-1)*
			  num_routing_classes*num_vcs_per_class){1'b0}};
	   
	   encoder
	     #(.num_ports(num_vcs))
	   flit_vc_out_enc
	     (.data_in(flit_ovc),
	      .data_out(flit_vc_out));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // flit buffer control
   //---------------------------------------------------------------------------
   
   wire 		       fbc_push;
   assign fbc_push = flit_valid_in;
   
   wire 		       fbc_pop;
   assign fbc_pop = flit_valid_out;
   
   wire 		       fbc_error;
   wire 		       fbc_full;
   fifo_ctrl
     #(.addr_width(fbf_addr_width),
       .offset(fbf_min_addr),
       .depth(num_flit_buffers),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push(fbc_push),
      .pop(fbc_pop),
      .write_addr(fbf_write_addr),
      .read_addr(fbf_read_addr),
      .empty(fbc_empty),
      .full(fbc_full),
      .error(fbc_error));
   
   assign flit_valid = flit_valid_in | ~fbc_empty;
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   wire [0:2] 		       errors_in;
   assign errors_in = {flit_valid & ~header_valid,
		       cred_tracker_error,
		       rtl_error};
   
   wire [0:2] 		       errors_out;
   checker
     #(.num_errors(3),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out | hdff_error | fbc_error;
   
   
   //---------------------------------------------------------------------------
   // instrumentation
   //---------------------------------------------------------------------------
   
   generate
      
      if(perf_ctr_enable > 0)
	begin
	   
	   wire 		       ev_no_flit;
	   assign ev_no_flit = header_valid & ~flit_valid;
	   
	   wire 		       ev_flit_stalled_vc;
	   assign ev_flit_stalled_vc
	     = header_valid & flit_valid & ~vc_allocated;
	   
	   wire 		       ev_flit_stalled_sw;
	   assign ev_flit_stalled_sw
	     = header_valid & flit_valid & vc_allocated & ~sw_allocated;
	   
	   wire 		       ev_spec_failed;
	   assign ev_spec_failed
	     = header_valid & flit_valid & ~vc_allocated & sw_allocated;
	   
	   wire 		       ev_flit_sent;
	   assign ev_flit_sent = flit_valid_out;
	   
	   wire 		       ev_flit_sent_spec;
	   assign ev_flit_sent_spec = flit_valid_out & ~vc_allocated_q;
	   
	   wire [0:5] 		       events_s, events_q;
	   assign events_s = {ev_no_flit,
			      ev_flit_stalled_vc,
			      ev_flit_stalled_sw,
			      ev_spec_failed,
			      ev_flit_sent,
			      ev_flit_sent_spec};
	   dff
	     #(.width(6),
	       .reset_type(reset_type))
	   eventsq
	     (.clk(clk),
	      .reset(reset),
	      .d(events_s),
	      .q(events_q));
	   assign events = events_q;
	   
	end
      else
	assign events = 6'd0;
      
   endgenerate
   
endmodule
