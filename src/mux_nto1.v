module mux_nto1
  (select, data_in, data_out);
   
   
`include "functions.v"
   
   
   parameter width = 32;
   parameter num_ports = 4;
   localparam sel_width = clogb(num_ports);
   
   
   input [0:sel_width-1] select;
   input [0:num_ports*width-1] data_in;
   output wire [0:width-1] data_out;
   
   
   assign data_out = data_in[select*width +: width];
   
endmodule
