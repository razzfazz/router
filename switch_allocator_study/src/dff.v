module dff
  #(parameter width = 32,
    parameter offset = 0,
    
    /* supported reset types:
     0: no reset
     1: asynchronous reset
     2: synchronous reset */
    parameter reset_type = 0,
    parameter reset_value = {width{1'b0}})
   (input clk,
    input reset,
    input [offset:offset+width-1] d,
    output reg [offset:offset+width-1] q);

   generate
      
      case(reset_type)
	
	0:
	  always @(posedge clk)
	    q <= d;
	
	1:
	  always @(posedge clk, posedge reset)
	    if(reset)
	      q <= reset_value;
	    else
	      q <= d;
	
	2:
	  always @(posedge clk)
	    if(reset)
	      q <= reset_value;
	    else
	      q <= d;
	
      endcase 
      
   endgenerate
   
endmodule
