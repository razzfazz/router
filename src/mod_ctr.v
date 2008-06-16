module mod_ctr
  (clk, reset, incr, value, next_value);
   
   parameter num_values = 8;
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
`include "functions.v"
   
   localparam width = clogb(num_values);

   input clk;
   input reset;

   input incr;

   output [0:width-1] value;
   output [0:width-1] next_value;

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
