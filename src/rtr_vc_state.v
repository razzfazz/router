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
// VC state tracking module
//==============================================================================

module rtr_vc_state
  (clk, reset, active, flit_sent, flit_tail, fc_event_valid, elig, 
   almost_empty, empty, almost_full, full, free, errors);
   
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
   
   // sent flit was a tail flit
   input flit_tail;
   
   // flow control event occurred
   input fc_event_valid;
   
   // VC is eligible for allocation
   output elig;
   wire   elig;
   
   // VC has one flit left
   output almost_empty;
   wire   almost_empty;
   
   // VC is empty
   output empty;
   wire   empty;

   // VC has one slot left
   output almost_full;
   wire   almost_full;
   
   // VC is full
   output full;
   wire   full;
   
   // VC fill level indicator
   output [0:flit_count_width-1] free;
   wire [0:flit_count_width-1] 	 free;
   
   // internal error condition detected
   output [0:1] 		 errors;
   wire [0:1] 			 errors;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire 			 error_ft_underflow;
   wire 			 error_ft_overflow;
   
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
	     
	     assign almost_empty = ft_almost_empty;
	     assign empty = ft_empty;
	     assign almost_full = ft_almost_full;
	     assign full = ft_full;
	     assign free = ft_free;
	     
	     assign error_ft_underflow = ft_errors[0];
	     assign error_ft_overflow = ft_errors[1];
	     	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently in use
   //---------------------------------------------------------------------------
   
   // NOTE: For the reset condition, we don't have to worry about whether or
   // not sufficient buffer space is available: If the VC is currently 
   // allocated, these checks would already have been performed at the 
   // beginning of switch allocation; on the other hand, if it is not currently 
   // allocated, 'allocated_q' is zero, and thus the reset condition does not 
   // have any effect.
   
   wire 					allocated_s, allocated_q;
   assign allocated_s = (allocated_q | flit_sent) & ~(flit_sent & flit_tail);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(allocated_s),
      .q(allocated_q));
   
   assign elig = ~allocated_q;
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	
	if(error_ft_underflow)
	  $display("ERROR: Flit count tracker underflow in module %m.");
	
	if(error_ft_overflow)
	  $display("ERROR: Flit count tracker overflow in module %m.");
	
     end
   
   // synopsys translate_on
   
   assign errors[0] = error_ft_underflow;
   assign errors[1] = error_ft_overflow;
   
endmodule
