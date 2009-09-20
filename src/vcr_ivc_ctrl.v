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



// input VC controller
module vcr_ivc_ctrl
  (clk, reset, router_address, flit_ctrl_in, header_info_in, 
   int_flow_ctrl_op_ovc, route_port, inc_rc, vc_req, vc_gnt, vc_gnt_ovc, 
   sw_req_nonspec, sw_req_spec, sw_gnt_nonspec, sw_gnt_spec, int_flit_ctrl_out, 
   la_route_info_out, fbf_write_addr, fbf_read_addr, error, events);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width of credit hold register
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_PUSH)
   localparam cred_hold_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs available for each class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
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

   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // select implementation variant for VC allocator
   parameter vc_alloc_type = `VC_ALLOC_TYPE_SEP_IF;
   
   // select speculation type for switch allocator
   parameter sw_alloc_spec_type = `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   // message class to which this VC belongs
   localparam message_class
     = (vc_id / (num_resource_classes*num_vcs_per_class)) % num_message_classes;
   
   // resource class to which this VC belongs
   localparam resource_class
     = (vc_id / num_vcs_per_class) % num_resource_classes;
   
   // packet class to which this VC belongs
   localparam packet_class = (vc_id / num_vcs_per_class) % num_packet_classes;
   
   // width of routing information required for each VC
   localparam hop_route_info_width
     = (resource_class == (num_resource_classes - 1)) ?
       addr_width :
       (resource_class == (num_resource_classes - 2)) ?
       (router_addr_width + addr_width) :
       (2 * router_addr_width);
   
   // total number of bits of header information required for each VC
   localparam hdff_width = la_route_info_width + hop_route_info_width;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(num_vcs*num_flit_buffers);
   
   // index of leftmost entry in shared flit buffer
   localparam fbf_min_addr = vc_id * num_flit_buffers;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // header information associated with current flit
   input [0:header_info_width-1] header_info_in;
   
   // internal flow control signalling from output controller to input 
   // controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   // destination port
   output [0:port_idx_width-1] route_port;
   wire [0:port_idx_width-1] route_port;
   
   // transition to next resource class
   output inc_rc;
   wire 		inc_rc;
   
   // request VC allocation
   output vc_req;
   wire vc_req;
   
   // VC allocation successful
   input vc_gnt;
   
   // granted output VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // non-speculative switch allocator requests
   output sw_req_nonspec;
   wire 		sw_req_nonspec;
   
   // speculative switch allocator requests
   output sw_req_spec;
   wire 		sw_req_spec;
   
   // non-speculative switch allocator grants
   input sw_gnt_nonspec;
   
   // speculative switch allocator grants
   input sw_gnt_spec;
   
   // outgoing flit control signals
   output [0:int_flit_ctrl_width-1] int_flit_ctrl_out;
   wire [0:int_flit_ctrl_width-1] int_flit_ctrl_out;
   
   // lookahead routing information for outgoing flit
   output [0:la_route_info_width-1] la_route_info_out;
   wire [0:la_route_info_width-1] la_route_info_out;
   
   // write pointer for shared flit buffer
   output [0:fbf_addr_width-1] fbf_write_addr;
   wire [0:fbf_addr_width-1] 	  fbf_write_addr;
   
   // read pointer for shared flit buffer
   output [0:fbf_addr_width-1] fbf_read_addr;
   wire [0:fbf_addr_width-1] 	  fbf_read_addr;
   
   // internal error condition detected
   output error;
   wire 			  error;
   
   // performance counter events
   // (note: only valid if perf_ctr_enable=1)
   output [0:5] events;
   wire [0:5] 			  events;
   
   
   //---------------------------------------------------------------------------
   // decode control signals
   //---------------------------------------------------------------------------
   
   wire 			  flit_valid_in;
   wire 			   flit_head_in;   
   wire 			   flit_tail_in;
   
   generate

      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] flit_vc_in;
		  assign flit_vc_in = flit_ctrl_in[1:1+vc_idx_width-1];
		  
		  assign flit_valid_in
		    = flit_ctrl_in[0] && (flit_vc_in == vc_id);
		  
	       end
	     else
		  assign flit_valid_in = flit_ctrl_in[0];
	     
	     assign flit_head_in = flit_ctrl_in[1+vc_idx_width+0];
	     
	  end
	
	endcase
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     assign flit_tail_in = flit_ctrl_in[1+vc_idx_width+1];
	  end
	
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     if(max_payload_length == 0)
	       begin
		  
		  if(max_payload_length == min_payload_length)
		    assign flit_tail_in = flit_head_in;
		  
		  // synopsys translate_off
		  else
		    begin
		       initial
		       begin
			  $display("ERROR: The value of the max_payload_length \
                                    parameter cannot be smaller than that of \
                                    the min_payload_length parameter.");
			  $stop;
		       end
		    end
		  // synopsys translate_on
		  
	       end
	     else if(max_payload_length == 1)
	       begin
		  
		  wire has_payload;
		  
		  if(max_payload_length > min_payload_length)
		    assign has_payload
		      = header_info_in[la_route_info_width+route_info_width];
		  else if(max_payload_length == min_payload_length)
		    assign has_payload = 1'b1;
		  
		  // synopsys translate_off
		  else
		    begin
		       initial
		       begin
			  $display("ERROR: The value of the max_payload_length \
                                    parameter cannot be smaller than that of \
                                    the min_payload_length parameter.");
			  $stop;
		       end
		    end
		  // synopsys translate_on
		  
		  assign flit_tail_in = ~flit_head_in | ~has_payload;
		  
	       end
	     else
	       begin
		  
		  wire [0:flit_ctr_width-1] flit_ctr_q;
		  wire [0:flit_ctr_width-1] flit_ctr_next;
		  
		  if(max_payload_length > min_payload_length)
		    begin
		       
		       wire [0:payload_length_width-1] payload_length;
		       assign payload_length
			 = header_info_in[la_route_info_width+
					  route_info_width:
					  la_route_info_width+
					  route_info_width+
					  payload_length_width-1];
		       
		       assign flit_ctr_next
			 = (min_payload_length - 1) + payload_length;
		       
		       if(min_payload_length == 0)
			 assign flit_tail_in
			   = flit_head_in ? ~|payload_length : ~|flit_ctr_q;
		       else
			 assign flit_tail_in = ~flit_head_in & ~|flit_ctr_q;
		       
		    end
		  else if(max_payload_length == min_payload_length)
		    begin
		       assign flit_ctr_next = max_payload_length - 1;
		       assign flit_tail_in = ~flit_head_in & ~|flit_ctr_q;
		    end
		  
		  // synopsys translate_off
		  else
		    begin
		       initial
		       begin
			  $display("ERROR: The value of the max_payload_length \
                                    parameter cannot be smaller than that of \
                                    the min_payload_length parameter.");
			  $stop;
		       end
		    end
		  // synopsys translate_on
		  
		  wire [0:flit_ctr_width-1] flit_ctr_s;
		  assign flit_ctr_s = flit_valid_in ? 
				      flit_head_in ? 
				      flit_ctr_next : 
				      (flit_ctr_q - 1'b1) : 
				      flit_ctr_q;
		  c_dff
		    #(.width(flit_ctr_width),
		      .reset_type(reset_type))
		  flit_ctrq
		    (.clk(clk),
		     .reset(reset),
		     .d(flit_ctr_s),
		     .q(flit_ctr_q));
		  
	       end
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   
   wire 				    flit_valid_out;
   wire 				    flit_tail_out;
   
   wire 				    packet_done;
   assign packet_done = flit_valid_out & flit_tail_out;
   
   wire 				    vc_allocated_s, vc_allocated_q;
   assign vc_allocated_s = (vc_allocated_q | vc_gnt) & ~packet_done;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocatedq
     (.clk(clk),
      .reset(reset),
      .d(vc_allocated_s),
      .q(vc_allocated_q));
   
   wire [0:num_vcs_per_class-1] 	    vc_gnt_unchanged_ocvc;
   assign vc_gnt_unchanged_ocvc
     = vc_gnt_ovc[packet_class*num_vcs_per_class:
		  (packet_class+1)*num_vcs_per_class-1];
   
   wire [0:num_vcs_per_class-1] 	    vc_gnt_ocvc;
   
   generate
      
      if(resource_class == (num_resource_classes - 1))
	assign vc_gnt_ocvc = vc_gnt_unchanged_ocvc;
      else
	begin
	   
	   wire [0:num_vcs_per_class-1] vc_gnt_changed_ocvc;
	   assign vc_gnt_changed_ocvc
	     = vc_gnt_ovc[(packet_class+1)*num_vcs_per_class:
			  (packet_class+2)*num_vcs_per_class-1];
	   
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
   c_dff
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
      
      if((vc_alloc_type != `VC_ALLOC_TYPE_PIGGYBACK) && 
	 (sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE))
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
   
   wire flit_head_out;
   
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
	   c_select_1ofn
	     #(.num_ports(num_flit_buffers),
	       .width(1))
	   head_queue_muxed_sel
	     (.select(read_sel),
	      .data_in(head_queue),
	      .data_out(head_queue_muxed));
	   
	   assign flit_head_out = fbc_empty ? flit_head_in : head_queue_muxed;
	   
	   wire tail_queue_muxed;
	   c_select_1ofn
	     #(.num_ports(num_flit_buffers),
	       .width(1))
	   tail_queue_muxed_sel
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
	   c_dff
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
	   c_dff
	     #(.width(fbf_addr_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   tail_idxq
	     (.clk(clk),
	      .reset(reset),
	      .d(tail_idx_s),
	      .q(tail_idx_q));
	   
	   wire 		     tail_valid_s, tail_valid_q;
	   assign tail_valid_s
	     = (tail_valid_q | tail_in) & ~(flit_valid_out & flit_tail_out);
	   c_dff
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
   
   wire [0:hop_route_info_width-1] hop_route_info_in;
   
   wire 			   hdff_empty;
   wire 			   hdff_error;
   
   wire 			   hdff_push;
   assign hdff_push = flit_valid_in & flit_head_in;
   
   wire 			   hdff_pop;
   assign hdff_pop = flit_valid_out & flit_tail_out;
   
   wire [0:la_route_info_width-1]  hdff_la_route_info;
   wire [0:hop_route_info_width-1] hdff_hop_route_info;
   
   generate
      
      if((resource_class == (num_resource_classes - 1)) ||
	 (resource_class == (num_resource_classes - 2)))
	assign hop_route_info_in
	  = route_info_in[route_info_width-hop_route_info_width:
			  route_info_width-1];
      else
	assign hop_route_info_in
	  = route_info_in[resource_class*router_addr_width:
			  (resource_class+2)*router_addr_width-1];
      
      if(num_header_buffers > 1)
	begin
	   
	   wire [0:hdff_width-1] 	  hdff_data_in;
	   assign hdff_data_in[0:la_route_info_width-1] = la_route_info_in;
	   assign hdff_data_in[la_route_info_width:
			       la_route_info_width+hop_route_info_width-1]
		    = hop_route_info_in;
	   
	   wire hdff_full;
	   wire [0:hdff_width-1] hdff_data_out;
	   
	   c_fifo
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
	   assign hdff_hop_route_info
	     = hdff_empty ?
	       hop_route_info_in :
	       hdff_data_out[la_route_info_width:
			     la_route_info_width+hop_route_info_width-1];
   
	end
      else
	begin
	   
	   wire [0:la_route_info_width-1] hdff_la_route_info_s,
					  hdff_la_route_info_q;
	   assign hdff_la_route_info_s
	     = hdff_push ? la_route_info_in : hdff_la_route_info_q;
	   c_dff
	     #(.width(la_route_info_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_ASYNC))
	   hdff_la_route_infoq
	     (.clk(clk),
	      .reset(reset),
	      .d(hdff_la_route_info_s),
	      .q(hdff_la_route_info_q));
	   
	   assign hdff_la_route_info
	     = hdff_empty ? la_route_info_in : hdff_la_route_info_q;
	   
	   wire [0:hop_route_info_width-1] hdff_hop_route_info_s,
					   hdff_hop_route_info_q;
	   assign hdff_hop_route_info_s
	     = hdff_push ? hop_route_info_in : hdff_hop_route_info_q;
	   c_dff
	     #(.width(hop_route_info_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_ASYNC))
	   hdff_hop_route_infoq
	     (.clk(clk),
	      .reset(reset),
	      .d(hdff_hop_route_info_s),
	      .q(hdff_hop_route_info_q));
	   
	   assign hdff_hop_route_info
	     = hdff_empty ? hop_route_info_in : hdff_hop_route_info_q;
	   
	   wire hdff_empty_s, hdff_empty_q;
	   assign hdff_empty_s = (hdff_empty_q | (hdff_pop & ~hdff_push)) &
				 ~(hdff_push & ~hdff_pop);
	   c_dff
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
   
   assign route_port = hdff_la_route_info[0:port_idx_width-1];
   
   generate
      
      if(resource_class < (num_resource_classes - 1))
	assign inc_rc = hdff_la_route_info[port_idx_width];
      else
	assign inc_rc = 1'b0;
      
   endgenerate
   
   vcr_la_routing_logic
     #(.num_resource_classes(num_resource_classes),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .resource_class(resource_class),
       .reset_type(reset_type))
   lar
     (.clk(clk),
      .reset(reset),
      .router_address(router_address),
      .route_port(route_port),
      .inc_rc(inc_rc),
      .hop_route_info(hdff_hop_route_info),
      .la_route_info(la_route_info_out));
   
   
   //---------------------------------------------------------------------------
   // credit tracking
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
   assign int_flow_ctrl_ovc
     = int_flow_ctrl_op_ovc[route_port*num_vcs*int_flow_ctrl_width +:
			    num_vcs*int_flow_ctrl_width];
   
   wire 				  free_allocated;
   wire 				  cred_tracker_error;
   
   generate
      
      case(credit_handling_type)
	
	// the current number of credits available are transmitted from the 
	// output controllers as a multi-level signal (0, 1, 2 or 3+ credits
	// currently available)
	`CREDIT_HANDLING_TYPE_LEVEL:
	  begin
	     
	     // credit status for the case where we do not change resource class
	     wire [0:num_vcs_per_class*2-1] free_unchanged_ocvc;
	     assign free_unchanged_ocvc
	       = int_flow_ctrl_ovc[packet_class*num_vcs_per_class*2:
				   (packet_class+1)*num_vcs_per_class*2-1];
	     
	     wire [0:num_vcs_per_class*2-1] free_ocvc;
	     
	     if(resource_class == (num_resource_classes - 1))
	       assign free_ocvc = free_unchanged_ocvc;
	     else
	       begin
		  
		  // credit status in case we change resource class
		  wire [0:num_vcs_per_class*2-1] free_changed_ocvc;
		  assign free_changed_ocvc
		    = int_flow_ctrl_ovc[(packet_class+1)*num_vcs_per_class*2:
					(packet_class+2)*num_vcs_per_class*2-1];
		  
		  assign free_ocvc
		    = inc_rc ? free_changed_ocvc : free_unchanged_ocvc;
		  
	       end
	     
	     wire 				 flit_sent_prev_s,
						 flit_sent_prev_q;
	     assign flit_sent_prev_s = flit_valid_out & ~flit_tail_out;
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_sent_prevq
	       (.clk(clk),
		.reset(reset),
		.d(flit_sent_prev_s),
		.q(flit_sent_prev_q));
	     
	     wire [0:1] 			 flit_sent_count;
	     assign flit_sent_count = flit_sent_prev_q + flit_valid_out;
	     
	     wire [0:num_vcs_per_class-1] 	 next_free_ocvc;
	     
	     genvar 				 ocvc;
	     
	     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
	       begin:ocvcs
		  
		  wire [0:1] free;
		  assign free = free_ocvc[ocvc*2:(ocvc+1)*2-1];
		  
		  wire [0:2] free_by_count;
		  assign free_by_count = {|free, free[0], &free};
		  
		  wire       next_free;
		  assign next_free = free_by_count[flit_sent_count];
		  
		  assign next_free_ocvc[ocvc] = next_free;
		  
	       end
	     
	     wire 	     free_allocated_s, free_allocated_q;
	     assign free_allocated_s
	       = |(next_free_ocvc & vc_allocated_hold_ocvc)/* & ~packet_done*/;
	     c_dff
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
	
	// credits are forwarded from the output controllers individually as 
	// pulses, accumulated at the input controllers, and used whenever a
	// flit is sent to the crossbar
	`CREDIT_HANDLING_TYPE_PUSH:
	  begin
	     
	     // credit indicator for the case where we do not change the 
	     // resource class
	     wire [0:num_vcs_per_class-1] cred_unchanged_ocvc;
	     assign cred_unchanged_ocvc
	       = int_flow_ctrl_ovc[packet_class*num_vcs_per_class:
				   (packet_class+1)*num_vcs_per_class-1];
	     
	     wire [0:num_vcs_per_class-1] cred_ocvc;
	     
	     if(resource_class == (num_resource_classes - 1))
	       assign cred_ocvc = cred_unchanged_ocvc;
	     else
	       begin
		  
		  // credit status for the case where the resource class changes
		  wire [0:num_vcs_per_class-1] cred_changed_ocvc;
		  assign cred_changed_ocvc
		    = int_flow_ctrl_ovc[(packet_class+1)*num_vcs_per_class:
					(packet_class+2)*num_vcs_per_class-1];
		  
		  assign cred_ocvc = inc_rc ?
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
		  ((has_cred_q & ~sw_gnt_nonspec) | (|cred_hold_q))) | 
		 cred;
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type))
	     has_credq
	       (.clk(clk),
		.reset(reset),
		.d(has_cred_s),
		.q(has_cred_q));
	     
	     assign free_allocated = has_cred_q;
	     
	     wire 			       incr_cred_hold;
	     assign incr_cred_hold = cred & ~sw_gnt_nonspec & has_cred_q;
	     
	     wire 			       decr_cred_hold;
	     assign decr_cred_hold = ~cred & sw_gnt_nonspec & |cred_hold_q;
	     
	     wire [0:cred_hold_width-1]        cred_hold_new;
	     assign cred_hold_new = cred & ~sw_gnt_spec;
	     
	     wire [0:cred_hold_width-1]        cred_hold_s;
	     assign cred_hold_s
	       = vc_gnt ?
		 cred_hold_new :
		 vc_allocated_q ?
		 (cred_hold_q + incr_cred_hold - decr_cred_hold) :
		 cred_hold_q;
	     c_dff
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
   
   generate
      
      if(vc_alloc_type == `VC_ALLOC_TYPE_PIGGYBACK)
	assign sw_req_nonspec
	  = header_valid & flit_valid & (free_allocated | ~vc_allocated_q);
      else
	assign sw_req_nonspec
	  = header_valid & flit_valid & vc_allocated_q & free_allocated;
      
      if((vc_alloc_type != `VC_ALLOC_TYPE_PIGGYBACK) && 
	 (sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE))
	assign sw_req_spec = header_valid & flit_valid & ~vc_allocated_q;
      else
	assign sw_req_spec = 1'b0;
      
   endgenerate
   
   assign vc_req = header_valid & ~vc_allocated_q;
   
   
   //---------------------------------------------------------------------------
   // encode output control signals
   //---------------------------------------------------------------------------
   
   assign int_flit_ctrl_out[0] = flit_valid_out;
   assign int_flit_ctrl_out[1+vc_idx_width+0] = flit_head_out;
   assign int_flit_ctrl_out[1+vc_idx_width+1] = flit_tail_out;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc_out;
	   
	   if(track_vcs_at_output)
	     assign flit_vc_out = vc_id;
	   else
	     begin
		
		wire [0:num_vcs_per_class-1] flit_ocvc;
		
		if((vc_alloc_type == `VC_ALLOC_TYPE_PIGGYBACK) || 
		   (sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE))
		  assign flit_ocvc = vc_allocated_hold_ocvc;
		else
		  assign flit_ocvc = vc_allocated_ocvc_q;
		
		wire [0:num_vcs-1] 	     flit_ovc;
		
		if(resource_class == (num_resource_classes - 1))
		  begin
		     
		     c_align
		       #(.data_width(num_vcs_per_class),
			 .dest_width(num_vcs),
			 .offset(packet_class*num_vcs_per_class))
		     flit_ovc_alg
		       (.data_in(flit_ocvc),
			.dest_in({num_vcs{1'b0}}),
			.data_out(flit_ovc));
		     
		  end
		else
		  begin
		     
		     c_align
		       #(.data_width(2*num_vcs_per_class),
			 .dest_width(num_vcs),
			 .offset(packet_class*num_vcs_per_class))
		     flit_ovc_alg
		       (.data_in({flit_ocvc & {num_vcs_per_class{~inc_rc}},
				  flit_ocvc & {num_vcs_per_class{inc_rc}}}),
			.dest_in({num_vcs{1'b0}}),
			.data_out(flit_ovc));
		     
		  end
		
		c_encoder
		  #(.num_ports(num_vcs))
		flit_vc_out_enc
		  (.data_in(flit_ovc),
		   .data_out(flit_vc_out));
		
	     end
	   
	   assign int_flit_ctrl_out[1:1+vc_idx_width-1] = flit_vc_out;
	   
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
   c_fifo_ctrl
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
   
   wire [0:1] 		       errors_in;
   assign errors_in = {flit_valid & ~header_valid, cred_tracker_error};
   
   wire [0:1] 		       errors_out;
   c_checker
     #(.num_errors(2),
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
	   c_dff
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
