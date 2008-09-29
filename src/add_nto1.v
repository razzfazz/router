module add_nto1
  (data_in, data_out);
   
`include "functions.v"
   
   parameter width = 1;
   parameter num_ports = 2;
   
   localparam out_width = clogb(num_ports) + width;
   
   input [0:width*num_ports-1] data_in;
   output [0:out_width-1] data_out;
   
   reg [0:out_width-1] data_out;

   integer 	       i;
   
   always @(data_in)
     begin
	data_out = {out_width{1'b0}};
	for(i = 0; i < num_ports; i = i + 1)
	  begin
	     data_out = data_out + data_in[i*width +: width];
	  end
     end
   
endmodule
