module dff
  #(parameter width = 32,
    parameter offset = 0,
    
    /* supported reset types:
     0: no reset
     1: asynchronous reset
     2: synchronous reset */
    parameter reset_type = 0,
    parameter reset_value = {width{1'b0}},

    /* supported hold types:
     0: explicit hold mux (external)
     1: enable pin on flipflop
     2: functional clock gating (external) */
    parameter hold_type = 0)
   (input clk,
    input reset,
    input enable,
    input [offset:offset+width-1] d,
    output reg [offset:offset+width-1] q);

   generate
      
      case(reset_type)
	
	0:
	  always @(posedge clk)
	    if(hold_type != 1)
	      q <= d;
	    else
	      if(enable)
		q <= d;
	
	1:
	  always @(posedge clk, posedge reset)
	    if(reset)
	      q <= reset_value;
	    else
	      if(hold_type != 1)
		q <= d;
	      else
		if(enable)
		  q <= d;
	
	2:
	  always @(posedge clk)
	    if(reset)
	      q <= reset_value;
	    else
	      if(hold_type != 1)
		q <= d;
	      else
		if(enable)
		  q <= d;
	
      endcase 
      
   endgenerate
   
endmodule
