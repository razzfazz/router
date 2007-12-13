module wf_alloc
  #(
    
    // number of input/output ports
    // each input can bid for any combination of outputs
    parameter num_ports = 8,

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
   
   wire [0:num_ports*num_ports*num_ports-1] gnt_by_prio;

   wire 				    clk_gated;
   
   genvar 				    i, j, k;
   
   wire [0:num_ports-1] 		    prio_s, prio_q;
   
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
   
   generate
      
      // generate gated clocks
      if(disable_clock_gating)
	begin
	   assign clk_gated = clk;
	end
      else
	begin
	   
	   wire act;
		
	   assign act = reset | update;
		
	   clkgate clk_gate_blk
	     (.clk(clk),
	      .act(act),
	      .clk_gated(clk_gated));
		
	end

   endgenerate

   generate
      
      for(i = 0; i < num_ports; i = i + 1)
	begin:blk_prios

	   wire [0:num_ports*num_ports-1] req_int;
	   wire [0:num_ports*num_ports-1] gnt_int;

	   wf_alloc_blk
	     #(.num_ports(num_ports))
	   wfa_blk
	     (.req(req_int),
	      .gnt(gnt_int));

	   for(j = 0; j < num_ports; j = j + 1)
	     begin:blk_rows
		for(k = 0; k < num_ports; k = k + 1)
		  begin:blk_cols
		     
		     assign req_int[j*num_ports+k] 
			      = req[((i+j)%num_ports)*num_ports +
				    (num_ports-j+k)%num_ports];
		     assign gnt_by_prio[((i+j)%num_ports)*num_ports +
				    (num_ports-j+k)%num_ports +
					i*num_ports*num_ports]
			      = gnt_int[j*num_ports+k];

		  end
	     end
	end
   endgenerate

   select_1ofn
     #(.width(num_ports*num_ports),
       .num_ports(num_ports))
   gnt_or
     (.select(prio_q),
      .data_in(gnt_by_prio),
      .data_out(gnt));
   
endmodule
