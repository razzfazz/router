module routing_logic
  (clk, reset, req, route_info, routing_class, gnt, next_route_info,
   next_routing_class, next_port);
   
`include "functions.v"
`include "config.v"   
`include "constants.v"
   
   /* supported architectures:
    0: baseline
    1: replicate port decoding logic */
   parameter architecture = 0;
   
   parameter reset_type = reset_type_async;
   
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
   
   wire gnt;
   wire [0:route_info_width-1] next_route_info;
   wire [0:routing_class_idx_width-1] next_routing_class;
   wire [0:num_ports-1] 	      next_port;
   
   wire [0:addr_width-1] 	      next_address;
   assign next_address = get_next_address(route_info);
   
   wire [0:addr_width-1] 	      final_address;
   assign final_address = get_final_address(route_info);
   
   assign gnt = req;
   
   wire 			      is_minimal;
   assign is_minimal = (routing_class == routing_class_minimal);
   
   wire 			      is_next;
   assign is_next = (address == next_address);
   
   wire [0:addr_width-1] 	      new_next_address;
   assign new_next_address = is_next ? final_address : next_address;
   
   assign next_route_info = create_route_info(new_next_address, final_address);
   
   assign next_routing_class = (~is_minimal & is_next) ? 
			       routing_class_minimal : 
			       routing_class;
   
   generate
      
      case(architecture)
	0:
	  begin
	     port_decoder_dim_order
	       #(.address(address))
	     port_dec
	       (.next_address(new_next_address),
		.next_port(next_port));
	  end
	1:
	  begin
	     wire [0:num_ports-1] next_port_a;
	     port_decoder_dim_order
	       #(.address(address))
	     port_dec_a
	       (.next_address(next_address),
		.next_port(next_port_a));
	     wire [0:num_ports-1] next_port_b;
	     port_decoder_dim_order
	       #(.address(address))
	     port_dec_b
	       (.next_address(final_address),
		.next_port(next_port_b));
	     assign next_port = is_next ? next_port_b : next_port_a;
	  end
      endcase
      
   endgenerate
   
endmodule
