module checker
  (clk, reset, errors_in, errors_out);
   
   // number of error inputs
   parameter num_errors = 1;
   
   /*
    0: disable checker
    1: enable checker in simulation only
    2: enable checker in simulation and synthesis
    */
   parameter checker_mode = 1;
   
   /*
    0: do not capture (hold) errors
    1: capture (hold) first error only
    2: capture (hold) all errors
    */
   parameter capture_mode = 0;

`include "constants.v"
   
   parameter reset_type = reset_type_async;
   
   
   input clk;
   input reset;
   
   input [0:num_errors-1] errors_in;
   output [0:num_errors-1] errors_out;
   
   wire [0:num_errors-1] errors_out;
   
   generate
      
      case(checker_mode)
	1:
	  begin
	     // synopsys translate_off
	     wire [0:num_errors-1] errors_s, errors_q;
	     case(capture_mode)
	       0:
	       begin
		  assign errors_s = errors_in;
	       end
	       1:
		 begin
		    wire [0:num_errors-1] mask;
		    assign mask = ~{num_errors{|errors_q}};
		    assign errors_s = errors_q | (mask & errors_in);
		 end
	       2:
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
	     // synopsys translate_on
	  end
	2:
	  begin
	     wire [0:num_errors-1] errors_s, errors_q;
	     case(capture_mode)
	       0:
	       begin
		  assign errors_s = errors_in;
	       end
	       1:
		 begin
		    wire [0:num_errors-1] mask;
		    assign mask = ~{num_errors{|errors_q}};
		    assign errors_s = errors_q | (mask & errors_in);
		 end
	       2:
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
	  end
	endcase
      
   endgenerate
   
endmodule
