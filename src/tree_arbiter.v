module tree_arbiter
  #(parameter num_ports = 16,
    parameter num_blocks = 4,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1,

    /* supported architectures:
     0: round-robin arbiter
     1: matrix arbiter */
    parameter architecture = 0)
   (input     clk,
    input     reset,
    input     update,
    input [0:num_ports-1] req,
    output wire [0:num_ports-1] gnt);
   
   localparam ports_per_block = num_ports / num_blocks;
   
   wire [0:num_blocks-1] 	stg2_req;   
   wire [0:num_blocks-1] 	stg2_gnt;
   
   generate
      
      // first stage of arbitration: one arbiter per group
      genvar 			i;
      for(i = 0; i < num_blocks; i = i + 1)
	begin:blocks
	   
	   wire [0:ports_per_block-1] 	 stg1_req;
	   assign stg1_req = req[i*ports_per_block:(i+1)*ports_per_block-1];
	   
	   assign stg2_req[i] = |stg1_req;
	   
	   wire [0:ports_per_block-1] 	 stg1_gnt;
	   arbiter
	     #(.num_ports(ports_per_block),
	       .reset_type(reset_type),
	       .hold_type(hold_type),
	       .architecture(architecture))
	   stg1_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update),
	      .req(stg1_req),
	      .gnt(stg1_gnt));

	   assign gnt[i*ports_per_block:(i+1)*ports_per_block-1]
		    = {ports_per_block{stg2_gnt[i]}} & stg1_gnt;
	   
	end
      
   endgenerate
   
   // second stage of arbitration: arbitrate between all groups
   arbiter
     #(.num_ports(num_blocks),
       .reset_type(reset_type),
       .hold_type(hold_type),
       .architecture(architecture))
   stg2_arb
     (.clk(clk),
      .reset(reset),
      .update(update),
      .req(stg2_req),
      .gnt(stg2_gnt));
   
endmodule
