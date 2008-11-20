$Id$
// module for reversing a set of bits
module reversor
  (data_in, data_out);

   // width of input word
   parameter width = 32;
   
   // input word
   input [0:width-1] data_in;
   
   // result
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   generate   
      
      genvar 	   i;
      for(i = 0; i < width; i = i + 1)
	begin:connect
	   
	   // reverse inputs data
	   assign data_out[i] = data_in[(width-1)-i];
	   
	end
      
   endgenerate
   
endmodule
