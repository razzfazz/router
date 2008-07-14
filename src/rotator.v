module rotator
  (data_in, select, data_out);
   
`include "functions.v"
   
   parameter width = 8;
   
   /* rotate direction:
    0: left
    1: right */
   parameter direction = 0;
   
   localparam sel_width = clogb(width);
   
   
   input [0:width-1] data_in;
   input [0:sel_width-1] select;
   output [0:width-1] data_out;
   
   wire [0:width-1] data_out;
   
   wire [0:(2*width-1)-1] data_dup;
   wire [0:(2*width-1)-1] data_rot;
   
   generate
      
      case (direction)
	0:
	  begin
	     assign data_dup = {data_in, data_in[0:(width-1)-1]};
	     assign data_rot = data_dup << select;
	     assign data_out = data_rot[0:width-1];
	  end
	1:
	  begin
	     assign data_dup = {data_in[1:width-1], data_in};
	     assign data_rot = data_dup >> select;
	     assign data_out = data_rot[width-1:(2*width-1)-1];
	  end
      endcase
      
   endgenerate
   
endmodule
