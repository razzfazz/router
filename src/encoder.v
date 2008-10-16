// encoder from one-hot to binary
module encoder
  (data_in, data_out);
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of input ports (i.e., decoded width)
   parameter num_ports = 8;
   
   localparam width = clogb(num_ports);
   
   // one-hot input data
   input [0:num_ports-1] data_in;
   
   // binary encoded output data
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   generate
      
      genvar 	    level;
      for(level = 0; level < width; level = level + 1)
	begin:levels
	   
	   wire [0:num_ports-1] bits;
	   
	   genvar 		position;
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
