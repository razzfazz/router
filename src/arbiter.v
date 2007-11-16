module arbiter
  #(
    parameter width = 32,
    parameter use_matrix_arb = 1
    )
   (
    input     clk,
    input     reset,
    input     update,
    input [0:width-1] req,
    output wire [0:width-1] gnt
    );
   
   generate
      if(use_matrix_arb == 1)
	matrix_arbiter #(.width(width)) arb (.clk(clk), .reset(reset),
					       .update(update), .req(req),
					       .gnt(gnt));
      else
	rr_arbiter #(.width(width)) arb (.clk(clk), .reset(reset),
					   .update(update), .req(req),
					   .gnt(gnt));
   endgenerate
   
endmodule
