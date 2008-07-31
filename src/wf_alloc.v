module wf_alloc
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   /*
    0: mux inputs/outputs based on priority
    1: replicate logic per priority
    2: diagonal propagation arbiter (DPA, see Hurt99)
    3: rotate inputs/outputs based on priority
    */
   parameter allocator_type = 0;
   
   parameter [0:num_ports*num_ports-1] mask = {num_ports*num_ports{1'b1}};
   
   parameter reset_type = reset_type_async;
   
   
   input clk;
   
   input reset;
   
   // update arbitration priorities
   input update;
   
   // requests
   input [0:num_ports*num_ports-1] req;
   
   // grants
   output [0:num_ports*num_ports-1] gnt;
   
   wire [0:num_ports*num_ports-1] gnt;
   
   generate
      
      case(allocator_type)
	0:
	  begin
	     wf_alloc_core_mux
	       #(.num_ports(num_ports),
		 .mask(mask),
		 .reset_type(reset_type))
	     core_mux
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
	1:
	  begin
	     wf_alloc_core_rep
	       #(.num_ports(num_ports),
		 .mask(mask),
		 .reset_type(reset_type))
	     core_rep
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
	2:
	  begin
	     wf_alloc_core_dpa
	       #(.num_ports(num_ports),
		 .mask(mask),
		 .reset_type(reset_type))
	     core_dpa
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end      
	3:
	  begin
	     wf_alloc_core_rot
	       #(.num_ports(num_ports),
		 .mask(mask),
		 .reset_type(reset_type))
	     core_rot
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
      endcase
      
   endgenerate
   
endmodule
