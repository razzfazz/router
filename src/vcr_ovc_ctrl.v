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
   xbr_ctrl_ip, flit_valid, flit_tail, elig, empty, int_flow_ctrl, 
   errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
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
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // select implementation variant for tail sent tracker register file
   parameter tst_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // required address width for tail flit FIFO
   localparam tff_addr_width = clogb(num_flits_per_vc);
   
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
   
   // incoming flit is valid
   input flit_valid;
   
   // incoming flit is a tail flit
   input flit_tail;
   
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
   output [0:1] errors;
   wire [0:1] 			  errors;
   
   
   //---------------------------------------------------------------------------
   // decode control signals
   //---------------------------------------------------------------------------
   
   wire 			  credit;
   assign credit = fc_event_valid;
   
   wire 			  debit;
   assign debit = flit_valid;
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently assigend to an input VC
   //---------------------------------------------------------------------------
   
   wire 			  alloc_active;
   assign alloc_active = vc_req | (|xbr_ctrl_ip);
   
   wire 			  allocated_q;
   
   wire 			  next_allocated;   
   assign next_allocated = vc_gnt | allocated_q;
   
   wire 			  allocated_s;
   assign allocated_s = next_allocated & ~(flit_valid & flit_tail);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .d(allocated_s),
      .q(allocated_q));
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 			  flags_active;
   assign flags_active = alloc_active | credit;
   
   wire 			  ft_almost_empty;
   wire 			  ft_empty;
   wire 			  ft_almost_full;
   wire 			  ft_full;
   wire [0:flit_count_width-1] 	  ft_free;
   wire [0:1] 			  ft_errors;
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
   
   wire 			  error_ct_underflow;
   assign error_ct_underflow = ft_errors[0];
   
   wire 			  error_ct_overflow;
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
	assign elig = ~allocated_q & (~ft_full | credit);
      else
	assign elig = ~allocated_q;
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	
	if(error_ct_underflow)
	  $display("ERROR: Credit tracker underflow in module %m.");
	
	if(error_ct_overflow)
	  $display("ERROR: Credit tracker overflow in module %m.");
	
     end
   
   // synopsys translate_on
   
   assign errors[0] = error_ct_underflow;
   assign errors[1] = error_ct_overflow;
   
endmodule
