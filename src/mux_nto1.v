// $Id$
// generic n-input multiplexer
module mux_nto1
  (select, data_in, data_out);
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of input ports
   parameter num_ports = 4;
   
   // width of each port
   parameter width = 32;
   
   // width of selector
   localparam sel_width = clogb(num_ports);
   
   // input selector
   input [0:sel_width-1] select;
   
   // vector of inputs
   input [0:num_ports*width-1] data_in;
   
   // result
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   assign data_out = data_in[select*width +: width];
   
endmodule
