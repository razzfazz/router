// replicate each bit in a vector a number of times
// (abc) --> (aaabbbccc)
module replicator
  (data_in, data_out);
   
   // width of input vector
   parameter width = 32;
   
   // how many times to replicate each bit
   parameter count = 2;
   
   // input data
   input [0:width-1] data_in;
   
   // result
   output [0:count*width-1] data_out;
   wire [0:count*width-1] data_out;
   
   generate
      genvar 		  idx;
      for(idx = 0; idx < width; idx = idx + 1)
	begin:idxs
	   assign data_out[idx*count:(idx+1)*count-1] = {count{data_in[idx]}};
	end
   endgenerate
   
endmodule
