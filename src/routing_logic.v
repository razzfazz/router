// $Id$
// module to determine the output port and VC based on routing information 
// (e.g. destination address) and the current input port and VC)
module routing_logic
  (clk, reset, router_address, route_info, next_port, next_vcs, error);
   
`include "constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select an individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // nuber of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs available for each class
   localparam num_vcs_per_class = num_vcs / num_classes;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   localparam num_nodes_per_router
     = num_ports - num_dimensions * num_neighbors_per_dim;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // total number of bits required for storing routing information
   localparam route_info_width = 2 * addr_width;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_BY_RELATION;
   
   // ID of current port
   parameter port_id = 0;
   
   // ID of current VC
   parameter vc_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // routing data
   input [0:route_info_width-1] route_info;
   
   // output port to forward to
   output [0:num_ports-1] next_port;
   wire [0:num_ports-1] next_port;
   
   // candidate output VCs
   output [0:num_vcs-1] next_vcs;
   wire [0:num_vcs-1] 	next_vcs;
   
   // internal error condition detected
   output error;
   wire 		error;   
   
   // address to route packet to next
   // (note: for Valiant traffic, this is the address of the intermediate node)
   wire [0:addr_width-1] next_address;
   assign next_address = route_info[0:addr_width-1];
   
   // eventual destination address
   // (note: for minimal traffic, this is the same as next_address)
   wire [0:addr_width-1] final_address;
   assign final_address = route_info[addr_width:2*addr_width-1];
   
   // are we at the current destination?
   wire 		 is_next;
   assign is_next = (router_address == next_address[0:router_addr_width-1]);
   
   wire [0:addr_width-1] new_next_address;
   assign new_next_address = is_next ? final_address : next_address;
   
   wire [0:num_ports-1]  next_port_int;
   
   wire [0:num_ports-1]  error_op;
   
   wire [0:num_dimensions-1] dim_addr_match;
   
   // function to extract traffic class from VC index
   // (this implementation handles the case where we have only a single traffic
   // class correctly)
   function integer get_traffic_class(input integer vc);
      begin
	 get_traffic_class
	   = (vc >> (clogb(num_routing_classes) + clogb(num_vcs_per_class))) %
	     num_traffic_classes;
      end
   endfunction
   
   // function to extract routing class from VC index
   // (this implementation handles the case where we have only a single routing
   // class correctly)
   function integer get_routing_class(input integer vc);
      begin
	 get_routing_class
	   = (vc >> clogb(num_vcs_per_class)) % num_routing_classes;
      end
   endfunction
   
   generate
      
      genvar 		     ovc;
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   assign next_vcs[ovc]
		    = ((get_traffic_class(ovc) == get_traffic_class(vc_id)) &&
		       (get_routing_class(ovc) == 
			((is_next && (get_routing_class(vc_id) != 0)) ?
			 0 :
			 get_routing_class(vc_id))));
	   
	end
      
      genvar 		     dim;
      
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   wire [0:dim_addr_width-1] dim_addr;
	   assign dim_addr
	     = new_next_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   assign dim_addr_match[dim]
		    = (dim_addr == router_address[dim*dim_addr_width:
						  (dim+1)*dim_addr_width-1]);
	   
	   wire 		     route_here;
	   
	   if(dim == 0)
	     assign route_here
	       = ~dim_addr_match[dim];
	   else
	     assign route_here
	       = &dim_addr_match[0:dim-1] & ~dim_addr_match[dim];
	   
	   wire [0:dim_addr_width-1]   local_dim_addr;
	   assign local_dim_addr = router_address[dim*dim_addr_width:
						  (dim+1)*dim_addr_width-1];
	   
	   wire [0:num_neighbors_per_dim-1] port_dec;
	   
	   case(routing_function_type)
	     `ROUTING_FUNCTION_TYPE_BY_RELATION:
	       begin
		  
		  assign port_dec
		    = {dim_addr < local_dim_addr, dim_addr > local_dim_addr};
		  
	       end
	     `ROUTING_FUNCTION_TYPE_BY_DIFFERENCE:
	       begin
		  
		  wire [0:num_routers_per_dim-1] dim_addr_dec;
		  decoder
		    #(.num_ports(num_routers_per_dim))
		  dim_addr_dec_dec
		    (.data_in(dim_addr),
		     .data_out(dim_addr_dec));
		  
		  wire [0:(2*num_routers_per_dim-1)-1] dim_addr_dec_repl;
		  assign dim_addr_dec_repl
		    = {dim_addr_dec, dim_addr_dec[0:(num_routers_per_dim-1)-1]};
		  
		  assign port_dec
		    = dim_addr_dec_repl[(local_dim_addr+1) +:
					num_neighbors_per_dim];
		  
	       end
	   endcase
	   
	   wire [0:num_neighbors_per_dim-1] 	       mask;
	   assign mask = {num_neighbors_per_dim{route_here}};
	   
	   assign next_port_int[dim*num_neighbors_per_dim:
				(dim+1)*num_neighbors_per_dim-1]
		    = port_dec & mask;
	   
	end
      
      if(num_nodes_per_router > 1)
	begin
	   
	   wire [0:node_addr_width-1] 	     node_addr;
	   assign node_addr
	     = new_next_address[num_dimensions*dim_addr_width:
				num_dimensions*dim_addr_width+node_addr_width
				-1];
	   
	   wire [0:num_nodes_per_router-1]   node_dec;
	   decoder
	     #(.num_ports(num_nodes_per_router))
	   port_addr_dec
	     (.data_in(node_addr),
	      .data_out(node_dec));
	   
	   assign next_port_int[num_dimensions*num_neighbors_per_dim:
				num_ports-1]
		    = node_dec & {num_nodes_per_router{&dim_addr_match}};
	   
	end
      else
	assign next_port_int[num_ports-1] = &dim_addr_match;
      
      genvar 		   op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   assign next_port[op] = next_port_int[op] && (op != port_id);
	   assign error_op[op] = next_port_int[op] && (op == port_id);
	   
	end
      
   endgenerate
   
   assign error = |error_op;
   
endmodule
