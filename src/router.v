module router(CLK, RST, update, req, gnt);
   parameter width = 4;
   input CLK;
   input RST;
   input update;
   input [0:width*width-1] req;
   output [0:width*width-1] gnt;
   //rr_arbiter #(width) rr_arb(CLK, RST, update, req, gnt);
   //matrix_arbiter #(width) matrix_arb(CLK, RST, update, req, gnt);
   wf_alloc #(width) wfa(CLK, RST, update, req, gnt);
endmodule
