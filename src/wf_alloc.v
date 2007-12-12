module wf_alloc
  #(
    
    // number of input/output ports
    // each input can bid for any combination of outputs
    parameter num_ports = 8,

    // clone priority flipflops to reduce delay
    // (0 = num_ports FFs for num_ports priority groups
    //  1 = num_ports^2 FFs for 3.5*num_ports*(num_ports-1) + 1 base blocks)
    parameter clone_prio_flipflops = 0,

    // disable clock gating?
    parameter disable_clock_gating = 0
	
    )
   (
    input     clk,
    input     reset,
    
    input     update,
    
    input [0:num_ports*num_ports-1] req,
    output [0:num_ports*num_ports-1] gnt
    );
   
   wire [0:(2*num_ports)*(2*num_ports)-1] x, y;
   wire [0:(2*num_ports)*(2*num_ports)-1] gnt_int;
   wire [0:(2*num_ports)*(2*num_ports)-1] prio;
   
   wire 				  clk_gated;
   
   genvar 				  row, col;
   
   generate

      // generate flipflops for priority indication

      // in this case, we have num_ports FFs per priority group that are
      // shared among all allocator blocks in that group to reduce load
      if(clone_prio_flipflops)
	begin
	   for(row = 0; row < 2 * num_ports; row = row + 1)
	     begin:prio_rows
		for(col = 0; col < 2 * num_ports; col = col + 1)
		  begin:prio_cols

		     // generate one num_ports^2 matrix of priority flipflops
		     if((row < num_ports) && (col < num_ports))
		       begin
			  
			  wire prio_s, prio_q;
			  
			  localparam idx = (((row+num_ports-1)%num_ports)*
					    (2*num_ports)+((col+num_ports-1)%
							   num_ports));

			  assign prio_s = (reset ?
					   ((((row+col)%num_ports)==0) ?
					    1'b1 :
					    1'b0) :
					   update ?
					   prio[idx] :
					   prio_q);
			  
			  dff
			    #(.width(1))
			  prioq
			    (.clk(clk_gated),
			     .d(prio_s),
			     .q(prio_q));
			  
			  assign prio[row*(2*num_ports)+col] = prio_q;
			  
		       end
		     
		     // hook up remaining priority signals
		     else
		       begin
			  assign prio[row*(2*num_ports)+col]
				   = prio[(row%num_ports)*(2*num_ports)+
					  (col%num_ports)];
		       end
		     
		  end
	     end
	end
	
      // in this case, we have one FF per priority group that drives all
      // allocator blocks in that group
      else
	begin
	   
	   wire [0:num_ports-1] prio_s, prio_q;
	   
	   assign prio_s = (reset ? 
			    {1'b1, {(num_ports-1){1'b0}}} :
			    update ?
			    {prio_q[num_ports-1], prio_q[0:num_ports-2]} :
			    prio_q);
	   
	   dff
	     #(.width(num_ports))
	   prioq
	     (.clk(clk_gated),
	      .d(prio_s),
	      .q(prio_q));

	   // hook up priority signals
	   for(row = 0; row < 2 * num_ports; row = row + 1)
	     begin:prio_rows
		for(col = 0; col < 2 * num_ports; col = col + 1)
		  begin:prio_cols
		     assign prio[row*(2*num_ports)+col]
			      = prio_q[(row+col)%num_ports];
		  end
	     end

	end

   endgenerate

   generate
      
      // generate gated clocks
      if(disable_clock_gating == 0)
	begin
	   
	   wire act;
		
	   assign act = reset | update;
		
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

   generate
      
      // replicate basic n*n matrix 4 times to avoid combinational loops
      for(row = 0; row < 2 * num_ports; row = row + 1)
	begin:rows
	   for(col = 0; col < 2 * num_ports; col = col + 1)
	     begin:cols

		// instantiate sub-blocks (except redundant ones)
		if((row > 0) && (col > 0) && (row + col > num_ports))
		  begin
		     
		     wire xprio;
		     wire yprio;

		     assign xprio
		       = x[row*(2*num_ports)+col-1] |
			 prio[row*(2*num_ports)+col];
		     assign yprio
		       = y[row*(2*num_ports)+col-(2*num_ports)] |
			 prio[row*(2*num_ports)+col];
		     
		     assign x[row*(2*num_ports)+col]
			      = (~yprio | ~req[(row%num_ports)*num_ports+
					       (col%num_ports)]) & xprio;
		     assign y[row*(2*num_ports)+col]
			      = (~xprio | ~req[(row%num_ports)*num_ports+
					       (col%num_ports)]) & yprio;
		     
		     assign gnt_int[row*(2*num_ports)+col]
			      = req[(row%num_ports)*num_ports+(col%num_ports)] &
				xprio & yprio;
		  end
		else
		  begin
		     assign x[row*(2*num_ports)+col] = 1'b0;
		     assign y[row*(2*num_ports)+col] = 1'b0;
		     
		     assign gnt_int[row*(2*num_ports)+col] = 1'b0;
		  end

		// collect grants from replicated allocator blocks
		if((row < num_ports) && (col < num_ports))
		  begin
		     assign gnt[row*num_ports + col]
			      = (gnt_int[row*(2*num_ports)+col] |
				 gnt_int[(row+num_ports)*(2*num_ports) + col] |
				 gnt_int[row*(2*num_ports) + col+num_ports] |
				 gnt_int[((row+num_ports)*(2*num_ports)+
					  col+num_ports)]);
		  end
		
	     end
	end
   endgenerate
   
endmodule
