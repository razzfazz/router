module routing_logic
  (clk, reset, route_info, port_id, vc_id, next_port, next_vcs, error);
   
`include "functions.v"
`include "config.v"   
`include "constants.v"
`include "config_utils.v"
   
   parameter reset_type = reset_type_async;
   
   // replicate port decoding logic
   parameter replicate_port_decoder = 0;
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   
   input clk;
   input reset;
   input [0:route_info_width-1] route_info;
   input [0:port_idx_width-1] port_id;
   input [0:vc_idx_width-1] vc_id;
   output [0:num_ports-1] next_port;
   output [0:num_vcs-1] next_vcs;
   output error;
   
   wire [0:num_ports-1] next_port;
   wire [0:num_vcs-1] 	next_vcs;
   wire 		error;
   
   wire [0:addr_width-1] next_address;
   assign next_address = get_next_address(route_info);
   
   wire [0:addr_width-1] final_address;
   assign final_address = get_final_address(route_info);
   
   wire 		 is_next;
   assign is_next = (address[0:router_addr_width-1] ==
		     next_address[0:router_addr_width-1]);
   
   wire [0:addr_width-1] new_next_address;
   assign new_next_address = is_next ? final_address : next_address;
   
   wire [0:num_ports-1]  next_port_int;
   
   wire [0:num_ports-1]  error_op;
   
   generate
      
      genvar 		 ovc;
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   assign next_vcs[ovc]
		    = ((get_traffic_class(ovc) == get_traffic_class(vc_id)) &&
		       (get_routing_class(ovc) == 
			((is_next && (get_routing_class(vc_id) != 0)) ?
			 0 :
			 get_routing_class(vc_id)))) ||
		      !restrict_vcs;
	end
      
      if(replicate_port_decoder)
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
	   assign next_port_int = is_next ? next_port_b : next_port_a;
	end
      else
	begin
	   port_decoder_dim_order
	     #(.address(address))
	   port_dec
	     (.next_address(new_next_address),
	      .next_port(next_port_int));
	end
      
      genvar 		   op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   assign next_port[op] = next_port_int[op] &&
				  ((op != port_id) || !ignore_same_port);
	   assign error_op[op] = next_port_int[op] &&
				 (op == port_id) && ignore_same_port;
	   
	end
      
   endgenerate
   
   assign error = |error_op;
   
endmodule
