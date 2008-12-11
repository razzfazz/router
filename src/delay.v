module delay
  (clk, reset, data_in, data_out);
   
`include "constants.v"
   
   // width of data
   parameter width = 1;
   
   // number of cycles by which to delay data
   parameter delay = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   input [0:width-1] data_in;
   
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   wire [0:(delay+1)*width-1] data_dly;
   
   assign data_dly[0:width-1] = data_in;
   
   generate
      
      genvar 		      level;
      
      for(level = 0; level < delay; level = level + 1)
	begin:levels
	   
	   wire [0:width-1] data_s, data_q;
	   assign data_s = data_dly[level*width:(level+1)*width-1];
	   dff
	     #(.width(width),
	       .reset_type(reset_type))
	   dataq
	     (.clk(clk),
	      .reset(reset),
	      .d(data_s),
	      .q(data_q));
	   
	   assign data_dly[(level+1)*width:(level+2)*width-1] = data_q;
	   
	end
      
   endgenerate
   
   assign data_out = data_dly[delay*width:(delay+1)*width-1];
   
endmodule
