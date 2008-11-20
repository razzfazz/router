$Id$
// generic wavefront allocator
module wf_alloc
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   // select implementation variant
   parameter wf_allocator_type = `WF_ALLOCATOR_TYPE_REP;
   
   // try to recover from errors
   parameter error_recovery = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // request matrix
   input [0:num_ports*num_ports-1] req;
   
   // grant matrix
   output [0:num_ports*num_ports-1] gnt;
   wire [0:num_ports*num_ports-1] gnt;
   
   generate
      
      case(wf_allocator_type)
	`WF_ALLOCATOR_TYPE_MUX:
	  begin
	     wf_alloc_core_mux
	       #(.num_ports(num_ports),
		 .error_recovery(error_recovery),
		 .reset_type(reset_type))
	     core_mux
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
	`WF_ALLOCATOR_TYPE_REP:
	  begin
	     wf_alloc_core_rep
	       #(.num_ports(num_ports),
		 .error_recovery(error_recovery),
		 .reset_type(reset_type))
	     core_rep
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
	`WF_ALLOCATOR_TYPE_DPA:
	  begin
	     wf_alloc_core_dpa
	       #(.num_ports(num_ports),
		 .error_recovery(error_recovery),
		 .reset_type(reset_type))
	     core_dpa
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end      
	`WF_ALLOCATOR_TYPE_ROT:
	  begin
	     wf_alloc_core_rot
	       #(.num_ports(num_ports),
		 .error_recovery(error_recovery),
		 .reset_type(reset_type))
	     core_rot
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
	`WF_ALLOCATOR_TYPE_LOOP:
	  begin
	     wf_alloc_core_loop
	       #(.num_ports(num_ports),
		 .error_recovery(error_recovery),
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
