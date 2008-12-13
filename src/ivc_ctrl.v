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
   header_info_in, flow_ctrl_op_ovc, vc_req_op, vc_req_ovc, vc_gnt_ovc, 
   sw_req_nonspec_op, sw_req_spec_op, sw_gnt_nonspec, sw_gnt_spec, 
   flit_valid_out, flit_head_out, flit_tail_out, flit_vc_out, la_route_info_out,
   fbf_write_addr, fbf_read_addr, error, events);
   
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
     = port_idx_width + ((num_routing_classes > 1) ? 1 : 0);
   
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
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
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
   localparam vc_header_info_width = la_route_info_width + vc_route_info_width;
   
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
   
   // requests VC allocation for given port
   output [0:num_ports-1] vc_req_op;
   wire [0:num_ports-1] vc_req_op;
   
   // allowable VCs for VC allocation
   output [0:num_vcs-1] vc_req_ovc;
   wire [0:num_vcs-1] 	vc_req_ovc;
   
   // granted output VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // non-speculative switch allocator requests
   output [0:num_ports-1] sw_req_nonspec_op;
   wire [0:num_ports-1] sw_req_nonspec_op;
   
   // speculative switch allocator requests
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
   
   wire 		     vc_gnt;
   assign vc_gnt = |vc_gnt_ovc;
   
   wire 		     get_next_header;
   wire 		     allocated_s, allocated_q;
   assign allocated_s = (allocated_q | vc_gnt) & ~get_next_header;
   dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .d(allocated_s),
      .q(allocated_q));
   
   wire 		     vc_allocated;
   wire 		     sw_allocated;
   
   generate
      
      if(sw_spec_enable)
	begin
	   assign vc_allocated = vc_gnt | allocated_q;
	   assign sw_allocated = sw_gnt_nonspec | sw_gnt_spec;
	end
      else
	begin
	   assign vc_allocated = allocated_q;
	   assign sw_allocated = sw_gnt_nonspec;
	end
      
   endgenerate
   
   wire 		       all_allocated;
   assign all_allocated = sw_allocated & vc_allocated;
   
   wire 		       valid_q;
   
   assign flit_valid_out = valid_q & all_allocated;
   
   
   //---------------------------------------------------------------------------
   // keep track of when to get next header
   //---------------------------------------------------------------------------
   
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
	   
	   select_1ofn
	     #(.num_ports(num_flit_buffers),
	       .width(1))
	   flit_head_out_sel
	     (.select(read_sel),
	      .data_in(head_queue),
	      .data_out(flit_head_out));
	   
	   select_1ofn
	     #(.num_ports(num_flit_buffers),
	       .width(1))
	   flit_tail_out_sel
	     (.select(read_sel),
	      .data_in(tail_queue),
	      .data_out(flit_tail_out));
	   
	end
      else
	begin
	   
	   wire head_in;
	   assign head_in = flit_valid_in & flit_head_in;
	   
	   wire [0:fbf_addr_width-1] head_idx_s, head_idx_q;
	   assign head_idx_s = head_in ? fbf_write_addr : head_idx_q;
	   dff
	     #(.width(fbf_addr_width),
	       .reset_type(reset_type))
	   head_idxq
	     (.clk(clk),
	      .reset(reset),
	      .d(head_idx_s),
	      .q(head_idx_q));
	   
	   wire 		     head_valid_s, head_valid_q;
	   assign head_valid_s
	     = (head_valid_q & ~(all_allocated & flit_head_out)) | head_in;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   head_validq
	     (.clk(clk),
	      .reset(reset),
	      .d(head_valid_s),
	      .q(head_valid_q));
	   
	   assign flit_head_out = head_valid_q && (fbf_read_addr == head_idx_q);
	   
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
	     = (tail_valid_q & ~(all_allocated & flit_tail_out)) | tail_in;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   tail_validq
	     (.clk(clk),
	      .reset(reset),
	      .d(tail_valid_s),
	      .q(tail_valid_q));
	   
	   assign flit_tail_out = tail_valid_q && (fbf_read_addr == tail_idx_q);
	   
	end
      
   endgenerate
   
   assign get_next_header = ~valid_q | (all_allocated & flit_tail_out);
   
   
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
   
   wire [0:vc_header_info_width-1] vc_header_info_in;
   assign vc_header_info_in[0:la_route_info_width-1] = la_route_info_in;
   assign vc_header_info_in[la_route_info_width:
			    la_route_info_width+vc_route_info_width-1]
	    = vc_route_info_in;
   
   wire 			     hdff_empty;
   
   wire 			     hdff_push;
   assign hdff_push
     = flit_valid_in & flit_head_in & (~hdff_empty | ~get_next_header);
   
   wire 			     hdff_pop;
   assign hdff_pop = get_next_header & ~hdff_empty;
   
   wire [0:vc_header_info_width-1]   hdff_data;
   wire 			     hdff_error;
   
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
	   
	   wire hdff_full;
	   fifo
	     #(.depth(num_header_buffers-1),
	       .width(vc_header_info_width),
	       .fifo_type(header_fifo_type),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type))
	   hdff
	     (.clk(clk),
	      .reset(reset),
	      .full(hdff_full),
	      .data_in(vc_header_info_in),
	      .push(hdff_push),
	      .empty(hdff_empty),
	      .data_out(hdff_data),
	      .pop(hdff_pop),
	      .error(hdff_error));
	   
	end
      else
	begin
	   
	   assign hdff_empty = 1'b1;
	   assign hdff_data_out = {vc_header_info_width{1'b0}};
	   assign hdff_error = 1'b0;
	   
	end
      
   endgenerate
   
   wire 		       next_valid;
   assign next_valid = (flit_valid_in & flit_head_in) | ~hdff_empty;
   
   wire [0:vc_header_info_width-1] next_vc_header_info;
   assign next_vc_header_info = hdff_empty ? vc_header_info_in : hdff_data;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:la_route_info_width-1] next_la_route_info;
   assign next_la_route_info = next_vc_header_info[0:la_route_info_width-1];
   
   wire [0:port_idx_width-1] 	  rtl_next_port_enc;
   assign rtl_next_port_enc = next_la_route_info[0:port_idx_width-1];
   
   wire [0:num_ports-1] 	  rtl_next_port;
   wire 			  rtl_change_class;
   wire [0:num_ports-1] 	  rtl_error_unmasked_op;
   wire [0:num_classes-1] 	  rtl_next_class;
   
   generate
      
      if(routing_class != (num_routing_classes - 1))
	assign rtl_change_class = next_la_route_info[port_idx_width];
      else
	assign rtl_change_class = 1'b0;
      
      genvar 			  op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire port_sel;
	   assign port_sel = (rtl_next_port_enc == op);
	   
	   wire mask_port;
	   
	   if((routing_class != (num_routing_classes - 1)) &&
	      (op == port_id))
	     assign mask_port = ~rtl_change_class;
	   else if(((routing_class == (num_routing_classes - 1)) &&
		    (op == port_id)) ||
		   ((routing_class != (num_routing_classes - 1)) &&
		    (op >= (num_ports - num_nodes_per_router))))
	     assign mask_port = 1'b1;
	   else
	     assign mask_port = 1'b0;
	   
	   assign rtl_next_port[op] = port_sel & ~mask_port;
	   assign rtl_error_unmasked_op[op] = port_sel & mask_port;
	   
	end
      
      genvar 	otc;
      
      for(otc = 0; otc < num_traffic_classes; otc = otc + 1)
	begin:otcs
	   
	   genvar 	orc;
	   
	   for(orc = 0; orc < num_routing_classes; orc = orc + 1)
	     begin:orcs
		
		if((otc == traffic_class) && (orc == routing_class))
		  assign rtl_next_class[otc*num_routing_classes+orc]
			   = ~rtl_change_class;
		else if((otc == traffic_class) && (orc == (routing_class + 1)))
		  assign rtl_next_class[otc*num_routing_classes+orc]
			   = rtl_change_class;
		else
		  assign rtl_next_class[otc*num_routing_classes+orc]
			   = 1'b0;
		
	     end
	   
	end
      
   endgenerate
   
   wire [0:num_vcs-1] rtl_next_vcs;
   replicator
     #(.width(num_classes),
       .count(num_vcs_per_class))
   rtl_next_vcs_repl
     (.data_in(rtl_next_class),
      .data_out(rtl_next_vcs));
   
   wire 	      rtl_error_unmasked;
   assign rtl_error_unmasked = |rtl_error_unmasked_op;
   
   wire 	      rtl_error;
   assign rtl_error = rtl_error_unmasked & get_next_header & next_valid;
   
   wire 	      change_class_s, change_class_q;
   assign change_class_s = get_next_header ? rtl_change_class : change_class_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   change_classq
     (.clk(clk),
      .reset(reset),
      .d(change_class_s),
      .q(change_class_q));
   
   wire [0:vc_route_info_width-1] next_vc_route_info;
   assign next_vc_route_info
     = next_vc_header_info[la_route_info_width:
			   la_route_info_width+vc_route_info_width-1];
   
   wire [0:vc_route_info_width-1] vc_route_info_s, vc_route_info_q;
   assign vc_route_info_s
     = get_next_header ? next_vc_route_info : vc_route_info_q;
   dff
     #(.width(vc_route_info_width),
       .reset_type(reset_type))
   vc_route_infoq
     (.clk(clk),
      .reset(reset),
      .d(vc_route_info_s),
      .q(vc_route_info_q));
   
   wire [0:num_ports-1] 	  port_q;
   
   la_routing_logic
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .routing_function_type(routing_function_type),
       .port_id(port_id),
       .traffic_class(traffic_class),
       .routing_class(routing_class))
   lar
     (.router_address(router_address),
      .route_port(port_q),
      .route_class(change_class_q),
      .vc_route_info(vc_route_info_q),
      .la_route_info(la_route_info_out));
   
   
   //---------------------------------------------------------------------------
   // currently active header
   //---------------------------------------------------------------------------
   
   wire 			  valid_s;
   assign valid_s = get_next_header ? next_valid : valid_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   validq
     (.clk(clk),
      .reset(reset),
      .d(valid_s),
      .q(valid_q));
   
   wire [0:num_ports-1] 	  port_s;
   assign port_s = get_next_header ? rtl_next_port : port_q;
   dff
     #(.width(num_ports),
       .reset_type(reset_type))
   portq
     (.clk(clk),
      .reset(reset),
      .d(port_s),
      .q(port_q));
   
   wire [0:num_vcs-1] 		  vcs_q;
   
   wire [0:num_vcs-1] 		  vcs_updated;
   assign vcs_updated = vc_gnt ? vc_gnt_ovc : vcs_q;
   
   wire [0:num_vcs-1] 		  vcs_s;
   assign vcs_s = get_next_header ? rtl_next_vcs : vcs_updated;
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vcsq
     (.clk(clk),
      .reset(reset),
      .d(vcs_s),
      .q(vcs_q));
   
   
   //---------------------------------------------------------------------------
   // credit tracking
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*int_flow_ctrl_width-1] flow_ctrl_ovc;
   select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs*int_flow_ctrl_width))
   flow_ctrl_ovc_sel
     (.select(port_q),
      .data_in(flow_ctrl_op_ovc),
      .data_out(flow_ctrl_ovc));
   
   wire 				  free_allocated;
   wire 				  cred_tracker_error;
   
   generate
      
      case(credit_handling_type)
	
	`CREDIT_HANDLING_TYPE_LEVEL:
	  begin
	     
	     wire [0:num_vcs-1] free_ovc;
	     assign free_ovc = flow_ctrl_ovc;
	     
	     wire 		flit_sent_prev_s, flit_sent_prev_q;
	     assign flit_sent_prev_s = flit_valid_out & ~get_next_header;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_sent_prevq
	       (.clk(clk),
		.reset(reset),
		.d(flit_sent_prev_s),
		.q(flit_sent_prev_q));
	     
	     wire [0:2] 	flit_sent_count;
	     assign flit_sent_count = {flit_sent_prev_q & flit_valid_out,
				       flit_sent_prev_q ^ flit_valid_out,
				       ~(flit_sent_prev_q | flit_valid_out)};
	     
	     wire [0:num_vcs-1] next_free_ovc;
	     
	     genvar 		ovc;
	     
	     for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	       begin:ovcs
		  
		  wire [0:1] free;
		  assign free = free_ovc[ovc*2:(ovc+1)*2-1];
		  
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
		  
		  assign next_free_ovc[ovc] = next_free;
		  
	       end
	     
	     wire 	     free_allocated_s, free_allocated_q;
	     assign free_allocated_s = |(next_free_ovc & vcs_updated);
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
	     
	     wire [0:num_vcs-1] 	       cred_ovc;
	     assign cred_ovc = flow_ctrl_ovc;
	     
	     wire 			       cred;
	     assign cred = |(cred_ovc & vcs_updated);
	     
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
		 allocated_q ?
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
	       = allocated_q && (cred_hold_q == num_flit_buffers-1) &&
		 incr_cred_hold;
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate allocator control signals
   //---------------------------------------------------------------------------
   
   wire 				       fbc_empty;
   
   assign sw_req_nonspec_op
     = port_q &
       {num_ports{valid_q & ~fbc_empty & allocated_q & free_allocated}};
   
   generate
      
      if(sw_spec_enable)
	assign sw_req_spec_op
	  = port_q & {num_ports{valid_q & ~fbc_empty & ~allocated_q}};
      else
	assign sw_req_spec_op = {num_ports{1'b0}};
      
   endgenerate
   
   assign vc_req_op = port_q;
   
   wire [0:num_vcs-1] 	       vc_req_ovc_s, vc_req_ovc_q;
   assign vc_req_ovc_s = vcs_s & {num_vcs{valid_s & ~allocated_s}};
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vc_req_ovcq
     (.clk(clk),
      .reset(reset),
      .d(vc_req_ovc_s),
      .q(vc_req_ovc_q));
   
   assign vc_req_ovc = vc_req_ovc_q;
   
   
   //---------------------------------------------------------------------------
   // generate target output VC to send along with flit data
   // (valid when flit_valid_out=1)
   //---------------------------------------------------------------------------
   
   // NOTE: don't need to use vc_gnt_ovc here, as flit_valid would not be
   // generated in the first place if grant was masked, so we don't care about
   // flit_vc_dec in this case!
   wire [0:num_vcs-1] 	       flit_vc_dec;
   assign flit_vc_dec = allocated_q ? vcs_q : vc_gnt_ovc;
   encoder
     #(.num_ports(num_vcs))
   vc_out_enc
     (.data_in(flit_vc_dec),
      .data_out(flit_vc_out));
   
   
   //---------------------------------------------------------------------------
   // flit buffer control
   //---------------------------------------------------------------------------
   
   wire 		       fbc_push;
   assign fbc_push = flit_valid_in;
   
   wire 		       fbc_pop;
   assign fbc_pop = all_allocated & ~fbc_empty;
   
   wire 		       fbc_error;
   wire 		       fbc_empty_early;
   wire 		       fbc_full;
   wire 		       fbc_full_early;
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
      .empty_early(fbc_empty_early),
      .full(fbc_full),
      .full_early(fbc_full_early),
      .error(fbc_error));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   wire [0:3] 		       errors_in;
   assign errors_in = {~hdff_empty & ~valid_q,
                       ~fbc_empty & ~valid_q,
		       cred_tracker_error,
		       rtl_error};
   
   wire [0:3] 		       errors_out;
   checker
     #(.num_errors(4),
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
   
   wire 		       ev_no_flit;
   assign ev_no_flit = valid_q & fbc_empty;
   
   wire 		       ev_flit_stalled_vc;
   assign ev_flit_stalled_vc = valid_q & ~fbc_empty & ~vc_allocated;
   
   wire 		       ev_flit_stalled_sw;
   assign ev_flit_stalled_sw = valid_q & ~fbc_empty & vc_allocated &
			       ~sw_allocated;
   
   wire 		       ev_spec_failed;
   assign ev_spec_failed = valid_q & ~fbc_empty & ~vc_allocated & sw_allocated;
   
   wire 		       ev_flit_sent;
   assign ev_flit_sent = valid_q & ~fbc_empty & all_allocated;
   
   wire 		       ev_flit_sent_spec;
   assign ev_flit_sent_spec = valid_q & ~fbc_empty & vc_gnt &
			      ~allocated_q & sw_allocated;
   
   generate
      
      if(perf_ctr_enable > 0)
	begin
	   wire [0:5] 	       events_s, events_q;
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
