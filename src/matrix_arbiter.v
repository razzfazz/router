module matrix_arbiter
  #(parameter num_ports = 32,
    parameter use_clock_gating = 1)
   (input     clk,
    input     reset,
    input     update,
    input [0:num_ports-1] req,
    output wire [0:num_ports-1] gnt);
   
   wire [0:num_ports*num_ports-1] prio_s, prio_q;
   
   wire 			  clk_gated;
   
   genvar 			  row, col;
   
   generate
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   for(col = 0; col < num_ports; col = col + 1)
	     begin:cols
		if(row < col)
		  begin
		     if(use_clock_gating)
		       begin
			  dff
			    #(.width(1),
			      .offset(col),
			      .reset_type(1),
			      .reset_value(1'b1))
			  prioq
			    (.clk(clk_gated),
			     .reset(reset),
			     .d(prio_s[row*num_ports+col]),
			     .q(prio_q[row*num_ports+col]));
		       end
		     else
		       begin
			  dff
			    #(.width(1),
			      .offset(col),
			      .reset_type(1),
			      .reset_value(1'b1),
			      .use_enable(1))
			  prioq
			    (.clk(clk_gated),
			     .reset(reset),
			     .enable(update),
			     .d(prio_s[row*num_ports+col]),
			     .q(prio_q[row*num_ports+col]));
		       end
		  end
		else if(row == col)
		  begin
		     assign prio_q[row*num_ports+col] = 1'b1;
		  end
		else
		  begin
		     assign prio_q[row*num_ports+col]
			      = ~prio_q[col*num_ports+row];
		  end
		
		assign prio_s[row*num_ports+col]
			 = (prio_q[row*num_ports+col] | gnt[col]) & ~gnt[row];
	     end
	end
   endgenerate
   
   genvar 		    i;
   
   generate
      for(i = 0; i < num_ports; i = i + 1)
	begin:gnts
	   assign gnt[i] = req[i] & 
			   (&(prio_q[i*num_ports:(i+1)*num_ports-1] | ~req));
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
   
endmodule
