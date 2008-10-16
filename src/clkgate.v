// clock gating module (supresses clock pulses)
module clkgate
  (clk, act, clk_gated);
   
   // free-running clock
   input clk;
   
   // clock enable
   input act;
   
   // gated clock
   output clk_gated;
   wire clk_gated;
   
   reg 	act_q;
   
   assign clk_gated = clk & act_q;
   
   always @(clk, act)
     begin
	if(clk == 0)
          act_q <= act;
     end
   
endmodule
