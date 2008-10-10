// generic register file
module regfile
  (clk, write_enable, write_address, write_data, read_address, read_data);
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number fo entries
   parameter depth = 8;
   
   // width of each entry
   parameter width = 64;
   
   // width required to swelect an entry
   localparam addr_width = clogb(depth);
   
   input clk;
   
   // if high, write to entry selected by write_address
   input write_enable;
   
   // entry to be written to
   input [0:addr_width-1] write_address;
   
   // data to be written
   input [0:width-1] write_data;
   
   // entry to read out
   input [0:addr_width-1] read_address;
   
   // contents of entry selected by read_address
   output [0:width-1] read_data;
   wire [0:width-1] read_data;
   
   reg [0:addr_width-1] read_address_q;
   reg [0:width-1] 	storage [0:depth-1];
   
   always @(posedge clk)
     begin
	if(write_enable)
	  storage[write_address] <= write_data;
	read_address_q <= read_address;
     end
   
   assign read_data = storage[read_address_q];
   
endmodule
