$Id$
// interleave a given number of blocks of bits
// (a0 a1 a1 b0 b1 b2 c0 c1 c2) -> (a0 b0 c0 a1 b1 c1 a2 b2 c2)
module interleaver
  (data_in, data_out);
   
   // input data width
   parameter width = 8;
   
   // number of blocks in input data
   parameter num_blocks = 2;
   
   // width of each block
   localparam step = width / num_blocks;
   
   // vector of input data
   input [0:width-1] data_in;
   
   // vector of output data
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   generate
      
      genvar 	    i;
      for(i = 0; i < step; i = i + 1)
	begin:blocks
	   
	   genvar j;
	   for(j = 0; j < num_blocks; j = j + 1)
	     begin:bits
		assign data_out[i*num_blocks+j] = data_in[i+j*step];
	     end
	   
	end
      
   endgenerate
   
endmodule
