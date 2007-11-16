module wf_alloc
  #(
    
    // number of input/output ports
    parameter num_ports = 8,

    // clone priority flipflops to reduce delay
    // (0 = num_ports FFs for num_ports priority groups
    //  1 = num_ports^2 FFs for 3.5*num_ports*(num_ports-1) + 1 base blocks)
    parameter clone_prio_flipflops = 0
	
    )
   (
    input     clk,
    input     reset,
    input [0:num_ports-1] req[0:num_ports-1],
    output [0:num_ports-1] gnt[0:num_ports-1]
    );
   
   wire [0:2*num_ports-1]  xin[0:2*num_ports-1];
   wire [0:2*num_ports-1]  xout[0:2*num_ports-1];
   wire [0:2*num_ports-1]  gnt_int[0:2*num_ports-1];
   wire [0:2*num_ports-1]  prio[0:2*num_ports-1];
   wire [0:num_ports-1]    clk_gated;
   
   genvar 		   row, col;
   
   generate
      for(row = 0; row < 2 * num_ports - 1; row = row + 1)
	begin:rows
	   for(col = 0; col < 2 * num_ports - 1; col = col + 1)
	     begin:cols
		
		if(clone_prio_flipflops == 1)
		  begin
		     if((row < num_ports) && (col == 0))
		       begin
			  localparam curr = row;
			  localparam prev = (row + num_ports-1) % num_ports;
			  wire 	     act = prio[prev][0] | prio[curr][0];
			  
			  clkgate clk_gate_blk(.clk(clk),
					       .act(act),
					       .clk_gated(clk_gated(curr)));
		       end
		     if((row < num_ports) && (col < num_ports))
		       begin
			  localparam prio_grp = (row + col) % num_ports;
			  localparam ref_row = (row + num_ports-1) % num_ports;
			  localparam ref_col = (col + num_ports-1) % num_ports;
			  wire 	     prio_q;
			  wire 	     prio_s = (reset ?
					       ((prio_grp == 0) ? 1'b1 : 1'b0) :
					       prio[ref_row][ref_col]);
			  dff #(.width(1)) prio_ff(.clk(clk_gated(prio_grp)),
						   .d(prio_s),
						   .q(prio_q));
			  assign     prio[row][col] = prio_q;
		       end
		     else
		       begin
			  localparam ref_row = row % num_ports;
			  localparam ref_col = col % num_ports;
			  assign     prio[row][col] = prio[ref_row][ref_col];
		       end
		  end
		else if(clone_prio_flipflops == 0)
		  begin
		     if((row < num_ports) && (col == 0))
		       begin
			  localparam prio_grp = row;
			  localparam ref_row = (row + num_ports-1) % num_ports;
			  localparam ref_col = 0;
			  wire 	     prio_q;
			  wire 	     prio_s = (reset ?
					       ((prio_grp == 0) ? 1'b1 : 1'b0) :
					       prio[ref_row][ref_col]);
			  dff #(.width(1)) prio_ff(.clk(clk_gated(prio_grp)),
						   .d(prio_s),
						   .q(prio_q));
			  assign     prio[row][col] = prio_q;
		       end
		     else
		       begin
			  localparam ref_row = (row + col) % num_ports;
			  localparam ref_col = 0;
			  assign     prio[row][col] = prio[ref_row][ref_col];
		       end
		  end
		
		if((row > 0) && (col > 0) && (row + col > num_ports))
		  begin
		     localparam  ref_row = row % num_ports;
		     localparam  ref_col = col % num_ports;
		     xin[row][col] = xout[row][col - 1];
		     yin[row][col] = yout[row - 1][col];
		     wf_alloc_block alloc_block(.prio(prio[row][col]),
						.xin(xin[row][col]),
						.yin(yin[row][col]),
						.req(req[ref_row][ref_col]),
						.xout(xout[row][col]),
						.yout(yout[row][col]),
						.gnt(gnt_int[row][col])
						);
		  end
		else
		  begin
		     xin[row][col] = 1'b0;
		     yin[row][col] = 1'b0;
		     xout[row][col] = xin[row][col];
		     yout[row][col] = yin[row][col];
		     gnt_int[row][col] = 1'b0;
		  end
		
		if((row >= num_ports) && (col >= num_ports))
		  begin
		     localparam row2 = row % num_ports;
		     localparam col2 = col % num_ports;
		     assign 	gnt[row2][col2] = (gnt_int[row][col] | 
						   gnt_int[row2][col] |
						   gnt_int[row][col2] | 
						   gnt_int[row2][col2]);
		  end
		
	     end
	end
   endgenerate
   
endmodule
