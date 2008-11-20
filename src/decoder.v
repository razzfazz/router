// $Id$
// decoder from binary to one-hot
module decoder
  (data_in, data_out);
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of output ports (i.e., width of decoded word)
   parameter num_ports = 8;
   
   localparam width = clogb(num_ports);
   
   // encoded input data
   input [0:width-1] data_in;
   
   // decoded output data
   output [0:num_ports-1] data_out;
   wire [0:num_ports-1] data_out;
   
   generate
      
      genvar 		position;
      for(position = 0; position < num_ports; position = position + 1)
	begin:positions
	   assign data_out[position] = (data_in == position);
	end
      
   endgenerate
   
endmodule
