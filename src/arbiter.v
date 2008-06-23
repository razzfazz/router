module arbiter
  (clk, reset, update, req, gnt);
   
   
`include "constants.v"
   
   
   parameter num_ports = 32;
   
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: round-robin arbiter
    1: matrix arbiter */
   parameter architecture = 0;
   
   
   input clk;
   input reset;
   input update;
   input [0:num_ports-1] req;
   output wire [0:num_ports-1] gnt;
   
   
   generate
      
      case(architecture)
	0:
	  begin
	     rr_arbiter
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     arb
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
	1:
	  begin
	     matrix_arbiter
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     arb
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req),
		.gnt(gnt));
	  end
      endcase
      
   endgenerate
   
endmodule
