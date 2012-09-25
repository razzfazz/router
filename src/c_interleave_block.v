module c_interleave_block
  (data_in, data_out);
   
   // input data width
   parameter width 	 = 8;

   // number of blocks in input data
   parameter num_blocks  = 2;

   //section width
   parameter chunk_size = 2;
   
   // width of each block
   localparam step 	 = width / (num_blocks*chunk_size);
   
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
		assign data_out[i*chunk_size + j*step*chunk_size +:chunk_size] = 
		   data_in[i*num_blocks*chunk_size + j*chunk_size+:chunk_size];
	     end
	   
	end
      
   endgenerate
   
endmodule
