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
  (clk, reset, flit_ctrl_in, flow_ctrl_in, vc_gnt_ovc, elig_ovc, flow_ctrl_ovc, 
   error);
   
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
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
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
   
   // select method for credit signaling from output to input controller
   parameter int_flow_control_type = `INT_FLOW_CONTROL_TYPE_CREDIT_PUSH;
   
   // number of bits to be used for credit level reporting
   // (note: must be less than or equal to cred_count_width as given below)
   // (note: this parameter is only used for INT_FLOW_CONTROL_TYPE_CREDIT_LEVEL)
   parameter cred_level_width = 2;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_control_type == `INT_FLOW_CONTROL_TYPE_CREDIT_LEVEL) ?
       cred_level_width :
       (int_flow_control_type == `INT_FLOW_CONTROL_TYPE_CREDIT_PUSH) ?
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
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // output VC was granted to an input VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
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
   
   wire [0:num_vcs-1] 			  next_cred_ovc;
   wire [0:num_vcs-1] 			  error_hct_ovc;
   wire [0:num_vcs*2-1] 		  error_cred_ovc;
   
   wire 				  flit_valid_in;
   wire 				  flit_head_in;
   wire 				  flit_tail_in;
   wire [0:num_vcs-1] 			  flit_valid_ovc;
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     
	     assign flit_valid_in = flit_ctrl_in[0];
	     assign flit_head_in = flit_ctrl_in[1];
	     assign flit_tail_in = flit_ctrl_in[2];
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] flit_vc_in;
		  assign flit_vc_in = flit_ctrl_in[3:3+vc_idx_width-1];
		  
		  wire [0:num_vcs-1] 	  flit_vc_1hot;
		  decoder
		    #(.num_ports(num_vcs))
		  flit_vc_1hot_dec
		    (.data_in(flit_vc_in),
		     .data_out(flit_vc_1hot));
		  
		  assign flit_valid_ovc
		    = {num_vcs{flit_valid_in}} & flit_vc_1hot;
		  
	       end
	     else
	       assign flit_valid_ovc = flit_valid_in;
	     
	  end
	
      endcase
      
      genvar ovc;
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire 			       vc_gnt;
	   assign vc_gnt = vc_gnt_ovc[ovc];
	   
	   
	   //-------------------------------------------------------------------
	   // track whether this output VC is currently assigend to an input VC
	   //-------------------------------------------------------------------
	   
	   wire 			       set_allocated;
	   assign set_allocated = vc_gnt;
	   
	   wire 			       reset_allocated;   
	   assign reset_allocated = flit_valid_ovc[ovc] & flit_tail_in;
	   
	   wire 			       allocated_s, allocated_q;
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
	   
	   
	   //-------------------------------------------------------------------
	   // keep track of whether current VC is available for allocation
	   //-------------------------------------------------------------------
	   
	   wire 			       head_free_early;
	   
	   wire 			       elig_s, elig_q;
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
	   
	   
	   //-------------------------------------------------------------------
	   // track downstream buffer state
	   //-------------------------------------------------------------------
	   
	   case(flow_control_type)
	     
	     `FLOW_CONTROL_TYPE_CREDIT:
	       begin
		  
		  wire cred_valid;
		  
		  if(num_vcs > 1)
		    begin
		       
		       wire [0:vc_idx_width-1] cred_vc;
		       assign cred_vc = flow_ctrl_in[1:1+vc_idx_width-1];
		       
		       assign cred_valid = flow_ctrl_in[0] && (cred_vc == ovc);
		       
		    end
		  else
		    assign cred_valid = flow_ctrl_in[0];
		  
		  wire 			       credit;
		  assign credit = cred_valid;
		  
		  wire 			       debit;
		  assign debit = flit_valid_ovc[ovc];
		  
		  
		  //------------------------------------------------------------
		  // track number of packets that downstream buffer can still 
		  // accept
		  //------------------------------------------------------------
		  
		  wire [0:cred_count_width-1]  cred_count_s;
		  
		  if(num_header_buffers == num_flit_buffers)
		    begin
		       
		       
		       // if every flit buffer entry can be a head flit, we 
		       // don't need dedicated credit tracking for headers, and 
		       // can instead just rely on the normal credit tracking 
		       // mechanism
		       assign head_free_early = 1'b1;
		       
		       assign error_hct_ovc[ovc] = 1'b0;
		       
		    end
		  else
		    begin
		       
		       // if only a subset of the flit buffer entries can be 
		       // headers, we need to keep track of how many such slots 
		       // are left
		       
		       wire head_credit;
		       
		       if(num_header_buffers == 1)
			 begin
			    
			    // if we can only have one packet per buffer, we 
			    // can accept the next one once the buffer has been 
			    // emptied
			    assign head_credit
			      = credit && (cred_count_s == num_flit_buffers);
			    
			 end
		       else
			 begin
			    
			    wire [0:num_flit_buffers-1] tail_queue_s,
							tail_queue_q;
			    
			    wire [0:flit_buffer_idx_width-1] push_ptr_q;
			    
			    genvar 			     idx;
			    
			    for(idx = 0; idx < num_flit_buffers; idx = idx + 1)
			      begin:idxs
				 
				 wire capture;
				 assign capture = debit && (push_ptr_q == idx);
				 
				 assign tail_queue_s[idx] = capture ?
							    flit_tail_in :
							    tail_queue_q[idx];
				 
			      end
			    
			    dff
			      #(.width(num_flit_buffers),
				.reset_type(reset_type))
			    tail_queueq
			      (.clk(clk),
			       .reset(reset),
			       .d(tail_queue_s),
			       .q(tail_queue_q));
			    
			    wire [0:flit_buffer_idx_width-1] push_ptr_next;
			    incr
			      #(.width(flit_buffer_idx_width),
				.min_value(0),
				.max_value(num_flit_buffers-1))
			    push_ptr_incr
			      (.data_in(push_ptr_q),
			       .data_out(push_ptr_next));
			    
			    wire [0:flit_buffer_idx_width-1] push_ptr_s;
			    assign push_ptr_s
			      = debit ? push_ptr_next : push_ptr_q;
			    dff
			      #(.width(flit_buffer_idx_width),
				.reset_type(reset_type))
			    push_ptrq
			      (.clk(clk),
			       .reset(reset),
			       .d(push_ptr_s),
			       .q(push_ptr_q));
			    
			    wire [0:flit_buffer_idx_width-1] pop_ptr_next,
							     pop_ptr_q;
			    incr
			      #(.width(flit_buffer_idx_width),
				.min_value(0),
				.max_value(num_flit_buffers-1))
			    pop_ptr_incr
			      (.data_in(pop_ptr_q),
			       .data_out(pop_ptr_next));
			    
			    wire [0:flit_buffer_idx_width-1] pop_ptr_s;
			    assign pop_ptr_s
			      = credit ? pop_ptr_next : pop_ptr_q;
			    dff
			      #(.width(flit_buffer_idx_width),
				.reset_type(reset_type))
			    pop_ptrq
			      (.clk(clk),
			       .reset(reset),
			       .d(pop_ptr_s),
			       .q(pop_ptr_q));
			    
			    wire 			     tail;
			    mux_nto1
			      #(.num_ports(num_flit_buffers),
				.width(1))
			    tail_mux
			      (.select(pop_ptr_q),
			       .data_in(tail_queue_q),
			       .data_out(tail));
			    
			    assign head_credit = tail & credit;
			    
			 end
		       
		       wire 				     head_debit;
		       assign head_debit = vc_gnt;
		       
		       // track header credits using stock credit tracker module
		       wire 				     head_free;
		       wire 				     error_hct;
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
		  
		  
		  //------------------------------------------------------------
		  // track number of flits that downstream buffer can still 
		  // accept
		  //------------------------------------------------------------
		  
		  wire [0:cred_count_width-1] 		     cred_count_q;
		  assign cred_count_s = (cred_valid | flit_valid_in) ?
					(cred_count_q + credit - debit) :
					cred_count_q;
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
		  
		  wire [0:1] 				     error_cred;
		  assign error_cred
		    = {(cred_count_q == num_flit_buffers) && credit,
		       (cred_count_q == 0) && debit};
		  
		  assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
		  
		  
		  //------------------------------------------------------------
		  // generate flow control signals to input controller
		  //------------------------------------------------------------
		  
		  case(int_flow_control_type)
		    
		    `INT_FLOW_CONTROL_TYPE_CREDIT_LEVEL:
		      begin
			 
			 wire [0:cred_level_width-1] free_s, free_q;
			 assign free_s = (cred_valid | flit_valid_in) ?
					 ((cred_count_s > max_cred_level) ?
					  max_cred_level :
					  cred_count_s[cred_count_width-
						       cred_level_width:
						       cred_count_width-1]) :
					 free_q;
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
		    
		    `INT_FLOW_CONTROL_TYPE_CREDIT_PUSH:
		      begin
			 
			 wire [0:cred_hold_width-1]  cred_hold_copy;
			 assign cred_hold_copy
			   = cred_count_s[(cred_count_width-cred_hold_width):
					  cred_count_width-1] - 1'b1;
			 
			 wire [0:cred_hold_width-1]  cred_hold_s, cred_hold_q;
			 assign cred_hold_s
			   = vc_gnt ?
			     cred_hold_copy :
			     (allocated_q ?
			      (cred_hold_q - (|cred_hold_q & ~credit)) :
			      cred_hold_q);
			 dff
			   #(.width(cred_hold_width),
			     .reset_type(reset_type),
			     .reset_value(num_flit_buffers-1))
			 cred_holdq
			   (.clk(clk),
			    .reset(reset),
			    .d(cred_hold_s),
			    .q(cred_hold_q));
			 
			 wire 			     cred_s, cred_q;
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
		  
	       end
	     
	   endcase
	   
	end
      
   endgenerate
   
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
