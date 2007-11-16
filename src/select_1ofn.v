module select_1ofn
  #(  parameter num_ports = 4,
      parameter width = 32)
   (   input [0:num_ports-1] select,
       input [0:width-1] data_in[0:num_ports-1],
       output [0:width-1] data_out);

   wire [0:num_ports-1] data_transposed[0:width-1];
   
   genvar i, j;
   
   generate
   for(i = 0; i < width; i = i + 1)
     begin:width_loop
	for(j = 0; j < num_ports; j = j + 1)
	  begin:ports_loop
	     assign data_transposed[i][j] = data[j][i];
	  end
	assign 	    data_out[i] = |data_transposed[i];
     end
   endgenerate

endmodule
