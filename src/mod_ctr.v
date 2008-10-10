// modulo counter (i.e., counter with wraparound)
module mod_ctr
  (clk, reset, incr, value, next_value);

`include "constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of counter values (0..num_values-1)
   parameter num_values = 8;
   
   // width of counter state
   localparam width = clogb(num_values);
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // increment the counter value
   input incr;

   // current counter value
   output [0:width-1] value;
   wire [0:width-1] value;
   
   // next counter value (i.e., (value+1) mod num_values)
   output [0:width-1] next_value;
   wire [0:width-1] next_value;
   
   wire [0:width-1] value_s, value_q, value_next;
   
   generate
      
      if((2 ** width) == num_values)
	// in this case, we have natural wraparound
	assign value_next = value_q + 1'b1;
      else
	// here we need explicit wraparound
	assign value_next = (value_q == num_values - 1) ?
			    {width{1'b0}} :
			    (value_q + 1'b1);
      
   endgenerate
   
   assign value_s = incr ? value_next : value_q;
   
   dff
     #(.width(width),
       .reset_type(reset_type))
   valueq
     (.clk(clk),
      .reset(reset),
      .d(value_s),
      .q(value_q));
   
   assign value = value_q;
   assign next_value = value_next;
   
endmodule
