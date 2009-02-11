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

// output port controller (tracks state of buffers in downstream router)
module op_ctrl
  (clk, reset, cred_valid_in, cred_vc_in, vc_gnt_ovc, vc_gnt_ovc_ip, 
   vc_gnt_ovc_ivc, xbr_ctrl_ip, flit_valid_in, flit_vc_in, flit_head_in, 
   flit_tail_in, flit_data_in, flit_valid_out, flit_vc_out, flit_head_out, 
   flit_tail_out, flit_data_out, elig_ovc, flow_ctrl_ovc, error);
   
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
   
   // width required to select a buffer
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   // width of counter for credits waiting to be sent to input controller
   localparam cred_hold_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // flit width
   parameter flit_data_width = 64;
   
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
   
   // valid credit data available
   input cred_valid_in;
   
   // which VC does credit pertain to
   // (note: only valid if cred_valid_in=1)
   input [0:vc_idx_width-1] cred_vc_in;
   
   // output VC was granted to an input VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // input port that each output VC was granted to
   input [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
   
   // input VC that each output VC was granted to
   input [0:num_vcs*num_vcs-1] vc_gnt_ovc_ivc;

   // port to which this output is currently connected
   input [0:num_ports-1] xbr_ctrl_ip;
   
   // valid flit data incoming
   input flit_valid_in;
   
   // which VC is incoming flit travelling on
   // (note: only valid if flit_valid_in=1)
   input [0:vc_idx_width-1] flit_vc_in;
   
   // incoming flit is head
   // (note: only valid if flit_valid_in=1)
   input flit_head_in;
   
   // incoming flit is tail
   // (note: only valid if flit_valid_in=1)
   input flit_tail_in;
   
   // flit data for each incoming flit
   // (note: only valid when flit_valid_in=1)
   input [0:flit_data_width-1] flit_data_in;
   
   // valid flit data outgoing
   output flit_valid_out;
   wire flit_valid_out;
   
   // destination VC ID for current flit
   // (note: only valid if flit_valid_out=1)
   output [0:vc_idx_width-1] flit_vc_out;
   wire [0:vc_idx_width-1] flit_vc_out;
   
   // incoming flit is head
   // (note: only valid if flit_valid_out=1)
   output flit_head_out;
   wire 		   flit_head_out;
   
   // incoming flit is tail
   // (note: only valid if flit_valid_out=1)
   output flit_tail_out;
   wire 		   flit_tail_out;
   
   // flit data for each outgoing flit
   // (note: only valid when flit_valid_out=1)
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs-1] elig_ovc;
   
   // internal flow control signalling from output controller to input 
   // controllers
   output [0:num_vcs*int_flow_ctrl_width-1] flow_ctrl_ovc;
   wire [0:num_vcs*int_flow_ctrl_width-1] flow_ctrl_ovc;
   
   // internal error condition detected
   output error;
   wire 				  error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire 				  cred_valid_s, cred_valid_q;
   assign cred_valid_s = cred_valid_in;
   dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   wire [0:vc_idx_width-1] 		  cred_vc_s, cred_vc_q;
   assign cred_vc_s = cred_vc_in;
   dff
     #(.width(vc_idx_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   cred_vcq
     (.clk(clk),
      .reset(reset),
      .d(cred_vc_s),
      .q(cred_vc_q));
   
   
   //---------------------------------------------------------------------------
   // output VC control logic
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 			  next_cred_ovc;
   wire [0:num_vcs-1] 			  error_hct_ovc;
   wire [0:num_vcs*2-1] 		  error_cred_ovc;
   wire [0:num_vcs-1] 			  match_ovc;
   
   generate
      
      genvar 				  ovc;
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   assign credit = cred_valid_q && (cred_vc_q == ovc);
	   
	   wire debit;
	   assign debit = flit_valid_in & match_ovc[ovc];
	   
	   wire vc_gnt;
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
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   allocatedq
	     (.clk(clk),
	      .reset(reset),
	      .d(allocated_s),
	      .q(allocated_q));
	   
	   if(track_vcs_at_output)
	     begin
		
		wire [0:num_ports-1] vc_gnt_ip;
		assign vc_gnt_ip
		  = vc_gnt_ovc_ip[ovc*num_ports:(ovc+1)*num_ports-1];
		
		wire [0:num_ports-1] allocated_ip_s, allocated_ip_q;
		assign allocated_ip_s = vc_gnt ? vc_gnt_ip : allocated_ip_q;
		dff
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
		assign allocated_ivc_s = vc_gnt ? vc_gnt_ivc : allocated_ivc_q;
		dff
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
	   else
	     assign match_ovc[ovc] = (flit_vc_in == ovc);
	   
	   
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
		     dff
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
		     dff
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
		     incr
		       #(.width(flit_buffer_idx_width),
			 .min_value(0),
			 .max_value(num_flit_buffers-1))
		     push_ptr_incr
		       (.data_in(push_ptr_q),
			.data_out(push_ptr_next));
		     
		     wire [0:flit_buffer_idx_width-1] push_ptr_s;
		     assign push_ptr_s = debit ? push_ptr_next : push_ptr_q;
		     dff
		       #(.width(flit_buffer_idx_width),
			 .reset_type(reset_type))
		     push_ptrq
		       (.clk(clk),
			.reset(reset),
			.d(push_ptr_s),
			.q(push_ptr_q));
		     
		     wire [0:flit_buffer_idx_width-1] pop_ptr_next, pop_ptr_q;
		     incr
		       #(.width(flit_buffer_idx_width),
			 .min_value(0),
			 .max_value(num_flit_buffers-1))
		     pop_ptr_incr
		       (.data_in(pop_ptr_q),
			.data_out(pop_ptr_next));
		     
		     wire [0:flit_buffer_idx_width-1] pop_ptr_s;
		     assign pop_ptr_s = credit ? pop_ptr_next : pop_ptr_q;
		     dff
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
		     credit_tracker
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
	   dff
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
		  dff
		    #(.width(cred_level_width),
		      .reset_type(reset_type),
		      .reset_value(free_reset_value))
		  freeq
		    (.clk(clk),
		     .reset(reset),
		     .d(free_s),
		     .q(free_q));
		  
		  assign flow_ctrl_ovc[ovc*cred_level_width:
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
		  dff
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
		  dff
		    #(.width(1),
		      .reset_type(reset_type),
		      .reset_value(1))
		  credq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_s),
		     .q(cred_q));
		  
		  assign flow_ctrl_ovc[ovc] = cred_q;
		  
	       end
	     
	   endcase
	   
	   
	   //-------------------------------------------------------------------
	   // keep track of whether current VC is available for allocation
	   //-------------------------------------------------------------------
	   
	   wire 			      elig_s, elig_q;
	   assign elig_s = ~allocated_s & head_free_early & next_cred_ovc[ovc];
	   dff
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
   
   wire 				      xbr_ctrl;
   assign xbr_ctrl = |xbr_ctrl_ip;
   
   wire 				      flit_valid_s, flit_valid_q;
   assign flit_valid_s = xbr_ctrl & flit_valid_in;
   dff
     #(.width(1),
       .reset_type(reset_type))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   assign flit_valid_out = flit_valid_q;
   
   wire [0:vc_idx_width-1] 		      flit_vc_s, flit_vc_q;
   
   generate
      
      if(track_vcs_at_output)
	begin
	   
	   wire [0:vc_idx_width-1] match_ovc_enc;
	   encoder
	     #(.num_ports(num_vcs))
	   match_ovc_enc_enc
	     (.data_in(match_ovc),
	      .data_out(match_ovc_enc));
	   
	   assign flit_vc_s = xbr_ctrl ? match_ovc_enc : flit_vc_q;
	   
	end
      else
	assign flit_vc_s = xbr_ctrl ? flit_vc_in : flit_vc_q;
      
   endgenerate
   
   dff
     #(.width(vc_idx_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_vcq
     (.clk(clk),
      .reset(reset),
      .d(flit_vc_s),
      .q(flit_vc_q));
   
   assign flit_vc_out = flit_vc_q;
   
   wire 			   flit_head_s, flit_head_q;
   assign flit_head_s = xbr_ctrl ? flit_head_in : flit_head_q;
   dff
     #(.width(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_headq
     (.clk(clk),
      .reset(reset),
      .d(flit_head_s),
      .q(flit_head_q));
   
   assign flit_head_out = flit_head_q;
   
   wire 			   flit_tail_s, flit_tail_q;
   assign flit_tail_s = xbr_ctrl ? flit_tail_in : flit_tail_q;
   dff
     #(.width(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_tailq
     (.clk(clk),
      .reset(reset),
      .d(flit_tail_s),
      .q(flit_tail_q));
   
   assign flit_tail_out = flit_tail_q;
   
   wire [0:flit_data_width-1] 	   flit_data_s, flit_data_q;
   assign flit_data_s = xbr_ctrl ? flit_data_in : flit_data_q;
   dff
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
   
   wire [0:num_vcs*2-1] 		      errors_out_ovc;
   checker
     #(.num_errors(num_vcs*2),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(error_cred_ovc),
      .errors_out(errors_out_ovc));
   
   assign error = (|error_hct_ovc) | (|errors_out_ovc);
   
endmodule
