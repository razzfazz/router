$Id$
// generic arbiter
module arbiter
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   // select type of arbiter to use
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
   
   generate

      if(num_ports > 1)
	begin
	   
	   case(arbiter_type)
	     `ARBITER_TYPE_ROUND_ROBIN:
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
	     `ARBITER_TYPE_MATRIX:
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
	   
	end
      else
	assign gnt = req;
      
   endgenerate
   
endmodule
