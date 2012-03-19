// $Id$

/*
 Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

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
// VC flow control state tracking module
//==============================================================================

module rtr_fc_state
  (clk, reset, active, flit_sent, fc_event_valid, fc_active, empty, 
   almost_full, full, full_prev, errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // make incoming flow control signals bypass the output VC state tracking 
   // logic
   parameter flow_ctrl_bypass = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // clock enable signal
   input active;
   
   // a flit was sent
   input flit_sent;
   
   // flow control event occurred
   input fc_event_valid;
   
   // activate flow control input logic
   output fc_active;
   wire   fc_active;
   
   // VC is empty
   output empty;
   wire   empty;

   // VC has one slot left
   output almost_full;
   wire   almost_full;
   
   // VC is full
   output full;
   wire   full;
   
   // VC was full in previous cycle
   output full_prev;
   wire   full_prev;
   
   // internal error condition detected
   output [0:1] errors;
   wire [0:1] 	errors;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire 	error_ft_underflow;
   wire 	error_ft_overflow;
   
   generate
      
      case(flow_ctrl_type)
	
	`FLOW_CTRL_TYPE_CREDIT:
	  begin
	     
	     //-----------------------------------------------------------------
	     // track number of flits the VC can still accept
	     //-----------------------------------------------------------------
	     
	     wire ft_debit;
	     assign ft_debit = flit_sent;
	     
	     wire ft_credit;
	     assign ft_credit = fc_event_valid;
	     
	     wire ft_almost_empty;
	     wire ft_empty;
	     wire ft_almost_full;
	     wire ft_full;
	     wire [0:flit_count_width-1] ft_free;
	     wire [0:1] 		 ft_errors;
	     c_fifo_tracker
	       #(.depth(num_flits_per_vc),
		 .reset_type(reset_type))
	     ft
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.push(ft_debit),
		.pop(ft_credit),
		.almost_empty(ft_almost_empty),
		.empty(ft_empty),
		.almost_full(ft_almost_full),
		.full(ft_full),
		.free(ft_free),
		.errors(ft_errors));

	     assign fc_active = ~ft_empty;
	     
	     wire 			 two_credits_left_s, two_credits_left_q;
	     if(num_flits_per_vc == 2)
	       assign two_credits_left_s
		 = (ft_almost_full & ~flit_sent & fc_event_valid) | 
		   (two_credits_left_q & (flit_sent ~^ fc_event_valid));
	     else if(num_flits_per_vc == 3)
	       assign two_credits_left_s
		 = (ft_almost_full & ~flit_sent & fc_event_valid) | 
		   (two_credits_left_q & (flit_sent ~^ fc_event_valid)) |
		   (ft_empty & flit_sent);
	     else if(num_flits_per_vc == 4)
	       assign two_credits_left_s
		 = (ft_almost_full & ~flit_sent & fc_event_valid) | 
		   (two_credits_left_q & (flit_sent ~^ fc_event_valid)) |
		   (ft_almost_empty & flit_sent & ~fc_event_valid);
	     else if(num_flits_per_vc > 4)
	       assign two_credits_left_s
		 = (ft_almost_full & ~flit_sent & fc_event_valid) | 
		   (two_credits_left_q & (flit_sent ~^ fc_event_valid)) |
		   (~|ft_free[0:flit_count_width-3] &
		    &ft_free[flit_count_width-2:flit_count_width-1] &
		    flit_sent & ~fc_event_valid);
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type),
		 .reset_value((num_flits_per_vc == 2) ? 1'b1 : 1'b0))
	     two_credits_leftq
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.d(two_credits_left_s),
		.q(two_credits_left_q));
	     
	     if(flow_ctrl_bypass)
	       begin
		  assign empty
		    = (ft_empty | (ft_almost_empty & fc_event_valid)) &
		      ~flit_sent;	
		  assign almost_full
		    = (ft_full & fc_event_valid) | 
		      (ft_almost_full & (flit_sent ~^ fc_event_valid)) |
		      (two_credits_left_q & flit_sent & ~fc_event_valid);
		  assign full = (ft_full | (ft_almost_full & flit_sent)) &
				~fc_event_valid;
		  assign full_prev = ft_full & ~fc_event_valid;
	       end
	     else
	       begin
		  assign empty = ft_empty & ~flit_sent;
		  assign almost_full
		    = flit_sent ? two_credits_left_q : ft_almost_full;
		  assign full = ft_full | (ft_almost_full & flit_sent);
		  assign full_prev = ft_full;
	       end

	     assign error_ft_underflow = ft_errors[0];
	     assign error_ft_overflow = ft_errors[1];
	     	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // pragma translate_off
   
   always @(posedge clk)
     begin
	
	if(error_ft_underflow)
	  $display("ERROR: Flit count tracker underflow in module %m.");
	
	if(error_ft_overflow)
	  $display("ERROR: Flit count tracker overflow in module %m.");
	
     end
   
   // pragma translate_on
   
   assign errors[0] = error_ft_underflow;
   assign errors[1] = error_ft_overflow;
   
endmodule
