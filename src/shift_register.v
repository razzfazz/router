module shift_register
  (clk, reset, full, data_in, push, empty, data_out, pop, error);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
   
   parameter depth = 4;
   parameter width = 8;
   
   parameter error_checker_mode = 1;
   parameter error_capture_mode = 0;
   parameter error_recovery = 0;
   
   parameter reset_type = reset_type_async;
   
   localparam [0:depth] insert_ptr_init = {{depth{1'b0}}, 1'b1};
   
   
   input clk;
   input reset;
   
   output full;
   input [0:width-1] data_in;
   input push;
   
   output empty;
   output [0:width-1] data_out;
   input pop;
   
   output error;
   
   wire full;
   wire empty;
   wire [0:width-1] data_out;
   
   wire 	    error;
   
   
   wire [0:(depth+1)*width-1] data;
   
   wire 		      insert_ptr_bad;
   wire [0:depth] 	      insert_ptr_s, insert_ptr_q;
   wire [0:1] 		      insert_ptr_sel;
   assign insert_ptr_sel = {push, pop};
   wire [0:depth] 	      insert_ptr_left;
   assign insert_ptr_left = {insert_ptr_q[1:depth], 1'b0};
   wire [0:depth] 	      insert_ptr_right;
   assign insert_ptr_right = {1'b0, insert_ptr_q[0:depth-1]};
   wire [0:depth] 	      insert_ptr_next;
   mux_nto1
     #(.width(depth+1),
       .num_ports(4))
   insert_ptr_next_mux
     (.select(insert_ptr_sel),
      .data_in({insert_ptr_q, insert_ptr_right, insert_ptr_left, insert_ptr_q}),
      .data_out(insert_ptr_next));
   assign insert_ptr_s = (error_recovery && insert_ptr_bad) ?
			 insert_ptr_init :
			 insert_ptr_next;
   dff
     #(.width(depth+1),
       .reset_type(reset_type),
       .reset_value(insert_ptr_init))
   insert_ptrq
     (.clk(clk),
      .reset(reset),
      .d(insert_ptr_s),
      .q(insert_ptr_q));
   
   assign full = insert_ptr_q[0];
   assign empty = insert_ptr_q[depth];
   
   assign insert_ptr_bad = ~^insert_ptr_q;
   
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
   
   wire 		    error_underflow;
   assign error_underflow = empty & pop;

   wire 		    error_overflow;
   assign error_overflow = full & push;

   wire 		    error_bad_ptr;
   assign error_bad_ptr = insert_ptr_bad;
   
   wire [0:2] 		    errors_in, errors_out;
   assign errors_in = {error_underflow,
		       error_overflow,
		       error_bad_ptr};
   checker
     #(.num_errors(3),
       .checker_mode(error_checker_mode),
       .capture_mode(error_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out;
   
endmodule
