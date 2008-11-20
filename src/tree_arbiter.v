// $Id$
// generic tree arbiter
module tree_arbiter
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input ports
   parameter num_ports = 16;
   
   // number of blocks in first stage of arbitration
   parameter num_blocks = 4;
   
   // number of inputs to each first-stage arbiter
   localparam ports_per_block = num_ports / num_blocks;
   
   // select arbiter variant to use
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // update port priorities
   input update;
   
   // request vector
   input [0:num_ports-1] req;
   
   // grant vector
   output [0:num_ports-1] gnt;
   wire [0:num_ports-1] gnt;
   
   // effective second-stage request vector
   wire [0:num_blocks-1] stg2_req;
   
   // second-stage grant vector
   wire [0:num_blocks-1] stg2_gnt;
   
   generate
      
      // first stage of arbitration: one arbiter per group
      genvar 		 i;
      for(i = 0; i < num_blocks; i = i + 1)
	begin:blocks
	   
	   wire [0:ports_per_block-1] 	 stg1_req;
	   assign stg1_req = req[i*ports_per_block:(i+1)*ports_per_block-1];
	   
	   assign stg2_req[i] = |stg1_req;
	   
	   wire [0:ports_per_block-1] 	 stg1_gnt;
	   arbiter
	     #(.num_ports(ports_per_block),
	       .reset_type(reset_type),
	       .arbiter_type(arbiter_type))
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
       .arbiter_type(arbiter_type))
   stg2_arb
     (.clk(clk),
      .reset(reset),
      .update(update),
      .req(stg2_req),
      .gnt(stg2_gnt));
   
endmodule
