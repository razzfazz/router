// $Id$

/*
Copyright (c) 2007-2010, Trustees of The Leland Stanford Junior University
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

//==============================================================================
// output port controller (tracks state of buffers in downstream router)
//==============================================================================

module vcr_ovc_ctrl
  (clk, reset, fc_event_valid, vc_req, vc_gnt, vc_gnt_ip, vc_gnt_ivc, 
   xbr_ctrl_ip, int_flit_ctrl, match, elig, empty, int_flow_ctrl, errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
   // width required to express number of packets in a VC
   localparam packet_count_width = clogb(num_packets_per_vc + 1);
   
   // number of traffic classes (e.g. request, reply)
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
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   // select whether VCs must have credits available in order to be considered 
   // for VC allocation
   parameter vc_alloc_requires_credit = 0;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // select implementation variant for tail flit FIFO
   parameter tff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // required address width for tail flit FIFO
   localparam tff_addr_width = clogb(num_flits_per_vc);
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width = 1 + vc_idx_width + 1 + 1;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_LEVEL) ? 2 :
       (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_PUSH) ? 1 :
       -1;
   
   // width of counter for credits waiting to be sent to input controller
   localparam cred_hold_width = vc_alloc_requires_credit ? 
				clogb(num_flits_per_vc) : 
				flit_count_width;
   
   // initial value for credit hold counter
   localparam [0:cred_hold_width-1] cred_hold_reset_value
     = vc_alloc_requires_credit ? (num_flits_per_vc - 1) : num_flits_per_vc;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // incoming flow control event
   input fc_event_valid;
   
   // output VC was requested by an input VC
   input vc_req;
   
   // output VC was granted to an input VC
   input vc_gnt;
   
   // input port that the output VC was granted to
   input [0:num_ports-1] vc_gnt_ip;
   
   // input VC that the output VC was granted to
   input [0:num_vcs-1] vc_gnt_ivc;
   
   // was this output granted to an input port?
   input [0:num_ports-1] xbr_ctrl_ip;
   
   // incoming flit control signals
   input [0:int_flit_ctrl_width-1] int_flit_ctrl;
   
   // output VC owns the current flit
   // (NOTE: only valid if track_vcs_at_output=1)
   output match;
   wire match;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output elig;
   wire elig;
   
   // no buffer slots in output VC are in use (i.e., all credits are present)
   output empty;
   wire empty;
   
   // internal flow control signalling from output controller to input 
   // controllers
   output [0:int_flow_ctrl_width-1] int_flow_ctrl;
   wire [0:int_flow_ctrl_width-1] int_flow_ctrl;
   
   // internal error condition detected
   output [0:3] errors;
   wire [0:3] 			  errors;
   
   
   //---------------------------------------------------------------------------
   // decode control signals
   //---------------------------------------------------------------------------
   
   wire 			  flit_valid;
   assign flit_valid = int_flit_ctrl[0] & |xbr_ctrl_ip;
   
   wire 			  flit_head;
   assign flit_head = int_flit_ctrl[1+vc_idx_width];
   
   wire 			  flit_tail;
   assign flit_tail = int_flit_ctrl[1+vc_idx_width+1];
   
   wire 			  credit;
   assign credit = fc_event_valid;
   
   wire 			   flit_valid_qual;
   assign flit_valid_qual = flit_valid & match;
   
   wire 			   debit;
   assign debit = flit_valid_qual;
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently assigend to an input VC
   //---------------------------------------------------------------------------
   
   wire 			   alloc_active;
   assign alloc_active = vc_req | (|xbr_ctrl_ip);
   
   wire 			   allocated_q;
   
   wire 			   next_allocated;   
   assign next_allocated = vc_gnt | allocated_q;
   
   wire 			   allocated_s;
   assign allocated_s = next_allocated & ~(flit_valid_qual & flit_tail);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .d(allocated_s),
      .q(allocated_q));
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc;
	   assign flit_vc = int_flit_ctrl[1:1+vc_idx_width-1];
	   
	   // if VC assignment is tracked at the output, each output VC needs to
	   // check if it is currently assigned to the incoming VC ID at the 
	   // selected input port
	   if(track_vcs_at_output)
	     begin
		
		wire [0:num_ports-1] allocated_ip_s, allocated_ip_q;
		assign allocated_ip_s = vc_gnt ? vc_gnt_ip : allocated_ip_q;
		c_dff
		  #(.width(num_ports),
		    .reset_type(reset_type))
		allocated_ipq
		  (.clk(clk),
		   .reset(reset),
		   .active(alloc_active),
		   .d(allocated_ip_s),
		   .q(allocated_ip_q));
		
		wire [0:vc_idx_width-1] vc_gnt_vc;
		c_encode
		  #(.num_ports(num_vcs))
		vc_gnt_vc_enc
		  (.data_in(vc_gnt_ivc),
		   .data_out(vc_gnt_vc));
		
		wire [0:vc_idx_width-1] allocated_vc_s, allocated_vc_q;
		assign allocated_vc_s = vc_gnt ? vc_gnt_vc : allocated_vc_q;
		c_dff
		  #(.width(vc_idx_width),
		    .reset_type(reset_type))
		allocated_vcq
		  (.clk(clk),
		   .reset(reset),
		   .active(alloc_active),
		   .d(allocated_vc_s),
		   .q(allocated_vc_q));
		
		assign match = allocated_q &&
			       |(allocated_ip_q & xbr_ctrl_ip) &&
			       (allocated_vc_q == flit_vc);
		
	     end
	   
	   // if VC assignments are tracked at the input side, we can just check
	   // for our own VC ID
	   else
	     assign match = (flit_vc == vc_id);
	   
	end
      
      // if we only have a single VC to begin with, it is always selected
      else
	assign match = 1'b1;
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track number of packets that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 				cred_active;
   assign cred_active = credit;
   
   wire 				flags_active;
   assign flags_active = alloc_active | cred_active;
   
   wire 				ft_almost_empty;
   wire 				head_full;
   wire 				error_hft_underflow;
   wire 				error_hft_overflow;
   
   generate
      
      if(num_packets_per_vc == num_flits_per_vc)
	begin
	   
	   // if every flit buffer entry can be a head flit, we don't need 
	   // dedicated credit tracking for headers, and can instead just rely 
	   // on the normal credit tracking mechanism
	   assign head_full = 1'b0;
	   
	   assign error_hft_underflow = 1'b0;
	   assign error_hft_overflow = 1'b0;
	   
	end
      else if(num_packets_per_vc < num_flits_per_vc)
	begin
	   
	   // if only a subset of the flit buffer entries can be headers, we 
	   // need to keep track of how many such slots are left
	   
	   wire head_credit;
	   
	   if(num_packets_per_vc == 1)
	     begin
		
		// if we can only have one packet per buffer, we can accept the 
		// next one once the buffer has been completely drained after 
		// the tail has been sent
		
		wire last_credit_received;
		assign last_credit_received = ft_almost_empty & credit;
		
		wire tail_sent_s, tail_sent_q;
		assign tail_sent_s
		  = ((tail_sent_q & ~(flit_valid_qual & flit_head)) | 
		     (flit_valid_qual & flit_tail));
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		tail_sentq
		  (.clk(clk),
		   .reset(reset),
		   .active(alloc_active),
		   .d(tail_sent_s),
		   .q(tail_sent_q));
		
		assign head_credit = tail_sent_q & last_credit_received;
		
	     end
	   else if(num_packets_per_vc > 1)
	     begin
		
		wire 			  tff_push_data;
		assign tff_push_data = flit_tail;
		
		wire 			  tff_pop_data;
		wire 			  tff_almost_full;
		wire 			  tff_full;
		wire 			  tff_almost_empty;
		wire 			  tff_empty;
		wire [0:1] 		  tff_errors;
		c_fifo
		  #(.depth(num_flits_per_vc),
		    .width(1),
		    .regfile_type(tff_regfile_type),
		    .reset_type(reset_type))
		tff
		  (.clk(clk),
		   .reset(reset),
		   .push_active(alloc_active),
		   .pop_active(cred_active),
		   .push(flit_valid_qual),
		   .pop(credit),
		   .push_data(tff_push_data),
		   .pop_data(tff_pop_data),
		   .almost_empty(tff_almost_empty),
		   .empty(tff_empty),
		   .almost_full(tff_almost_full),
		   .full(tff_full),
		   .errors(tff_errors));
		
		assign head_credit = credit & tff_pop_data;		
		
	     end
	   
	   wire 				 head_debit;
	   assign head_debit = vc_gnt;
	   
	   // track header credits using stock FIFO tracker module
	   wire 				 hft_almost_empty;
	   wire 				 hft_empty;
	   wire 				 hft_almost_full;
	   wire 				 hft_full;
	   wire [0:packet_count_width-1] 	 hft_free;
	   wire [0:1] 				 hft_errors;
	   c_fifo_tracker
	     #(.depth(num_packets_per_vc),
	       .reset_type(reset_type))
	   hft
	     (.clk(clk),
	      .reset(reset),
	      .active(flags_active),
	      .push(head_debit),
	      .pop(head_credit),
	      .almost_empty(hft_almost_empty),
	      .empty(hft_empty),
	      .almost_full(hft_almost_full),
	      .full(hft_full),
	      .free(hft_free),
	      .errors(hft_errors));
	   
	   assign head_full = hft_full;
	   
	   assign error_hft_underflow = hft_errors[0];
	   assign error_hft_overflow = hft_errors[1];
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 					 ft_empty;
   wire 					 ft_almost_full;
   wire 					 ft_full;
   wire [0:flit_count_width-1] 			 ft_free;
   wire [0:1] 					 ft_errors;
   c_fifo_tracker
     #(.depth(num_flits_per_vc),
       .reset_type(reset_type))
   ft
     (.clk(clk),
      .reset(reset),
      .active(flags_active),
      .push(debit),
      .pop(credit),
      .almost_empty(ft_almost_empty),
      .empty(ft_empty),
      .almost_full(ft_almost_full),
      .full(ft_full),
      .free(ft_free),
      .errors(ft_errors));
   
   assign empty = ft_empty;
   
   wire 					 error_ct_underflow;
   assign error_ct_underflow = ft_errors[0];
   
   wire 					 error_ct_overflow;
   assign error_ct_overflow = ft_errors[1];
   
   
   //---------------------------------------------------------------------------
   // generate flow control signals to input controller
   //---------------------------------------------------------------------------
   
   generate
      
      case(int_flow_ctrl_type)
	
	`INT_FLOW_CTRL_TYPE_LEVEL:
	  begin
	     
	     // NOTE: The debit input to this module is driven by the input VC 
	     // controller. Consequently, the debit signal is already readily 
	     // available at the input controller, and we can simply pass the 
	     // current credit level, incremented by one if a credit was just 
	     // received, from output to input controller, rather having the 
	     // debit signal effectively go from input to output controller 
	     // and back. Note that whenever an output VC is allocated to an 
	     // input VC, no flit can have been sent in the current cycle, as
	     // in order for VC allocation to succeed, the output VC must be 
	     // eligible for allocation in the current cycle, and thus cannot 
	     // be assigned to another input VC.
	     
	     assign int_flow_ctrl[0] = ~ft_full & (~ft_almost_full | credit);
	     assign int_flow_ctrl[1] = ft_almost_full | (ft_full & credit);
	     
	  end
	
	`INT_FLOW_CTRL_TYPE_PUSH:
	  begin
	     
	     wire [0:cred_hold_width-1] cred_hold_base;
	     assign cred_hold_base
	       = ft_free[flit_count_width-cred_hold_width:flit_count_width-1];
	     
	     wire [0:cred_hold_width-1] cred_hold_copy;
	     
	     if(vc_alloc_requires_credit)
	       begin
		  
		  // If the VC is currently full, of if there is only a single 
		  // credit left in the VC and we don't receive another one in 
		  // this cycle, we know that there cannot be any credits left 
		  // for the next cycle.
		  
		  wire force_zero;
		  assign force_zero = ft_full | (ft_almost_full & ~credit);
		  
		  // Otherwise we must subtract one from the current credit
		  // count, and then add 'credit' and subtract 'debit'; note
		  // that this can potentially cause underflows, so we will
		  // use 'force_zero' later to mask out such incorrect results.
		  
		  // First we adjust the credit count by adding 'credit' and 
		  // subtracting one.
		  // (NOTE: -1+x = -(1-x) = -(~x) for single-bit x)
		  
		  wire [0:cred_hold_width-1] cred_hold_step1;
		  assign cred_hold_step1 = cred_hold_base - !credit;
		  
		  // Then we subtract the incoming 'debit' signal.
		  
		  wire [0:cred_hold_width-1] cred_hold_step2;
		  assign cred_hold_step2 = cred_hold_step1 - debit;
		  
		  // Forcing the result to zero in this case allows us to 
		  // avoid a potential underflow when unconditionally 
		  // subtracting the incoming 'debit' signal.
		  
		  assign cred_hold_copy
		    = cred_hold_step2 & {cred_hold_width{~force_zero}};
		  
	       end
	     else
	       begin
		  
		  wire [0:cred_hold_width-1] cred_hold_plus_credit;
		  assign cred_hold_plus_credit = cred_hold_base + credit;
		  
		  assign cred_hold_copy = cred_hold_plus_credit - debit;
		  
	       end
	     
	     if(cred_hold_width >= 2)
	       begin
		  
		  wire cred_hold_any;
		  
		  // NOTE: This doesn't fit in well with any of the other clock
		  // gating domains, as the register needs to be kept active 
		  // until all credits have been sent; the register is probably 
		  // not wide enough to end up in a clock gating domain of its 
		  // own, so it will most likely end up being free-running.
		  
		  wire cred_hold_active;
		  assign cred_hold_active = flags_active | cred_hold_any;
		  
		  wire [0:cred_hold_width-1] cred_hold_s, cred_hold_q;
		  assign cred_hold_s
		    = next_allocated ?
		      (cred_hold_q - (cred_hold_any & ~credit)) :
		      cred_hold_copy;
		  c_dff
		    #(.width(cred_hold_width),
		      .reset_type(reset_type),
		      .reset_value(cred_hold_reset_value))
		  cred_holdq
		    (.clk(clk),
		     .reset(reset),
		     .active(cred_hold_active),
		     .d(cred_hold_s),
		     .q(cred_hold_q));
		  
		  assign cred_hold_any = |cred_hold_q;
		  
		  assign int_flow_ctrl
		    = next_allocated ?
		      (|cred_hold_q[0:cred_hold_width-2] | credit) :
		      |cred_hold_copy;
		  
	       end
	     else
	       assign int_flow_ctrl = next_allocated ? credit : |cred_hold_copy;
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // keep track of whether current VC is available for allocation
   //---------------------------------------------------------------------------
   
   generate
      
      if(vc_alloc_requires_credit)
	begin
	   
	   // Instead of just computing this as the reduction of of the updated 
	   // credit count sum, we can optimize a bit. In particular, we have 
	   // one or more credits available iff...
	   //  a) ... we just received a credit. In this case, we either had 
	   //     credits available to begin with, or there cannot be a debit 
	   //     at the same time.
	   //  b) ... we currently have at least two credits available. In this 
	   //     case, even if there is a debit and no credit, we will still 
	   //     have at least one credit left.
	   //  c) ... we currently have a single credit available, and did not 
	   //     just receive a debit.
	   // This only leaves out the case where we are not receiving a credit,
	   // do not currently have two or more credits and either have no 
	   // credits left or have a single credit left and receive a debit.
	   wire cred_s, cred_q;
	   assign cred_s = credit | (~ft_full & (~ft_almost_full | ~debit));
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   credq
	     (.clk(clk),
	      .reset(reset),
	      .active(flags_active),
	      .d(cred_s),
	      .q(cred_q));
	   
	   assign elig = ~allocated_q & ~head_full & cred_q;
	   
	end
      else
	assign elig = ~allocated_q & ~head_full;
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   integer 	i;
   
   always @(posedge clk)
     begin
	
	for(i = 0; i < num_vcs; i = i + 1)
	  begin
	     
	     if(error_ct_underflow)
	       $display("ERROR: Credit tracker underflow in module %m.");
	     
	     if(error_ct_overflow)
	       $display("ERROR: Credit tracker overflow in module %m.");
	     
	     if(error_hft_underflow)
	       $display("ERROR: Head credit tracker underflow in module %m.");
	     
	     if(error_hft_overflow)
	       $display("ERROR: Head credit tracker overflow in module %m.");
	     
	  end
	
     end
   
   // synopsys translate_on
   
   assign errors = {error_ct_underflow, 
		    error_ct_overflow,
		    error_hft_underflow, 
		    error_hft_overflow};
   
endmodule
