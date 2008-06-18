module routing_logic
  (clk, reset, req, route_info, routing_class, gnt, next_route_info,
   next_routing_class, next_port);
   
   parameter architecture = 0;
   parameter reset_type = 0;
   
`include "config.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   input clk;
   input reset;
   input req;
   input [0:route_info_width-1] route_info;
   input [0:routing_class_idx_width-1] routing_class;
   output gnt;
   output [0:route_info_width-1] next_route_info;
   output [0:routing_class_idx_width-1] next_routing_class;
   output [0:num_ports-1] next_port;
   
   generate
      
      wire [0:addr_width-1] 		 next_address;
      assign next_address = get_next_address(route_info);
      
      wire [0:addr_width-1] 		 final_address;
      assign final_address = get_final_address(route_info);
      
      case(architecture)
	0:
	  begin

	     assign gnt = req;
	     assign next_route_info = route_info;
	     assign next_routing_class = routing_class;

	     port_decoder_dim_order
	       #(.address(address))
	     port_dec
	       (.next_address(next_address),
		.next_port(next_port));

	  end
      endcase
      
   endgenerate
   
endmodule
