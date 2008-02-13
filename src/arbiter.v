module arbiter
  #(parameter num_ports = 32,
    parameter num_blocks = 1,
    parameter use_clock_gating = 0,

    /* supported architectures:
     0: round-robin arbiter
     1: matrix arbiter */
    parameter use_architecture = 0)
   (input     clk,
    input     reset,
    input     update,
    input [0:num_ports-1] req,
    output wire [0:num_ports-1] gnt);

   genvar 			i;

   localparam ports_per_block = num_ports / num_blocks;
   
   generate
      if(num_blocks == 1)

	// if we have one big block, just do flat arbitration between all ports
	begin
	   if(use_architecture == 0)
	     begin
		rr_arbiter
		  #(.num_ports(num_ports),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(req),
		   .gnt(gnt));
	     end
	   else if(use_architecture == 1)
	     begin
		matrix_arbiter
		  #(.num_ports(num_ports),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(req),
		   .gnt(gnt));
	     end
	end
      else

	// if we have multiple blocks, arbitrate between requests in each block
	// and between all blocks with requests in parallel, and then combine
	// the grants from both stages
	begin
	   
	   wire [0:num_blocks-1] stg2_req;
	   wire [0:num_blocks-1] stg2_gnt;

	   // first stage of arbitration: one arbiter per group
	   for(i = 0; i < num_blocks; i = i + 1)
	     begin:blocks

		wire [0:ports_per_block-1] stg1_req;
		wire [0:ports_per_block-1] stg1_gnt;

		assign stg1_req = req[i*ports_per_block:
				      (i+1)*ports_per_block-1];
		
		assign stg2_req[i] = |stg1_req;

		if(use_architecture == 0)
		  begin
		     rr_arbiter
		       #(.num_ports(ports_per_block),
			 .use_clock_gating(use_clock_gating))
		     stg1_arb
		       (.clk(clk),
			.reset(reset),
			.update(update),
			.req(stg1_req),
			.gnt(stg1_gnt));
		  end
		else if(use_architecture == 1)
		  begin
		     matrix_arbiter
		       #(.num_ports(ports_per_block),
			 .use_clock_gating(use_clock_gating))
		     stg1_arb
		       (.clk(clk),
			.reset(reset),
			.update(update),
			.req(stg1_req),
			.gnt(stg1_gnt));
		  end

		assign gnt[i*ports_per_block:(i+1)*ports_per_block-1]
			 = {ports_per_block{stg2_gnt[i]}} & stg1_gnt;
		
	     end

	   // second stage of arbitration: arbitrate between all groups
	   if(use_architecture == 0)
	     begin
		rr_arbiter
		  #(.num_ports(num_blocks),
		    .use_clock_gating(use_clock_gating))
		stg2_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(stg2_req),
		   .gnt(stg2_gnt));
	     end
	   else if(use_architecture == 1)
	     begin
		matrix_arbiter
		  #(.num_ports(num_blocks),
		    .use_clock_gating(use_clock_gating))
		stg2_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(stg2_req),
		   .gnt(stg2_gnt));
	     end
   
	end
   endgenerate
   
endmodule
