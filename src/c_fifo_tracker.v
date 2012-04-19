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
// module for tracking state of a FIFO
//==============================================================================

module c_fifo_tracker
  (/*autoarg*/
   // Outputs
   almost_empty, empty, almost_full, full, free, errors,
   // Inputs
   clk, reset, active, push, pop
   );
   
   
`include "c_functions.v"
`include "c_constants.v"
   
   // total number of credits available
   parameter depth = 8;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required to represent full range of credit count (0..depth)
   localparam free_width = clogb(depth+1);
   
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
   
   wire [0:free_width-1]   free_s, free_q;
   c_dff
     #(.width(free_width),
       .reset_value(depth),
       .reset_type(reset_type))
   freeq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(free_s),
      .q(free_q));
   
   assign free = free_q;
   
   wire 		   error_underflow;
   assign error_underflow = empty & ~push & pop;
   
   wire 		   error_overflow;
   assign error_overflow = full & push & ~pop;
   
   generate
      
      if(depth == 1)
	begin
	   
	   assign free_s = free_q ? (~push | pop) : (~push & pop);
	   
	   assign almost_empty = ~free_q;
	   assign empty = free_q;
	   assign almost_full = free_q;
	   assign full = ~free_q;
	   
	end
      
      else if(depth > 1)
	begin
	   
	   wire decr_push;
	   assign decr_push = ~pop;
	   
	   wire [0:free_width-1] free_push;
	   assign free_push = free_q - decr_push;
	   
	   wire 		 incr_nopush;
	   assign incr_nopush = pop;
	   
	   wire [0:free_width-1] free_nopush;
	   assign free_nopush = free_q + incr_nopush;
	   
	   assign free_s = push ? free_push : free_nopush;
	   
	   wire 		 free_max;
	   assign free_max = (free_q == depth);
	   
	   wire 		 next_almost_empty;
	   assign next_almost_empty = (free_q == (depth - 2));
	   
	   wire 		 almost_empty_s, almost_empty_q;
	   assign almost_empty_s = (almost_empty & ~(push ^ pop)) | 
				   (next_almost_empty & (~push & pop)) | 
				   (free_max & (push & ~pop));
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   almost_emptyq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(almost_empty_s),
	      .q(almost_empty_q));
	   
	   assign almost_empty = almost_empty_q;
	   
	   wire 		 next_empty;
	   assign next_empty = (free_q == (depth - 1));
	   
	   wire 		 empty_s, empty_q;
	   assign empty_s = (empty & ~(push & ~pop)) |
			    (next_empty & (~push & pop));
	   c_dff
	     #(.width(1),
	       .reset_value(1'b1),
	       .reset_type(reset_type))
	   emptyq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(empty_s),
	      .q(empty_q));
	   
	   assign empty = empty_q;
	   
	   wire 		 free_zero;
	   assign free_zero = ~|free_q;
	   
	   if(depth == 2)
	     assign almost_full = almost_empty;
	   else if(depth > 2)
	     begin
		
		wire next_almost_full;
		assign next_almost_full = (free_q == 2);
		
		wire almost_full_s, almost_full_q;
		assign almost_full_s = (almost_full & ~(push ^ pop)) |
				       (next_almost_full & (push & ~pop)) |
				       (free_zero & (~push & pop));
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		almost_fullq
		  (.clk(clk),
		   .reset(reset),
		   .active(active),
		   .d(almost_full_s),
		   .q(almost_full_q));
		
		assign almost_full = almost_full_q;
		
	     end
	   
	   wire      next_full;
	   assign next_full = (free_q == 1);

	   wire      full_s, full_q;
	   assign full_s = (full & ~(~push & pop)) | 
			   (next_full & (push & ~pop));
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
