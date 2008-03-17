module dff
  #(parameter width = 32,
    parameter offset = 0,
    parameter reset_type = 0, // 0 = none, 1 = async, 2 = sync
    parameter reset_value = {width{1'b0}},
    parameter hold_type = 0) // 0 = explicit, 1 = enable pin, 2 = clock gating
   (input clk,
    input reset,
    input enable,
    input [offset:offset+width-1] d,
    output reg [offset:offset+width-1] q);

   generate

      case(reset_type)

	0:
	  always @(posedge clk)
	    if((hold_type != 1) || enable)
	      q <= d;
	
	1:
	  always @(posedge clk, posedge reset)
	    if(reset)
	      q <= reset_value;
	    else
	      if((hold_type != 1) || enable)
		q <= d;

	2:
	  always @(posedge clk)
	    if(reset)
	      q <= reset_value;
	    else
	      if((hold_type != 1) || enable)
		q <= d;

      endcase 
      
   endgenerate
   
endmodule
