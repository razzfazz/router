module rr_arbiter
  #(parameter num_ports = 32,
    parameter use_clock_gating = 1)
   (input     clk,
    input     reset,
    input     update,
    input [0:num_ports-1] req,
    output wire [0:num_ports-1] gnt);
   
   wire [0:num_ports-1] 	req_rev;
   wire [0:num_ports-2] 	prev_q;
   
   wire [0:num_ports-1] 	gnt_unqual = req_rev & -req_rev;

   wire [0:num_ports-2] 	mask = prev_q - 1;
   wire [0:num_ports-2] 	req_qual = req_rev[0:num_ports-2] & ~mask;
   wire [0:num_ports-2] 	gnt_qual = req_qual & -req_qual;
   
   wire [0:num_ports-1] 	gnt_rev = ((|req_qual) ?
					   {gnt_qual, 1'b0} :
					   gnt_unqual);
   
   wire [0:num_ports-2] 	prev_s = (update ?
					  gnt_rev[1:num_ports-1] :
					  prev_q);
   
   wire 			clk_gated;
   
   genvar 			i;
   generate
      for(i = 0; i < num_ports; i = i + 1)
	begin:connect
	   assign req_rev[i] = req[(num_ports-1)-i];
	   assign gnt[i] = gnt_rev[(num_ports-1)-i];
	end
   endgenerate
   
   generate
      if(use_clock_gating)
	begin
	   wire act;
	   
	   assign act = update;
	   
	   clkgate clk_gate_blk
	     (.clk(clk),
	      .act(act),
	      .clk_gated(clk_gated));
	end
      else
	begin
	   assign clk_gated = clk;
	end
   endgenerate
   
   dff
     #(.width(num_ports-1),
       .reset_type(1))
   prevq
     (.clk(clk_gated),
      .reset(reset),
      .d(prev_s),
      .q(prev_q));
   
endmodule
