$Id$
// configurable register
module dff
  (clk, reset, d, q);
   
`include "constants.v"
   
   // width of register
   parameter width = 32;
   
   // offset (left index) of register
   parameter offset = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   parameter [offset:(offset+width)-1] reset_value = {width{1'b0}};
   
   input clk;
   input reset;
   
   // data input
   input [offset:(offset+width)-1] d;
   
   // data output
   output [offset:(offset+width)-1] q;
   reg [offset:(offset+width)-1] q;
   
   generate
      
      case(reset_type)
	
	`RESET_TYPE_NONE:
	  always @(posedge clk)
	    q <= d;
	
	`RESET_TYPE_ASYNC:
	  always @(posedge clk, posedge reset)
	    if(reset)
	      q <= reset_value;
	    else
	      q <= d;
	
	`RESET_TYPE_SYNC:
	  always @(posedge clk)
	    if(reset)
	      q <= reset_value;
	    else
	      q <= d;
	
      endcase 
      
   endgenerate
   
endmodule
