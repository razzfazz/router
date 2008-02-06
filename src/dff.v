module dff
  #(  parameter width = 32,
      parameter offset = 0)
   (   input clk,
       input [offset:offset+width-1] d,
       output reg [offset:offset+width-1] q);

   always @(posedge clk)
     begin
	q <= d;
     end
   
endmodule
