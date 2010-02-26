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



// generic FIFO buffer built from registers
module c_fifo
  (clk, reset, active, almost_full, full, write_data, push, almost_empty, empty,
   read_data, peek_data, pop, errors);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // number of entries
   parameter depth = 4;
   
   // width of each entry
   parameter width = 8;
   
   // select implementation variant
   parameter fifo_type = `FIFO_TYPE_INDEXED;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required for insertion pointer
   localparam insert_ptr_width = clogb(depth+1);
   
   // reset value for insertion pointer
   localparam [0:insert_ptr_width-1] insert_ptr_reset_value = depth;
   
   // width required for read/write pointers
   localparam rw_ptr_width = clogb(depth);
   
   input clk;
   input reset;
   input active;
   
   // a single entry is not occupied
   output almost_full;
   wire almost_full;
   
   // all entries occupied
   output full;
   wire full;
   
   // input data
   input [0:width-1] write_data;
   
   // write data from write_data into shift register
   input push;
   
   // a single entry is occupied
   output almost_empty;
   wire almost_empty;
   
   // no entries are occupied
   output empty;
   wire empty;
   
   // output data (head element)
   output [0:width-1] read_data;
   wire [0:width-1] read_data;
   
   // output data (next element)
   output [0:width-1] peek_data;
   wire [0:width-1] peek_data;
   
   // remove head element from shift register
   input pop;
   
   // internal error condition detected
   output [0:1] errors;
   wire [0:1] 	    errors;
   
   genvar 	    level;
   
   generate
      
      case(fifo_type)
	
	`FIFO_TYPE_SHIFTING:
	  begin
	     
	     wire [0:insert_ptr_width-1] insert_ptr_q, insert_ptr_next;
	     c_incr
	       #(.width(insert_ptr_width),
		 .min_value(0),
		 .max_value(depth))
	     insert_ptr_incr
	       (.data_in(insert_ptr_q),
		.data_out(insert_ptr_next));
	     
	     wire [0:insert_ptr_width-1] insert_ptr_prev;
	     c_decr
	       #(.width(insert_ptr_width),
		 .min_value(0),
		 .max_value(depth))
	     insert_ptr_decr
	       (.data_in(insert_ptr_q),
		.data_out(insert_ptr_prev));
	     
	     wire [0:4*insert_ptr_width-1] insert_ptr_values;
	     assign insert_ptr_values = {insert_ptr_q,
					 insert_ptr_next,
					 insert_ptr_prev,
					 insert_ptr_q};
	     
	     wire [0:1] 		   insert_ptr_sel;
	     assign insert_ptr_sel = {push, pop};
	     
	     wire [0:insert_ptr_width-1]   insert_ptr_s;
	     assign insert_ptr_s
	       = insert_ptr_values[insert_ptr_sel*insert_ptr_width +:
				   insert_ptr_width];
	     c_dff
	       #(.width(insert_ptr_width),
		 .reset_type(reset_type),
		 .reset_value(insert_ptr_reset_value))
	     insert_ptrq
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.d(insert_ptr_s),
		.q(insert_ptr_q));
	     
	     assign almost_full = (insert_ptr_q == 1);
	     assign full = ~|insert_ptr_q;
	     
	     assign almost_empty = (insert_ptr_q == (depth - 1));
	     
	     wire 			   empty_s, empty_q;
	     assign empty_s
	       = (empty_q | (almost_empty & pop & ~push)) & ~(push & ~pop);
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type),
		 .reset_value(1'b1))
	     emptyq
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.d(empty_s),
		.q(empty_q));
	     
	     assign empty = empty_q;
	     
	     wire [0:(depth+1)*width-1]    data;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:levels
		  
		  wire capture;
		  assign capture = push && (level + 1 == insert_ptr_q + pop);
		  
		  wire shift;
		  assign shift = pop;
		  
		  wire [0:width-1] data_s;
		  assign data_s = capture ? 
				  write_data : 
				  data[level*width:(level+1)*width-1];
		  
		  reg [0:width-1] data_q;
		  always @(posedge clk)
		    if(active)
		      if(capture | shift)
			data_q <= data_s;
		  
		  assign data[(level+1)*width:(level+2)*width-1] = data_q;
		  
	       end
	     
	     assign read_data = data[depth*width:(depth+1)*width-1];
	     assign peek_data = data[(depth-1)*width:depth*width-1];
	     
	     wire 		   error_underflow;
	     assign error_underflow = empty & pop & ~push;
	     
	     wire 		   error_overflow;
	     assign error_overflow = full & push & ~pop;
	     
	     assign errors = {error_underflow, error_overflow};
	     
	  end
	
	`FIFO_TYPE_INDEXED:
	  begin
	     
	     wire [0:rw_ptr_width-1] write_ptr, read_ptr, peek_ptr;
	     c_fifo_ctrl
	       #(.addr_width(rw_ptr_width),
		 .offset(0),
		 .depth(depth),
		 .reset_type(reset_type))
	     ctrl
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.push(push),
		.pop(pop),
		.write_addr(write_ptr),
		.read_addr(read_ptr),
		.peek_addr(peek_ptr),
		.almost_empty(almost_empty),
		.empty(empty),
		.almost_full(almost_full),
		.full(full),
		.errors(errors));
	     
	     reg [0:width-1] 	     storage [0:depth-1];
	     
	     always @(posedge clk)
	       if(active)
		 if(push)
		   storage[write_ptr] <= write_data;
	     
	     assign read_data = storage[read_ptr];
	     assign peek_data = storage[peek_ptr];
	     
	  end
	
      endcase
      
      // synopsys translate_off
      if(depth < 2)
	begin
	   initial
	   begin
	      $display({"ERROR: The FIFO module must have a depth of at least ",
			"two entries."});
	      $stop;
	   end
	end
      // synopsys translate_on
      
   endgenerate
   
endmodule
