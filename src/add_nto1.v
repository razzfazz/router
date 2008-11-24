// $Id$
// generic n-input adder
module add_nto1
  (data_in, data_out);
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // width of each input
   parameter width = 1;
   
   // number of inputs
   parameter num_ports = 2;
   
   // result width
   localparam out_width = clogb(num_ports) + width;
   
   // vector of inputs
   input [0:width*num_ports-1] data_in;
   
   // output data
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
