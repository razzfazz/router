module regfile
  #(parameter width = 64,
    parameter depth = 8,
    parameter sync_rf_output = 0)
   (clk, write_enable, write_address, write_data, read_address, read_data);
   
`include "functions.v"

   localparam addr_width = clogb(depth);
   
   input                  clk;
   input                  write_enable;
   input [0:addr_width-1] write_address;
   input [0:width-1]      write_data;
   input [0:addr_width-1] read_address;
   output reg [0:width-1] read_data;
   
   reg [0:width-1] 	  storage [0:depth-1];
   
   generate
   
      always @(posedge clk)
	begin
	   
	   if(write_enable)
	     begin
		$display("Writing %x to entry %d", write_data, write_address);
		storage[write_address] <= write_data;
	     end
	   
	   if(sync_rf_output)
	     begin
		read_data <= storage[read_address];
		$display("Reading %x from entry %d", read_data, read_address);
	     end
	   
	end
      
      if(!sync_rf_output)
	always @(read_address)
	  begin
	     read_data = storage[read_address];
	     $display("Reading %x from entry %d", read_data, read_address);
	  end
      
   endgenerate
   
endmodule
