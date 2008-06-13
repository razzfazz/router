module routing_logic
  (clk, reset, req, pkt_class, pkt_address, gnt, op, ovc_mask);
   
   parameter architecture = 0;
   
`include "config.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   input clk;
   input reset;
   input req;
   input [0:class_idx_width-1] pkt_class;
   input [0:addr_width-1] pkt_address;
   output gnt;
   output [0:num_ports-1] op;
   output [0:num_vcs-1] ovc_mask;
   
   generate
      
      case(architecture)
	0:
	  begin
	     rl
	       #(.address(address))
	     routing_logic_dim_order
	       (.clk(clk),
		.reset(reset),
		.req(req),
		.pkt_class(pkt_class),
		.pkt_address(pkt_address),
		.gnt(gnt),
		.op(op),
		.ovc_mask(ovc_mask));
	  end
      endcase
      
   endgenerate
   
endmodule
