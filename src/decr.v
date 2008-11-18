// generic modulo decrementer (i.e., decrementer with wraparound)
module decr
  (data_in, data_out);
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   parameter width = 3;
   
   parameter [0:width-1] min_value = 0;
   parameter [0:width-1] max_value = (1 << width) - 1;
   
   localparam num_values = max_value - min_value + 1;
   
   localparam cwidth = clogb(num_values);
   
   // operand inputs
   input [0:width-1] data_in;
   
   // sum output
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   wire 	    carry;
   assign carry = ~|data_in[(width-cwidth):width-1];
   
   wire 	    wrap;
   assign wrap = (data_in[(width-cwidth):width-1] ==
		  min_value[(width-cwidth):width-1]);
   
   generate
      
      if((1 << cwidth) == num_values)
	begin
	   
	   // if the range is a power of two, we can take advantage of natural
	   // wraparound for the LSBs
	   assign data_out[(width-cwidth):width-1]
		    = data_in[(width-cwidth):width-1] - 1'b1;
	   
	end
      else
	begin
	   
	   // if the range is not a power of two, we need to implement 
	   // explicit wraparound
	   assign data_out[(width-cwidth):width-1]
		    = wrap ?
		      max_value[(width-cwidth):width-1] :
		      (data_in[(width-cwidth):width-1] - 1'b1);
	   
	end
      
      if(width > cwidth)
	begin
	   
	   if(min_value[0:(width-cwidth)-1] == max_value[0:(width-cwidth)-1])
	     begin
		
		// if the MSBs are identical for the first and last value, we 
		// never need to change them
		assign data_out[0:(width-cwidth)-1]
			 = data_in[0:(width-cwidth)-1];
		
	     end
	   else
	     begin
		
		// if the first and last value have differing MSBs, we need to
		// adjust them whenever either the LSBs overflow or wraparound
		// occurs
		assign data_out[0:(width-cwidth)-1]
			 = data_in[0:(width-cwidth)-1] - carry + wrap;
		
	     end
	   
	end
      
   endgenerate
   
endmodule
