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



// module for tracking state of a FIFO
module c_fifo_tracker
  (clk, reset, active, push, pop, almost_empty, empty, almost_full, full, 
   free, errors);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // total number of credits available
   parameter depth = 8;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required to select an individual credit
   localparam idx_width = clogb(depth);
   
   // synopsys translate_off
   
   // width required to represent full range of credit count (0..depth)
   localparam free_width = clogb(depth+1);
   
   // synopsys translate_on
   
   input clk;
   input reset;
   input active;
   
   // add an entry
   input push;
   
   // remove an entry
   input pop;
   
   // all but one entries free
   output almost_empty;
   wire   almost_empty;
   
   // all entries free
   output empty;
   wire   empty;
   
   // all but one entries occupied
   output almost_full;
   wire   almost_full;
   
   // all entries occupied
   output full;
   wire   full;
   
   // number of free entries
   output [0:free_width-1] free;
   wire [0:free_width-1]   free;
   
   // internal error condition encountered
   output [0:1] 	   errors;
   wire [0:1] 		   errors;
   
   wire 		   full_push;
   wire 		   full_nopush;
   
   wire 		   full_s, full_q;
   assign full_s = push ? full_push : full_nopush;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   fullq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(full_s),
      .q(full_q));
   
   assign full = full_q;
   
   wire 		   error_underflow;
   wire 		   error_overflow;
   
   generate
      
      // if we only have a single entry, we don't need an explicit counter
      if(depth == 1)
	begin
	   
	   assign full_push = full_q | ~pop;
	   assign full_nopush = full_q & ~pop;
	   
	   assign error_underflow = push & ~pop & full_q;
	   assign error_overflow = pop & ~push & ~full_q;
	   
	   assign almost_full = ~full_q;
	   assign almost_empty = full_q;
	   assign empty = ~full_q;
	   
	   assign free = ~full_q;
	   
	end
      
      // if we have more than one entry, we need an extra counter to keep track
      else if(depth > 1)
	begin
	   
	   wire [0:idx_width-1] free_count_q;
	   wire 		free_count_zero;
	   assign free_count_zero = ~|free_count_q;
	   
	   wire 		decr_free_count;
	   assign decr_free_count = ~pop & ~free_count_zero;
	   
	   wire [0:idx_width-1] free_count_push;
	   assign free_count_push = free_count_q - decr_free_count;
	   
	   wire 		incr_free_count;
	   assign incr_free_count = pop & ~full_q;
	   
	   wire [0:idx_width-1] free_count_nopush;
	   assign free_count_nopush = free_count_q + incr_free_count;
	   
	   wire [0:idx_width-1] free_count_s;
	   assign free_count_s = push ? free_count_push : free_count_nopush;
	   c_dff
	     #(.width(idx_width),
	       .reset_type(reset_type),
	       .reset_value(depth-1))
	   free_countq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(free_count_s),
	      .q(free_count_q));
	   
	   assign full_push = free_count_zero & (full_q | ~pop);
	   assign full_nopush = full_q & ~pop;
	   
	   wire 		free_count_max;
	   assign free_count_max = (free_count_q == (depth - 1));
	   
	   assign error_underflow = push & ~pop & full_q;
	   assign error_overflow = pop & ~push & free_count_max;
	   
	   assign almost_full = free_count_zero & ~full_q;
	   
	   if(depth == 2)
	     assign almost_empty = almost_full;
	   else
	     assign almost_empty = (free_count_q == (depth - 2));
	   
	   assign empty = free_count_max;

	   if(depth == 2)
	     assign free = {free_count_q, ~free_count_q & full_q};
	   else
	     assign free = free_count_q + !full_q;
	   
	end
      
      // synopsys translate_off
      
      else
	begin
	   initial
	   begin
	      $display({"ERROR: FIFO tracker module %m requires a depth of at ",
			"least one entry."});
	      $stop;
	   end
	end
      
      // synopsys translate_on
      
   endgenerate
   
   assign errors = {error_underflow, error_overflow};
   
endmodule
