module regfile
   (clk, write_enable, write_address, write_data, read_address, read_data);
   
   parameter width = 64;
   parameter depth = 8;
   
`include "functions.v"
   
   localparam addr_width = clogb(depth);
   
   input clk;
   input write_enable;
   input [0:addr_width-1] write_address;
   input [0:width-1] write_data;
   input [0:addr_width-1] read_address;
   output [0:width-1] read_data;
   
   reg [0:width-1] 	  storage [0:depth-1];
   
   always @(posedge clk)
     if(write_enable)
       storage[write_address] <= write_data;
   
   wire [0:width-1] 	  read_data;

   assign read_data = storage[read_address];
   
endmodule
