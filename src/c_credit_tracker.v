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



// module for tracking available credit in a buffer
module c_credit_tracker
  (clk, reset, active, debit, credit, free, empty, errors);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // total number of credits available
   parameter num_credits = 8;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required to select an individual credit
   localparam credit_idx_width = clogb(num_credits);
   
   // synopsys translate_off
   
   // width required to represent full range of credit count (0..num_credits)
   localparam true_idx_width = clogb(num_credits+1);
   
   // synopsys translate_on
   
   
   input clk;
   input reset;
   input active;
   
   // inputs for subtracting and adding credits
   input debit;
   input credit;
   
   // at least one credit available?
   output free;
   wire free;
   
   // all credits available?
   output empty;
   wire empty;
   
   // internal error condition encountered
   output [0:1] errors;
   wire [0:1] errors;
   
   wire       cred_debit;
   wire       cred_nodebit;
   
   wire       cred_s, cred_q;
   assign cred_s = debit ? cred_debit : cred_nodebit;
   c_dff
     #(.width(1),
       .reset_type(reset_type),
       .reset_value(1'b1))
   credq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(cred_s),
      .q(cred_q));
   
   assign free = cred_q;
   
   wire error_underflow;
   wire error_overflow;
   
   // synopsys translate_off
   
   wire [0:true_idx_width-1] true_count;
   
   // synopsys translate_on
   
   generate
      
      // if we only have a single credit, we don't need explicit credit counter
      if(num_credits == 1)
	begin
	   
	   assign cred_debit = cred_q & credit;
	   assign cred_nodebit = cred_q | credit;
	   
	   assign error_underflow = debit & ~credit & ~cred_q;
	   assign error_overflow = credit & ~debit & cred_q;
	   
	   assign true_count = cred_q;
	   
	   assign empty = cred_q;
	   
	end
      
      // if we have more than one credit, we need an extra counter to keep track
      else if(num_credits > 1)
	begin
	   
	   wire [0:credit_idx_width-1] cred_count_q;
	   wire 		       cred_count_zero;
	   assign cred_count_zero = ~|cred_count_q;
	   
	   wire 		       decr_count;
	   assign decr_count = ~credit & ~cred_count_zero;
	   
	   wire [0:credit_idx_width-1] cred_count_debit;
	   assign cred_count_debit = cred_count_q - decr_count;
	   
	   wire 		       incr_count;
	   assign incr_count = credit & cred_q;
	   
	   wire [0:credit_idx_width-1] cred_count_nodebit;
	   assign cred_count_nodebit = cred_count_q + incr_count;
	   
	   wire [0:credit_idx_width-1] cred_count_s;
	   assign cred_count_s = debit ? cred_count_debit : cred_count_nodebit;
	   c_dff
	     #(.width(credit_idx_width),
	       .reset_type(reset_type),
	       .reset_value(num_credits-1))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   assign cred_debit = ~cred_count_zero | (cred_q & credit);
	   assign cred_nodebit = cred_q | credit;
	   
	   wire 		       cred_count_max;
	   assign cred_count_max = (cred_count_q == (num_credits - 1));
	   
	   assign error_underflow = debit & ~credit & ~cred_q;
	   assign error_overflow = credit & ~debit & cred_count_max;
	   
	   assign empty = cred_count_max;
	   
	   // synopsys translate_off
	   
	   assign true_count = cred_count_q + cred_q;
	   
	   // synopsys translate_on
	   
	end
      
      // synopsys translate_off
      
      else
	begin
	   initial
	   begin
	      $display({"ERROR: Credit tracker module %m requires at least ", 
			"one credit."});
	      $stop;
	   end
	end
      
      // synopsys translate_on
      
   endgenerate
   
   assign errors = {error_underflow, error_overflow};
   
endmodule
