module interleaver
  #(
    parameter width = 8,
    parameter num_blocks = 2
    )
   (
    input [0:width-1] data_in,
    output [0:width-1] data_out
    );
   
   localparam step = width/num_blocks;
   
   genvar i, j;
   
   generate
      for(i = 0; i < width / num_blocks; i = i + 1)
	begin:blocks
	   for(j = 0; j < num_blocks; j = j + 1)
	     begin:bits
		assign data_out[i*num_blocks+j] = data_in[i+j*step];
	     end
	end
   endgenerate
   
endmodule