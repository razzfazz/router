module matrix_arbiter
  #(
    parameter width = 32
    )
   (
    input     clk,
    input     reset,
    input     update,
    input [0:width-1] req,
    output [0:width-1] gnt
    );
   
   wire [0:width*width-1] prio_s, prio_q;

   wire 		  clk_gated;
   
   genvar 		  row, col;
   
   generate
      for(row = 0; row < width; row = row + 1)
	begin:rows
	   for(col = 0; col < width; col = col + 1)
	     begin:cols
		if(row < col)
		  dff #(.width(1), .offset(col)) cell_ff
		    (.clk(clk_gated), .d(prio_s[row*width+col]),
		     .q(prio_q[row*width+col]));
		else if(row == col)
			  assign prio_q[row*width+col] = 1;
		else
		     assign prio_q[row*width+col] = ~prio_q[col*width+row];
		
		assign 	    prio_s[row*width+col] = ((prio_q[row*width+col] |
						      (gnt[col] & update)) & 
						     (~gnt[row] | ~update)) | 
						    reset;
	     end
	end
   endgenerate

   genvar 		    i;

   generate
      for(i = 0; i < width; i = i + 1)
	begin:gnts
	   assign gnt[i] = req[i] & &(prio_q[i*width:(i+1)*width-1] | ~req); 
	end
   endgenerate
   
   wire 	  act = (|gnt & update) | reset;
   
   clkgate clk_gate_blk(.clk(clk), .act(act), .clk_gated(clk_gated));
   
endmodule
