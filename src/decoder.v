module decoder
  #(parameter num_ports = 8)
   (data_in, data_out);

`include "functions.v"
   
   localparam width = clogb(num_ports);
   
   input [0:width-1] data_in;
   output wire [0:num_ports-1] data_out;
   
   generate
      
      genvar 		       position;
      for(position = 0; position < num_ports; position = position + 1)
	begin:positions
	   assign data_out[position] = (data_in == position);
	end
   
   endgenerate
   
endmodule
