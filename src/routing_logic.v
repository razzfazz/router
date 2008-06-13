module routing_logic
  (clk, reset, req, route_info_in, gnt, route_info_out, next_port);
   
   parameter architecture = 0;
   
`include "config.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   input clk;
   input reset;
   input req;
   input [0:route_info_width-1] route_info_in;
   output gnt;
   output [0:route_info_width-1] route_info_out;
   output [0:num_ports-1] next_port;
   
   generate
      
      wire [0:traffic_class_width-1] traffic_class;
      wire [0:routing_class_width-1] routing_class;
      wire [0:addr_width-1] next_address;
      wire [0:addr_width-1] final_address;
      route_info_decoder
	#()
      route_info_dec
	(.route_info(route_info_in),
	 .traffic_class(traffic_class),
	 .routing_class(routing_class),
	 .next_address(next_address),
	 .final_address(final_address));
      
      case(architecture)
	0:
	  begin

	     assign gnt = req;
	     assign route_info_out = route_info_in;

	     port_decoder_dim_order
	       #(.address(address))
	     port_dec
	       (.next_address(next_address),
		.next_port(next_port));

	  end
      endcase
      
   endgenerate
   
endmodule
