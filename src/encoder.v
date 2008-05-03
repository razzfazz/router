module encoder
  #(parameter num_ports = 8)
   (data_in, data_out);

`include "functions.v"
   
   localparam width = clogb(num_ports);
   
   input [0:num_ports-1] data_in;
   output wire [0:width-1] data_out;
   
   generate

      genvar level;
      for(level = 0; level < width; level = level + 1)
	begin:levels
	   wire [0:num_ports-1] bits;
	   genvar position;
	   for(position = 0; position < num_ports; position = position + 1)
	     begin:positions
		if(position & (1 << level))
		  assign bits[position] = data_in[position];
		else
		  assign bits[position] = 1'b0;
	     end
	   assign data_out[(width-1)-level] = |bits;
	end
   
   endgenerate
   
endmodule
