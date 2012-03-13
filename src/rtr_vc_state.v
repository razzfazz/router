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
// VC state tracking module
//==============================================================================

module rtr_vc_state
  (clk, reset, active, flit_sent, flit_tail, fc_event_valid, fc_active, elig, 
   empty, almost_full, full, errors);
   
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
   
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask = `ELIG_MASK_NONE;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
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
   
   // activate flow control input logic
   output fc_active;
   wire   fc_active;
   
   // VC is eligible for allocation
   output elig;
   wire   elig;
   
   // VC is empty
   output empty;
   wire   empty;

   // VC has one slot left
   output almost_full;
   wire   almost_full;
   
   // VC is full
   output full;
   wire   full;
   
   // internal error condition detected
   output [0:1] errors;
   wire [0:1] 	errors;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------

   rtr_fc_state
     #(.num_flits_per_vc(num_flits_per_vc),
       .flow_ctrl_type(flow_ctrl_type),
       .flow_ctrl_bypass(flow_ctrl_bypass),
       .reset_type(reset_type))
   fcs
     (.clk(clk),
      .reset(reset),
      .active(active),
      .flit_sent(flit_sent),
      .fc_event_valid(fc_event_valid),
      .fc_active(fc_active),
      .empty(empty),
      .almost_full(almost_full),
      .full(full),
      .full_prev(),
      .errors(errors));
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently in use
   //---------------------------------------------------------------------------
   
   // NOTE: For the reset condition, we don't have to worry about whether or
   // not sufficient buffer space is available: If the VC is currently 
   // allocated, these checks would already have been performed at the 
   // beginning of switch allocation; on the other hand, if it is not currently 
   // allocated, 'allocated_q' is zero, and thus the reset condition does not 
   // have any effect.
   
   wire allocated;
   
   wire allocated_s, allocated_q;
   assign allocated_s = allocated;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(allocated_s),
      .q(allocated_q));
   
   assign allocated = flit_sent ? ~flit_tail : allocated_q;
   
   generate
      
      case(elig_mask)
	
	`ELIG_MASK_NONE:
	  assign elig = ~allocated;
	
	`ELIG_MASK_FULL:
	  assign elig = ~allocated & ~full;
	
	`ELIG_MASK_USED:
	  assign elig = ~allocated & empty;
	
      endcase
      
   endgenerate
   
endmodule
