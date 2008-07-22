module routing_logic
  (clk, reset, req, route_info, vc_id, gnt, next_route_info, next_port,
   next_vcs);
   
`include "functions.v"
`include "config.v"   
`include "constants.v"
`include "config_utils.v"
   
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
   input [0:port_idx_width-1] port_id;
   input [0:vc_idx_width-1] vc_id;
   output gnt;
   output [0:route_info_width-1] next_route_info;
   output [0:num_ports-1] next_port;
   output [0:num_vcs-1] next_vcs;
   
   wire gnt;
   wire [0:route_info_width-1] next_route_info;
   wire [0:num_ports-1]        next_port;
   wire [0:num_vcs-1] 	       next_vcs;
   
   wire [0:addr_width-1]       next_address;
   assign next_address = get_next_address(route_info);
   
   wire [0:addr_width-1]       final_address;
   assign final_address = get_final_address(route_info);
   
   assign gnt = req;
   
   wire 		       is_next;
   assign is_next = (address == next_address);
   
   wire [0:addr_width-1]       new_next_address;
   assign new_next_address = is_next ? final_address : next_address;
   
   assign next_route_info = create_route_info(new_next_address, final_address);
   
   
   generate

      genvar 		       nvc;
      for(nvc = 0; nvc < num_vcs; nvc = nvc + 1)
	begin:nvcs
	   assign next_vcs[nvc]
	     = ((get_traffic_class(nvc) == get_traffic_class(vc_id)) &&
		(get_routing_class(nvc) == 
		 ((is_next && (get_routing_class(vc_id) != 0)) ?
		  0 :
		  get_routing_class(vc_id)))) ||
	       !restrict_vcs;
	end
      
      case(architecture)
	0:
	  begin
	     port_decoder_dim_order
	       #(.address(address))
	     port_dec
	       (.next_address(new_next_address),
		.next_port(next_port_int));
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
	     assign next_port_int = is_next ? next_port_b : next_port_a;
	  end
      endcase
      
      genvar 			  nport;
      for(nport = 0; nport < num_ports; nport = nport + 1)
	begin:nports
	   assign next_port[nport] = next_port_int &&
				     ((nport != port_id) || !ignore_same_port);
	end
      
   endgenerate
   
endmodule
