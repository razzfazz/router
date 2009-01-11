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

// generic FIFO buffer built from registers
module fifo
  (clk, reset, full, data_in, push, empty, data_out, pop, error);
   
`include "constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of entries
   parameter depth = 4;
   
   // width of each entry
   parameter width = 8;
   
   // select implementation variant
   parameter fifo_type = `FIFO_TYPE_INDEXED;
   
   // include checker logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required for insertion pointer
   localparam insert_ptr_width = clogb(depth+1);
   
   // reset value for insertion pointer
   localparam [0:insert_ptr_width-1] insert_ptr_reset_value = depth;
   
   // width required for read/write pointers
   localparam rw_ptr_width = clogb(depth);
   
   input clk;
   input reset;
   
   // all entries occupied
   output full;
   wire full;
   
   // input data
   input [0:width-1] data_in;
   
   // write data from data_in into shift register
   input push;
   
   // no entries occupied
   output empty;
   wire empty;
   
   // output data (head element)
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   // remove head element from shift register
   input pop;
   
   // internal error condition detected
   output error;
   wire 	    error;
   
   genvar 	    level;
   
   generate
      
      case(fifo_type)
	`FIFO_TYPE_SHIFTING:
	  begin
	     
	     wire [0:insert_ptr_width-1] insert_ptr_q, insert_ptr_next;
	     incr
	       #(.width(insert_ptr_width),
		 .min_value(0),
		 .max_value(depth-1))
	     insert_ptr_incr
	       (.data_in(insert_ptr_q),
		.data_out(insert_ptr_next));
	     
	     wire [0:insert_ptr_width-1] insert_ptr_prev;
	     decr
	       #(.width(insert_ptr_width),
		 .min_value(0),
		 .max_value(depth-1))
	     insert_ptr_decr
	       (.data_in(insert_ptr_q),
		.data_out(insert_ptr_prev));
	     
	     wire [0:insert_ptr_width-1] insert_ptr_s;
	     mux_nto1
	       #(.num_ports(4),
		 .width(insert_ptr_width))
	     insert_ptr_s_mux
	       (.select({push, pop}),
		.data_in({insert_ptr_q,
			  insert_ptr_prev,
			  insert_ptr_next,
			  insert_ptr_q}),
		.data_out(insert_ptr_s));
	     dff
	       #(.width(insert_ptr_width),
		 .reset_type(reset_type),
		 .reset_value(insert_ptr_reset_value))
	     insert_ptrq
	       (.clk(clk),
		.reset(reset),
		.d(insert_ptr_s),
		.q(insert_ptr_q));
	     
	     assign full = ~|insert_ptr_q;
	     
	     wire 			 almost_empty;
	     assign almost_empty = (insert_ptr_q == (depth - 1));
	     
	     wire 			 empty_s, empty_q;
	     assign empty_s
	       = (empty_q | (almost_empty & pop & ~push)) & ~(push & ~pop);
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     emptyq
	       (.clk(clk),
		.reset(reset),
		.d(empty_s),
		.q(empty_q));
	     
	     assign empty = empty_q;
	     
	     wire [0:(depth+1)*width-1] data;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:shifting_levels
		  
		  wire capture;
		  assign capture = push && (level + 1 == insert_ptr_q + pop);
		  
		  wire shift;
		  assign shift = pop;
		  
		  reg [0:width-1] data_q;
		  wire [0:width-1] data_s;
		  assign data_s = capture ?
				  data_in :
				  shift ?
				  data[level*width:(level+1)*width-1] :
				  data_q;
		  
		  always @(posedge clk)
		    data_q <= data_s;
		  
		  assign data[(level+1)*width:(level+2)*width-1] = data_q;
		  
	       end
	     
	     assign data_out = data[depth*width:(depth+1)*width-1];
	     
	     wire 		   error_underflow;
	     assign error_underflow = empty & pop & ~push;
	     
	     wire 		   error_overflow;
	     assign error_overflow = full & push & ~pop;
	     
	     wire [0:1] 	   errors_in, errors_out;
	     assign errors_in = {error_underflow,
				 error_overflow};
	     checker
	       #(.num_errors(2),
		 .enable(checker_enable),
		 .capture_mode(checker_capture_mode),
		 .reset_type(reset_type))
	     chk
	       (.clk(clk),
		.reset(reset),
		.errors_in(errors_in),
		.errors_out(errors_out));
	     
	     assign error = |errors_out;
	     
	  end
	`FIFO_TYPE_INDEXED:
	  begin

	     wire [0:rw_ptr_width-1] read_ptr, write_ptr;
	     fifo_ctrl
	       #(.addr_width(rw_ptr_width),
		 .offset(0),
		 .depth(depth),
		 .checker_enable(checker_enable),
		 .checker_capture_mode(checker_capture_mode),
		 .reset_type(reset_type))
	     ctrl
	       (.clk(clk),
		.reset(reset),
		.push(push),
		.pop(pop),
		.write_addr(write_ptr),
		.read_addr(read_ptr),
		.empty(empty),
		.full(full),
		.error(error));
	     
	     reg [0:width-1] 	     storage [0:depth-1];
	     
	     always @(posedge clk)
	       if(push)
		 storage[write_ptr] <= data_in;
	     
	     assign data_out = storage[read_ptr];
	     
	  end
      endcase
      
   endgenerate
   
endmodule
