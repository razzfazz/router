module regfile
   (clk, write_enable, write_address, write_data, read_address, read_data);
   
   parameter width = 64;
   parameter depth = 8;
   parameter internal_bypass = 0;
   
`include "functions.v"
   
   localparam addr_width = clogb(depth);
   
   input                  clk;
   input                  write_enable;
   input [0:addr_width-1] write_address;
   input [0:width-1]      write_data;
   input [0:addr_width-1] read_address;
   output [0:width-1] 	  read_data;
   
   reg [0:width-1] 	  read_data;
   reg [0:width-1] 	  storage [0:depth-1];
   
   generate
   
      always @(posedge clk)
	if(write_enable)
	  begin
	     //$display("Writing %x to entry %d", write_data, write_address);
	     storage[write_address] <= write_data;
	  end
      
      always @(read_address)
	begin
	   if(internal_bypass)
	     read_data = (write_enable && (write_address == read_address)) ?
			 write_data :
			 storage[read_address];
	   else
	     read_data = storage[read_address];
	   //$display("Reading %x from entry %d", read_data, read_address);
	end
      
   endgenerate
   
endmodule
