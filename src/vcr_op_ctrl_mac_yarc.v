// $Id: vcr_op_ctrl_mac.v 1228 2009-05-01 20:35:02Z qtedq $

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

// output port controller (tracks state of buffers in downstream router)
module vcr_op_ctrl_mac_yarc
  (clk, reset, flow_ctrl_in, vc_gnt_ovc, vc_gnt_ovc_ip, vc_gnt_ovc_ivc, 
   xbr_ctrl_ip, int_flit_ctrl_in, flit_data_in, flit_ctrl_out, flit_data_out, 
   elig_ovc, int_flow_ctrl_ovc, error);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
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
   
   // width required to select a buffer
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   // width of counter for credits waiting to be sent to input controller
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
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = num_ports + ((num_routing_classes > 1) ? 1 : 0);
   
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
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // number of bits to be used for credit level reporting
   // (note: must be less than or equal to cred_count_width as given below)
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_LEVEL)
   parameter cred_level_width = 2;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width
     = 1 + vc_idx_width + 1 + 1;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (credit_handling_type == `CREDIT_HANDLING_TYPE_LEVEL) ?
       cred_level_width :
       (credit_handling_type == `CREDIT_HANDLING_TYPE_PUSH) ?
       1 :
       -1;
   
   // maximum value for credit level
   localparam [0:cred_level_width-1] max_cred_level = {cred_level_width{1'b1}};
   
   // capped reset value for credit level
   localparam [0:cred_level_width-1] free_reset_value
     = (num_flit_buffers > max_cred_level) ? max_cred_level : num_flit_buffers;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;

   // incoming flow control signals
   input [0:8*flow_ctrl_width-1] flow_ctrl_in;
   
   // output VC was granted to an input VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // input port that each output VC was granted to
   input [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
   
   // input VC that each output VC was granted to
   input [0:num_vcs*num_vcs-1] vc_gnt_ovc_ivc;

   // port to which this output is currently connected
   input [0:num_ports-1] xbr_ctrl_ip;
   
   // incoming flit control signals
   input [0:int_flit_ctrl_width-1] int_flit_ctrl_in;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs-1] elig_ovc;
   
   // internal flow control signalling from output controller to input 
   // controllers
   output [0:8*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
   wire [0:8*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
   
   // internal error condition detected
   output error;
   wire 				  error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire [0:flow_ctrl_width-1] 		  flow_ctrl_s, flow_ctrl_q;
   assign flow_ctrl_s = flow_ctrl_in;
   
   wire 				  cred_valid_s, cred_valid_q;
   assign cred_valid_s = flow_ctrl_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign flow_ctrl_q[0] = cred_valid_q;

   generate
      
      if(flow_ctrl_width > 1)
	begin
	   
	   c_dff
	     #(.width(flow_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flow_ctrlq
	     (.clk(clk),
	      .reset(reset),
	      .d(flow_ctrl_s[1:flow_ctrl_width-1]),
	      .q(flow_ctrl_q[1:flow_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output VC control logic
   //---------------------------------------------------------------------------
   
   wire 				  xbr_ctrl;
   assign xbr_ctrl = |xbr_ctrl_ip;
   
   wire 				  flit_valid_in;
   assign flit_valid_in = int_flit_ctrl_in[0] & xbr_ctrl;
   
   wire 				  flit_tail_in;
   assign flit_tail_in = int_flit_ctrl_in[1+vc_idx_width+1];
   
   wire 				  cred_valid;
   assign cred_valid = flow_ctrl_q[0];
   
   wire [0:num_vcs-1] 			  match_ovc;
   
   wire 				  error_unmatched;
   assign error_unmatched = flit_valid_in & ~|match_ovc;
   
   wire [0:num_vcs-1] 			  next_cred_ovc;
   wire [0:num_vcs-1] 			  error_hct_ovc;
   wire [0:num_vcs*2-1] 		  error_cred_ovc;
   
   generate
      
      genvar 				  ovc;
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   
	   if(num_vcs > 1)
	     begin
		
		wire [0:vc_idx_width-1] cred_vc;
		assign cred_vc = flow_ctrl_q[1:1+vc_idx_width-1];
		
		assign credit = cred_valid && (cred_vc == ovc);
		
	     end
	   else
	     assign credit = cred_valid;
	   
	   wire 			debit;
	   assign debit = flit_valid_in & match_ovc[ovc];
	   
	   wire 			vc_gnt;
	   assign vc_gnt = vc_gnt_ovc[ovc];
	   
	   
	   //-------------------------------------------------------------------
	   // track whether this output VC is currently assigend to an input VC
	   //-------------------------------------------------------------------
	   
	   wire set_allocated;
	   assign set_allocated = vc_gnt;
	   
	   wire reset_allocated;   
	   assign reset_allocated = debit & flit_tail_in;
	   
	   wire allocated_s, allocated_q;
	   assign allocated_s
	     = set_allocated | (allocated_q & ~reset_allocated);
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   allocatedq
	     (.clk(clk),
	      .reset(reset),
	      .d(allocated_s),
	      .q(allocated_q));
	   
	   if(num_vcs > 1)
	     begin
		
		wire [0:vc_idx_width-1] flit_vc_in;
		assign flit_vc_in = int_flit_ctrl_in[1:1+vc_idx_width-1];
		
		// if VC assignment is tracked at the output, each output VC 
		// needs to check if it is currently assigned to the incoming VC
		// ID at the selected input port
		if(track_vcs_at_output)
		  begin
		     
		     wire [0:num_ports-1] vc_gnt_ip;
		     assign vc_gnt_ip
		       = vc_gnt_ovc_ip[ovc*num_ports:(ovc+1)*num_ports-1];
		     
		     wire [0:num_ports-1] allocated_ip_s, allocated_ip_q;
		     assign allocated_ip_s
		       = vc_gnt ? vc_gnt_ip : allocated_ip_q;
		     c_dff
		       #(.width(num_ports),
			 .reset_type(reset_type))
		     allocated_ipq
		       (.clk(clk),
			.reset(reset),
			.d(allocated_ip_s),
			.q(allocated_ip_q));
		     
		     wire [0:num_vcs-1]   vc_gnt_ivc;
		     assign vc_gnt_ivc
		       = vc_gnt_ovc_ivc[ovc*num_vcs:(ovc+1)*num_vcs-1];
		     
		     wire [0:num_vcs-1]   allocated_ivc_s, allocated_ivc_q;
		     assign allocated_ivc_s
		       = vc_gnt ? vc_gnt_ivc : allocated_ivc_q;
		     c_dff
		       #(.width(num_vcs),
			 .reset_type(reset_type))
		     allocated_ivcq
		       (.clk(clk),
			.reset(reset),
			.d(allocated_ivc_s),
			.q(allocated_ivc_q));
		     
		     assign match_ovc[ovc] = allocated_q &&
					     |(allocated_ip_q & xbr_ctrl_ip) &&
					     allocated_ivc_q[flit_vc_in];
		     
		  end
		
		// if VC assignments are tracked at the input side, we can just 
		// check if for our own VC ID
		else
		  assign match_ovc[ovc] = (flit_vc_in == ovc);
		
	     end
	   
	   // if we only have a single VC to begin with, it is always selected
	   else
	     assign match_ovc[ovc] = 1'b1;
	   
	   
	   //-------------------------------------------------------------------
	   // track number of packets that downstream buffer can still accept
	   //-------------------------------------------------------------------
	   
	   wire [0:cred_count_width-1] cred_count_s;
	   wire 		       head_free_early;
	   
	   if(num_header_buffers == num_flit_buffers)
	     begin
		
		// if every flit buffer entry can be a head flit, we don't need 
		// dedicated credit tracking for headers, and can instead just
		// rely on the normal credit tracking mechanism
		assign head_free_early = 1'b1;
		
		assign error_hct_ovc[ovc] = 1'b0;
		
	     end
	   else
	     begin

		// if only a subset of the flit buffer entries can be headers, 
		// we need to keep track of how many such slots are left
		
		if(num_header_buffers == 1)
		  begin
		     
		     // if we can only have one packet per buffer, we can accept
		     // the next one once the buffer has been completely drained
		     // after the tail has been sent
		     
		     wire buffer_drained;
		     assign buffer_drained = (cred_count_s == num_flit_buffers);
		     
		     wire tail_sent_s, tail_sent_q;
		     assign tail_sent_s
		       = (tail_sent_q | (debit & flit_tail_in)) &
			 ~buffer_drained;
		     c_dff
		       #(.width(1),
			 .reset_type(reset_type))
		     tail_sentq
		       (.clk(clk),
			.reset(reset),
			.d(tail_sent_s),
			.q(tail_sent_q));
		     
		     wire head_free_s, head_free_q;
		     assign head_free_s
		       = (head_free_q & ~vc_gnt) |
			 (credit & tail_sent_q & buffer_drained);
		     c_dff
		       #(.width(1),
			 .reset_type(reset_type),
			 .reset_value(1'b1))
		     head_freeq
		       (.clk(clk),
			.reset(reset),
			.d(head_free_s),
			.q(head_free_q));
		     
		     assign head_free_early = head_free_s;
		     
		     assign error_hct_ovc[ovc] = 1'b0;
		     
		  end
		else
		  begin
		     
		     wire [0:flit_buffer_idx_width-1] push_ptr_next, push_ptr_q;
		     c_incr
		       #(.width(flit_buffer_idx_width),
			 .min_value(0),
			 .max_value(num_flit_buffers-1))
		     push_ptr_incr
		       (.data_in(push_ptr_q),
			.data_out(push_ptr_next));
		     
		     wire [0:flit_buffer_idx_width-1] push_ptr_s;
		     assign push_ptr_s = debit ? push_ptr_next : push_ptr_q;
		     c_dff
		       #(.width(flit_buffer_idx_width),
			 .reset_type(reset_type))
		     push_ptrq
		       (.clk(clk),
			.reset(reset),
			.d(push_ptr_s),
			.q(push_ptr_q));
		     
		     wire [0:flit_buffer_idx_width-1] pop_ptr_next, pop_ptr_q;
		     c_incr
		       #(.width(flit_buffer_idx_width),
			 .min_value(0),
			 .max_value(num_flit_buffers-1))
		     pop_ptr_incr
		       (.data_in(pop_ptr_q),
			.data_out(pop_ptr_next));
		     
		     wire [0:flit_buffer_idx_width-1] pop_ptr_s;
		     assign pop_ptr_s = credit ? pop_ptr_next : pop_ptr_q;
		     c_dff
		       #(.width(flit_buffer_idx_width),
			 .reset_type(reset_type))
		     pop_ptrq
		       (.clk(clk),
			.reset(reset),
			.d(pop_ptr_s),
			.q(pop_ptr_q));
		     
		     reg [0:num_flit_buffers-1]       tail_queue;
		     
		     always @(posedge clk)
		       if(debit)
			 tail_queue[push_ptr_q] <= flit_tail_in;
		     
		     wire 			      tail;
		     assign tail = tail_queue[pop_ptr_q];
		     
		     wire 			      head_credit;
		     assign head_credit = tail & credit;
		     
		     wire 			      head_debit;
		     assign head_debit = vc_gnt;
		     
		     // track header credits using stock credit tracker module
		     wire 			      head_free;
		     wire 			      error_hct;
		     c_credit_tracker
		       #(.num_credits(num_header_buffers),
			 .checker_enable(checker_enable),
			 .checker_capture_mode(checker_capture_mode),
			 .reset_type(reset_type))
		     hct
		       (.clk(clk),
			.reset(reset),
			.credit(head_credit),
			.debit(head_debit),
			.free(head_free),
			.free_early(head_free_early),
			.error(error_hct));
		     
		     assign error_hct_ovc[ovc] = error_hct;
		     
		  end
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // track number of flits that downstream buffer can still accept
	   //-------------------------------------------------------------------
	   
	   wire [0:cred_count_width-1] cred_count_q;
	   assign cred_count_s = (cred_count_q + credit - debit);
	   c_dff
	     #(.width(cred_count_width),
	       .reset_type(reset_type),
	       .reset_value(num_flit_buffers))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   assign next_cred_ovc[ovc] = |cred_count_s;
	   
	   wire [0:1] 		       error_cred;
	   assign error_cred = {(cred_count_q == num_flit_buffers) && credit,
				(cred_count_q == 0) && debit};
	   
	   assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
	   
	   
	   //-------------------------------------------------------------------
	   // generate flow control signals to input controller
	   //-------------------------------------------------------------------
	   
	   case(credit_handling_type)
	     
	     `CREDIT_HANDLING_TYPE_LEVEL:
	       begin
		  
		  wire [0:cred_level_width-1] free_s, free_q;
		  assign free_s = (cred_count_s > max_cred_level) ?
				  max_cred_level :
				  cred_count_s[cred_count_width-
					       cred_level_width:
					       cred_count_width-1];
		  c_dff
		    #(.width(cred_level_width),
		      .reset_type(reset_type),
		      .reset_value(free_reset_value))
		  freeq
		    (.clk(clk),
		     .reset(reset),
		     .d(free_s),
		     .q(free_q));
		  
		  assign int_flow_ctrl_ovc[ovc*cred_level_width:
					   (ovc+1)*cred_level_width-1]
			   = free_q;
		  
	       end
	     
	     `CREDIT_HANDLING_TYPE_PUSH:
	       begin
		  
		  wire [0:cred_hold_width-1]  cred_hold_copy;
		  assign cred_hold_copy
		    = cred_count_s[(cred_count_width-cred_hold_width):
				   cred_count_width-1] - 1'b1;
		  
		  wire [0:cred_hold_width-1]  cred_hold_s, cred_hold_q;
		  assign cred_hold_s
		    = (vc_gnt | allocated_q) ?
		      (cred_hold_q - (|cred_hold_q & ~credit)) :
		      cred_hold_copy;
		  c_dff
		    #(.width(cred_hold_width),
		      .reset_type(reset_type),
		      .reset_value(num_flit_buffers-1))
		  cred_holdq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_hold_s),
		     .q(cred_hold_q));
		  
		  wire 			      cred_s, cred_q;
		  assign cred_s = |cred_hold_s | credit;
		  c_dff
		    #(.width(1),
		      .reset_type(reset_type),
		      .reset_value(1))
		  credq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_s),
		     .q(cred_q));
		  
		  assign int_flow_ctrl_ovc[ovc] = cred_q;
		  
	       end
	     
	   endcase
	   
	   
	   //-------------------------------------------------------------------
	   // keep track of whether current VC is available for allocation
	   //-------------------------------------------------------------------
	   
	   wire 			      elig_s, elig_q;
	   assign elig_s = ~allocated_s & head_free_early & next_cred_ovc[ovc];
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .reset_value(1'b1))
	   eligq
	     (.clk(clk),
	      .reset(reset),
	      .d(elig_s),
	      .q(elig_q));
	   
	   assign elig_ovc[ovc] = elig_q;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output staging
   //---------------------------------------------------------------------------
   
   wire [0:flit_ctrl_width-1] 		      flit_ctrl_s, flit_ctrl_q;
   
   assign flit_ctrl_s[0] = flit_valid_in;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   if(track_vcs_at_output)
	     begin
		
		wire [0:vc_idx_width-1] match_ovc_enc;
		c_encoder
		  #(.num_ports(num_vcs))
		match_ovc_enc_enc
		  (.data_in(match_ovc),
		   .data_out(match_ovc_enc));
		
		assign flit_ctrl_s[1:1+vc_idx_width-1]
			 = xbr_ctrl ? 
			   match_ovc_enc : 
			   flit_ctrl_q[1:1+vc_idx_width-1];
		
	     end
	   else
	     assign flit_ctrl_s[1:1+vc_idx_width-1]
		      = xbr_ctrl ? 
			int_flit_ctrl_in[1:1+vc_idx_width-1] :
			flit_ctrl_q[1:1+vc_idx_width-1];
	   
	end
      
      case(packet_format)
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     assign flit_ctrl_s[1+vc_idx_width+0]
		      = xbr_ctrl ? 
			int_flit_ctrl_in[1+vc_idx_width+0] : 
			flit_ctrl_q[1+vc_idx_width+0];
	     assign flit_ctrl_s[1+vc_idx_width+1]
		      = xbr_ctrl ? 
			int_flit_ctrl_in[1+vc_idx_width+1] : 
			flit_ctrl_q[1+vc_idx_width+1];
	  end
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     assign flit_ctrl_s[1+vc_idx_width+0]
		      = xbr_ctrl ? 
			int_flit_ctrl_in[1+vc_idx_width+0] : 
			flit_ctrl_q[1+vc_idx_width+0];
	  end
      endcase
      
   endgenerate
   
   wire 				flit_valid_s, flit_valid_q;
   assign flit_valid_s = flit_ctrl_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   assign flit_ctrl_q[0] = flit_valid_q;
   
   generate
      
      if(flit_ctrl_width > 1)
	begin
	   
	   c_dff
	     #(.width(flit_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE),
	       .offset(1))
	   flit_ctrlq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_ctrl_s[1:flit_ctrl_width-1]),
	      .q(flit_ctrl_q[1:flit_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   assign flit_ctrl_out = flit_ctrl_q;
   
   wire [0:flit_data_width-1] 		  flit_data_s, flit_data_q;
   assign flit_data_s = xbr_ctrl ? flit_data_in : flit_data_q;
   c_dff
     #(.width(flit_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_dataq
     (.clk(clk),
      .reset(reset),
      .d(flit_data_s),
      .q(flit_data_q));
   
   assign flit_data_out = flit_data_q;
   
   
   //---------------------------------------------------------------------------
   // error checker logic
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*2-1] 		  errors_out_ovc;
   c_checker
     #(.num_errors(num_vcs*2),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(error_cred_ovc),
      .errors_out(errors_out_ovc));
   
   assign error = error_unmatched | (|error_hct_ovc) | (|errors_out_ovc);
   
endmodule
