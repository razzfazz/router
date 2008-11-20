// $Id$
// error checker module
module checker
  (clk, reset, errors_in, errors_out);
   
`include "constants.v"
   
   // number of error inputs
   parameter num_errors = 1;
   
   // enable error checking
   parameter enable = 1;
   
   // select mode of operation
   parameter capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;

   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   input clk;
   input reset;

   // raw error inputs
   input [0:num_errors-1] errors_in;
   
   // registered and potentially held error outputs
   output [0:num_errors-1] errors_out;
   wire [0:num_errors-1] errors_out;
   
   generate
      
      if(enable > 0)
	begin
	   wire [0:num_errors-1] errors_s, errors_q;
	   case(capture_mode)
	     `CHECKER_CAPTURE_MODE_NO_HOLD:
	       begin
		  assign errors_s = errors_in;
	       end
	     `CHECKER_CAPTURE_MODE_HOLD_FIRST:
	       begin
		  wire [0:num_errors-1] mask;
		  assign mask = ~{num_errors{|errors_q}};
		  assign errors_s = errors_q | (mask & errors_in);
	       end
	     `CHECKER_CAPTURE_MODE_HOLD_ALL:
	       begin
		  assign errors_s = errors_q | errors_in;
	       end
	   endcase
	   dff
	     #(.width(num_errors),
	       .reset_type(reset_type))
	   errorsq
	     (.clk(clk),
	      .reset(reset),
	      .d(errors_s),
	      .q(errors_q));
	   
	   assign errors_out = errors_q;
	end
      else
	begin
	   assign errors_out = {num_errors{1'b0}};
	end
      
   endgenerate
   
endmodule
