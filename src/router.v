module router(CLK, RST, req, gnt);
   parameter width = 8;
   input CLK;
   input RST;
   input [0:width-1] req[0:width-1];
   output [0:width-1] gnt[0:width-1];
   //matrix_arbiter #(width) matrix_arb(CLK, RST, req, gnt);
   wf_alloc #(width) wfa(CLK, RST, req, gnt);
endmodule
