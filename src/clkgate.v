module clkgate
  #()
   (input clk,
    input act,
    output wire clk_gated);
   
   reg 		act_q;
   
   assign    clk_gated = clk & act_q;
   
   always @(clk, act)
     begin
	if(clk == 0)
          act_q <= act;
     end
   
endmodule
