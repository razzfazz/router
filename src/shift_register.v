module shift_register
  (clk, reset, full, data_in, push, empty, data_out, pop);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
   
   parameter depth = 4;
   parameter width = 8;
   parameter reset_type = reset_type_async;
   
   
   input clk;
   input reset;
   
   output full;
   input [0:width-1] data_in;
   input push;
   
   output empty;
   output [0:width-1] data_out;
   input pop;
   
   wire full;
   wire empty;
   wire [0:width-1] data_out;
   
   wire [0:(depth+1)*width-1] data;
   
   wire [0:depth] 	      insert_ptr_q;
   wire 		      insert_ptr_bad;
   assign insert_ptr_bad = ~^insert_ptr_q;
   
   wire [0:depth] 	      insert_ptr_s;
   assign insert_ptr_s = insert_ptr_bad ? {{depth-1{1'b0}}, 1'b1} :
			 (push & ~pop) ? {insert_ptr_q[1:depth], 1'b0} :
			 (pop & ~push) ? {1'b0, insert_ptr_q[0:depth-1]} :
			 insert_ptr_q;
   dff
     #(.width(depth+1),
       .reset_type(reset_type))
   insert_ptrq
     (.clk(clk),
      .reset(reset),
      .d(insert_ptr_s),
      .q(insert_ptr_q));
   
   assign full = insert_ptr_q[0];
   assign empty = insert_ptr_q[depth];
   
   generate
      
      genvar 		      level;
      for(level = 0; level < depth; level = level + 1)
	begin:levels
	   
	   wire capture;
	   assign capture
	     = push & (pop ? insert_ptr_q[level] : insert_ptr_q[level+1]);
	   
	   wire shift;
	   assign shift = pop;
	   
	   wire [0:width-1] data_s, data_q;
	   assign data_s = capture ?
			   data_in :
			   shift ?
			   data[level*width:(level+1)*width-1] :
			   data_q;
	   dff
	     #(.width(width),
	       .reset_type(reset_type))
	   dataq
	     (.clk(clk),
	      .reset(reset),
	      .d(data_s),
	      .q(data_q));
	   assign data[(level+1)*width:(level+2)*width-1] = data_q;
	   
	end
      
   endgenerate
   
   assign data_out = data[depth*width:(depth+1)*width-1];
   
endmodule
