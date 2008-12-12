// rotate bit vector by given amount
module rotator
  (amount, data_in, data_out);
   
`include "constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // width of input data
   parameter width = 8;
   
   // direction in which to rotate
   parameter rotate_dir = `ROTATE_DIR_LEFT;
   
   // width of rotation amount
   localparam amount_width = clogb(width);
   
   // input data
   input [0:width-1] data_in;
   
   // result
   input [0:amount_width-1] amount;
   
   // amount by which to rotate
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   wire [0:(2*width-1)-1] data_dup;
   wire [0:(2*width-1)-1] data_rot;
   
   generate
      
      case (rotate_dir)
	`ROTATE_DIR_LEFT:
	  begin
	     assign data_dup = {data_in, data_in[0:(width-1)-1]};
	     assign data_rot = data_dup << amount;
	     assign data_out = data_rot[0:width-1];
	  end
	`ROTATE_DIR_RIGHT:
	  begin
	     assign data_dup = {data_in[1:width-1], data_in};
	     assign data_rot = data_dup >> amount;
	     assign data_out = data_rot[width-1:(2*width-1)-1];
	  end
      endcase
      
   endgenerate
   
endmodule
