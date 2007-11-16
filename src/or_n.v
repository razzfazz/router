module or_n
  #(
    parameter width = 1,
    parameter inputs = 2
    )
   (
    input [0:width*inputs-1] data_in,
    output [0:width-1] data_out
    )

    genvar i;
    generate
       for(i = 0; i < width; i = i + 1)
	 begin:bit_positions
	    wire [0:inputs-1] data;
	    genvar 	      j;
	    for(j = 0; j < inputs; j = j + 1)
	      begin:input_ports
		 data[j] = data_in[j*width+i];
	      end
	    data_out[i] = |data;
	 end
    endgenerate

endmodule