module wf_alloc
  #(
    
    // number of input/output ports
    // each input can bid for any combination of outputs
    parameter num_ports = 8,

    // clone priority flipflops to reduce delay
    // (0 = num_ports FFs for num_ports priority groups
    //  1 = num_ports^2 FFs for 3.5*num_ports*(num_ports-1) + 1 base blocks)
    parameter clone_prio_flipflops = 0
	
    )
   (
    input     clk,
    input     reset,
    input     update,
    input [0:num_ports*num_ports-1] req,
    output [0:num_ports*num_ports-1] gnt
    );
   
   wire [0:(2*num_ports)*(2*num_ports)-1] x;
   wire [0:(2*num_ports)*(2*num_ports)-1] y;
   wire [0:(2*num_ports)*(2*num_ports)-1] gnt_int;
   wire [0:(2*num_ports)*(2*num_ports)-1] prio;
   wire [0:num_ports-1] 		  clk_gated;
   
   genvar 				  row, col;
   
   generate

      // generate flipflops for priority indication

      // in this case, we have one FF per priority group that drives all
      // allocator blocks in that group
      if(clone_prio_flipflops == 0)
	begin
	   wire [0:num_ports-1] prio_q;
	   wire [0:num_ports-1] prio_s = (reset ?
					  {1'b1, {(num_ports-1){1'b0}}} :
					  {prio_q[num_ports-1], 
					   prio_q[0:num_ports-2]});
	   
	   dff #(.width(num_ports)) prio_ff(.clk(clk_gated[0]),
					    .d(prio_s),
					    .q(prio_q));
	   
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:connect_prio
		localparam this_idx = row*(2*num_ports);
		
		assign prio[this_idx] = prio_q[row];
	     end
	end

      // in this case, we have num_ports FFs per priority group that are
      // shared among all allocator blocks in that group to reduce load
      else if(clone_prio_flipflops == 1)
	begin
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:prio_ff_rows
		for(col = 0; col < num_ports; col = col + 1)
		  begin:prio_ff_cols
		     localparam prio_grp = (row + col) % num_ports;
		     localparam ref_row = (row + num_ports-1) % num_ports;
		     localparam ref_col = (col + num_ports-1) % num_ports;
		     localparam ref_idx = ref_row*(2*num_ports) + ref_col;
		     localparam this_idx = row*(2*num_ports) + col;
		     wire 	prio_q;
		     wire 	prio_s = (reset ?
					  ((prio_grp == 0) ? 1'b1 : 1'b0) :
					  prio[ref_idx]);
		     
		     dff #(.width(1)) prio_ff(.clk(clk_gated[prio_grp]),
					      .d(prio_s),
					      .q(prio_q));
		     
		     assign     prio[this_idx] = prio_q;
		  end
	     end
	end

      // generate gated clocks
      if(clone_prio_flipflops == 0)
	begin
	   wire act = update;
	   
	   clkgate clk_gate_blk(.clk(clk),
				.act(act),
				.clk_gated(clk_gated[0]));
	   assign clk_gated[1:num_ports-1] = {(num_ports-1){1'b0}};
	end
      else if(clone_prio_flipflops == 1)
	begin
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:clk_gate_blks
		localparam this_idx = row*(2*num_ports);
		localparam ref_idx = (((row + num_ports-1) % num_ports) *
				      (2*num_ports));
		wire       act = (prio[ref_idx] | prio[this_idx]) & update;
	   
		clkgate clk_gate_blk(.clk(clk),
				     .act(act),
				     .clk_gated(clk_gated[row]));
	     end
	end

      // replicate basic n*n matrix 4 times to avoid combinational loops
      for(row = 0; row < 2 * num_ports; row = row + 1)
	begin:rows
	   for(col = 0; col < 2 * num_ports; col = col + 1)
	     begin:cols
		localparam this_idx = row*(2*num_ports) + col;
		localparam ref_row = row % num_ports;
		localparam ref_col = col % num_ports;
		localparam ref_idx = ref_row*num_ports + ref_col;

		// hook up priority signals
		if((clone_prio_flipflops == 0) &&
		   ((row >= num_ports) || (col > 0)))
		  begin
		     localparam prio_grp = (row + col) % num_ports;

		     assign 	prio[this_idx] = prio[prio_grp*(2*num_ports)];
		  end
		else if((clone_prio_flipflops == 1) &&
			((row >= num_ports) || (col >= num_ports)))
		  begin
		     localparam prio_idx = ref_row*(2*num_ports) + ref_col;
		     
		     assign 	prio[this_idx] = prio[prio_idx];
		  end
		
		// instantiate sub-blocks (except redundant ones)
		if((row > 0) && (col > 0) && (row + col > num_ports))
		  begin
		     wire   xprio = x[this_idx-1] | prio[this_idx];
		     wire   yprio = y[this_idx-(2*num_ports)] | prio[this_idx];
		     
		     assign x[this_idx] = xprio & (~yprio | ~req[ref_idx]);
		     assign y[this_idx] = yprio & (~xprio | ~req[ref_idx]);
		     assign gnt_int[this_idx] = xprio & yprio & req[ref_idx];
		  end
		else
		  begin
		     assign x[this_idx] = 1'b0;
		     assign y[this_idx] = 1'b0;
		     assign gnt_int[this_idx] = 1'b0;
		  end

		// collect grants from replicated allocator blocks
		if((row < num_ports) && (col < num_ports))
		  begin
		     localparam idx1 = row*(2*num_ports) + col;
		     localparam idx2 = (row+num_ports)*(2*num_ports) + col;
		     localparam idx3 = row*(2*num_ports) + col+num_ports;
		     localparam idx4 = ((row+num_ports)*(2*num_ports) +
					col+num_ports);
		     
		     assign 	gnt[row*num_ports + col] = (gnt_int[idx1] |
							    gnt_int[idx2] |
							    gnt_int[idx3] |
							    gnt_int[idx4]);
		  end
		
	     end
	end
   endgenerate
   
endmodule
