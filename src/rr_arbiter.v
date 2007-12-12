module rr_arbiter
  #(
    parameter width = 32,
    parameter disable_clock_gating = 0
    )
   (
    input     clk,
    input     reset,
    input     update,
    input [0:width-1] req,
    output wire [0:width-1] gnt
    );
   
   wire [0:width-1] 	    req_rev;
   wire [0:width-1] 	    prev_q;
   
   wire [0:width-1] 	    gnt_unqual = req_rev & -req_rev;
   
   wire [0:width-1] 	    mask = prev_q | (prev_q - 1);
   wire [0:width-1] 	    req_qual = req_rev & ~mask;
   wire [0:width-1] 	    gnt_qual = req_qual & -req_qual;
   
   wire [0:width-1] 	    gnt_rev = (|gnt_qual) ? gnt_qual : gnt_unqual;
   
   wire [0:width-1] 	    prev_s = (((|gnt_unqual & update) ? 
				       gnt_rev : 
				       prev_q) & 
				      ~{width{reset}});

   wire 		    clk_gated;
   
   genvar 		    i;
   generate
      for(i = 0; i < width; i = i + 1)
	begin:connect
	   assign req_rev[i] = req[(width-1)-i];
	   assign gnt[i] = gnt_rev[(width-1)-i];
	end
   endgenerate

   generate
      if(disable_clock_gating == 0)
	begin
	   wire act;

	   assign act = (|gnt_unqual & update) | reset;
   
	   clkgate clk_gate_blk(.clk(clk), .act(act), .clk_gated(clk_gated));
	end
      else
	begin
	   assign clk_gated = clk;
	end
   endgenerate
   
   dff #(.width(width)) prev_ff (.clk(clk_gated), .d(prev_s), .q(prev_q));
   
endmodule
