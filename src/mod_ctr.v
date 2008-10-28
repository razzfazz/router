// modulo counter (i.e., counter with wraparound)
module mod_ctr
  (clk, reset, incr, decr, load, load_value, value, early_value, next_value,
   prev_value);

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
   
   // reset value for counter
   parameter [0:width-1] reset_value = {width{1'b0}};
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // increment the counter value
   input incr;
   
   // decrement the counter value
   input decr;
   
   // load counter with value specified in load_value
   input load;
   
   // value to be loaded into counter when load=1
   input [0:width-1] load_value;
   
   // current counter value
   output [0:width-1] value;
   wire [0:width-1] value;
   
   // next cycle's counter value
   output [0:width-1] early_value;
   wire [0:width-1] early_value;
   
   // next counter value (i.e., (value+1) mod num_values)
   output [0:width-1] next_value;
   wire [0:width-1] next_value;
   
   // previous counter value (i.e., (value-1) mod num_values)
   output [0:width-1] prev_value;
   wire [0:width-1] prev_value;
   
   wire [0:width-1] value_s, value_q, value_next, value_prev;
   
   generate
      
      if((2 ** width) == num_values)
	begin
	   
	   // in this case, we have natural wraparound
	   assign value_next = value_q + 1'b1;
	   assign value_prev = value_q - 1'b1;
	   
	end
      else
	begin
	   
	   // here we need explicit wraparound
	   assign value_next = (value_q == num_values - 1) ?
			       {width{1'b0}} :
			       (value_q + 1'b1);
	   assign value_prev = (value_q == 0) ?
			       (num_values - 1) :
			       (value_q - 1'b1);
	   
	end
      
   endgenerate
   
   assign value_s = load ? load_value :
		    (incr & ~decr) ? value_next :
		    (decr & ~incr) ? value_prev :
		    value_q;
   dff
     #(.width(width),
       .reset_type(reset_type),
       .reset_value(reset_value))
   valueq
     (.clk(clk),
      .reset(reset),
      .d(value_s),
      .q(value_q));
   
   assign value = value_q;
   assign early_value = value_s;
   assign next_value = value_next;
   assign prev_value = value_prev;
   
endmodule
