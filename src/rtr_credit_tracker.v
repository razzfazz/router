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
module rtr_credit_tracker
  (clk, reset, active, debit, credit, free, free_plus1, errors);
   
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   // total number of credits available
   parameter num_credits = 8;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required for credit counter
   localparam cred_count_width = clogb(num_credits-1);
   
   // width required to represent full range of credit count (0..num_credits)
   localparam true_idx_width = clogb(num_credits+1);
   
   
   input clk;
   input reset;
   input active;
   
   // inputs for subtracting and adding credits
   input debit;
   input credit;
   
   // at least one credit available?
   output free;
   wire free;
   
   // at least two credits available?
   output free_plus1;
   wire free_plus1;
   
   // internal error condition encountered
   output [0:1] errors;
   wire [0:1] errors;
   
   
   wire       free_s, free_q;
   c_dff
     #(.width(1),
       .reset_value(1'b1),
       .reset_type(reset_type))
   freeq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(free_s),
      .q(free_q));
   
   assign free = free_q;
   
   wire       error_underflow;
   assign error_underflow = ~free_q & debit;
   
   wire       set_free;
   wire       reset_free;
   wire       error_overflow;
   
   // synopsys translate_off
   wire [0:true_idx_width-1] true_count;
   // synopsys translate_on
   
   generate
      
      // if we only have a single credit, we don't need to explicitly add a 
      // second flag and credit counter
      if(num_credits == 1)
	begin
	   
	   assign set_free = credit;
	   assign reset_free = debit;
	   assign free_s = (set_free | free_q) & ~reset_free;
	   
	   assign free_plus1 = 1'b0;
	   
	   assign error_overflow = free_q & credit;
	   
	   // synopsys translate_off
	   assign true_count = free_q;
	   // synopsys translate_on
	   
	end
      
      // if we have two or more credits, we need the second flag
      else if(num_credits > 1)
	begin
	   
	   wire free_plus1_s, free_plus1_q;
	   c_dff
	     #(.width(1),
	       .reset_value(1'b1),
	       .reset_type(reset_type))
	   free_plus1q
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(free_plus1_s),
	      .q(free_plus1_q));
	   
	   assign free_plus1 = free_plus1_q;
	   
	   wire set_free_plus1;
	   wire reset_free_plus1;
	   
	   // if we have exactly two credits, we still don't need an explicit
	   // credit counter
	   if(num_credits == 2)
	     begin
		
		assign set_free = credit & ~debit;
		assign reset_free = ~free_plus1_q & ~credit & debit;
		assign free_s = (set_free | free_q) & ~reset_free;
		
		assign set_free_plus1 = free_q & credit & ~debit;
		assign reset_free_plus1 = ~credit & debit;
		assign free_plus1_s
		  = set_free_plus1 | (free_plus1_q & ~reset_free_plus1);
		
		assign error_overflow = free_plus1_q & credit;
		
		// synopsys translate_off
		assign true_count = free_q + free_plus1_q;
		// synopssy translate_on
		
	     end
	   
	   // if we have more than two credits, we need an extra counter to 
	   // keep track of the total number of credits available
	   else
	     begin
		
		wire [0:cred_count_width-1] cred_count_q;
		
		wire 			    cred_count_zero;
		assign cred_count_zero = ~|cred_count_q;
		
		wire 			    cred_count_max;
		assign cred_count_max = (cred_count_q == (num_credits - 2));
		
		wire [0:credit_idx_width-1] cred_count_s;
		c_dff
		  #(.width(cred_count_width),
		    .reset_value(num_credits-2),
		    .reset_type(reset_type))
		cred_countq
		  (.clk(clk),
		   .reset(reset),
		   .active(active),
		   .d(cred_count_s),
		   .q(cred_count_q));
		
		assign set_free = credit;
		assign reset_free = ~free_plus1_q & ~credit & debit;
		assign free_s = (set_free | free_q) & ~reset_free;
		
		assign set_free_plus1 = free_q & credit & ~debit;
		assign reset_free_plus1 = cred_count_zero & ~credit & debit;
		assign free_plus1_s
		  = (set_free_plus1 | free_plus1_q) & ~reset_free_plus1;
		
		// if we have exactly three credits, the counter can be treated
		// as a third flag bit
		if(num_credits == 3)
		  begin
		     
		     wire set_cred_count;
		     assign set_cred_count = free_plus1_q & credit & ~debit;
		     
		     wire reset_cred_count;
		     assign reset_cred_count = debit;
		     
		     assign cred_count_s
		       = set_cred_count | (cred_count_q & ~reset_cred_count);
		     
		  end
		
		// if we have more than three credits, we need to do proper 
		// arithmetic to update the counter
		else
		  begin
		     
		     wire incr_cred_count;
		     assign incr_cred_count
		       = free_plus1_q & credit & ~debit;
		     
		     wire decr_cred_count;
		     assign decr_cred_count
		       = ~cred_count_zero & ~credit & debit;
		     
		     assign cred_count_s = credit ? 
					   (cred_count_q + incr_cred_count) :
					   (cred_count_q - decr_cred_count);
		     
		  end
		
		assign error_overflow = cred_count_max & credit;
		
		// synopsys translate_off
		assign true_count = free_q + free_plus1_q + cred_count_q;
		// synopsys translate_on
		
	     end
	   
	end
      
      // synopsys translate_off
      else
	begin
	   initial
	   begin
	      $display({"ERROR: The credit tracker module requires at least ", 
			"one credit."});
	      $stop;
	   end
	end
      // synopsys translate_on
      
   endgenerate
   
   assign errors = {error_underflow, error_overflow};
   
endmodule
