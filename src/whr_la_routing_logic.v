// $Id$

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list
of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this 
list of conditions and the following disclaimer in the documentation and/or 
other materials provided with the distribution.
Neither the name of the Stanford University nor the names of its contributors 
may be used to endorse or promote products derived from this software without 
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR 
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON 
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// lookahead routing logic for wormhole router
module whr_la_routing_logic
  (router_address, route_op, route_info, la_route_info);
   
`include "c_constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required for lookahead routing information
   localparam la_route_info_width = port_idx_width;
   
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
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // total number of bits required for storing routing information
   localparam route_info_width = addr_width;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // port on which the packet will leave the current router
   input [0:num_ports-1] route_op;
   
   // routing data
   input [0:route_info_width-1] route_info;
   
   // lookahead routing information for next router
   output [0:la_route_info_width-1] la_route_info;
   wire [0:la_route_info_width-1] la_route_info;
   
   // address of destination router
   wire [0:router_addr_width-1]   dest_router_address;
   assign dest_router_address = route_info[0:router_addr_width-1];
   
   // address of the downstream router
   wire [0:router_addr_width-1]   next_router_address;
   
   wire [0:num_dimensions-1] 	  dim_addr_match;
   
   wire [0:num_ports-1] 	  next_route_op;
   
   wire 			  eject;
   assign eject = &dim_addr_match;
   
   genvar 			  dim;
   
   generate
      
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   wire [0:dim_addr_width-1] dest_dim_addr;
	   assign dest_dim_addr
	     = dest_router_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   wire [0:dim_addr_width-1] curr_dim_addr;
	   assign curr_dim_addr
	     = router_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   wire [0:dim_addr_width-1] next_dim_addr;
	   
	   assign dim_addr_match[dim] = (next_dim_addr == dest_dim_addr);
	   
	   wire 		     dim_sel;
	   
	   case(dimension_order)
	     
	     `DIMENSION_ORDER_ASCENDING:
	       begin
		  if(dim == 0)
		    assign dim_sel = ~dim_addr_match[dim];
		  else
		    assign dim_sel = &dim_addr_match[0:dim-1] &
				     ~dim_addr_match[dim];
	       end
	     
	     `DIMENSION_ORDER_DESCENDING:
	       begin
		  if(dim == (num_dimensions - 1))
		    assign dim_sel = ~dim_addr_match[dim];
		  else
		    assign dim_sel = ~dim_addr_match[dim] &
				     dim_addr_match[(dim+1):(num_dimensions-1)];
	       end
	     
	   endcase
	   
	   wire [0:num_neighbors_per_dim-1] port_dec;
	   
	   assign next_router_address[dim*dim_addr_width:
				      (dim+1)*dim_addr_width-1]
		    = next_dim_addr;
	   
	   case(routing_function_type)
	     
	     `ROUTING_FUNCTION_TYPE_MESH:
	       begin
		  
		  wire 			    route_down;
		  assign route_down = route_op[dim*num_neighbors_per_dim];
		  
		  wire 			    route_up;
		  assign route_up = route_op[dim*num_neighbors_per_dim+1];
		  
		  // Assemble a delta value for the address segment 
		  // corresponding to the current dimension; the delta can have
		  // the values -1 (i.e., all ones in two's complement), 0 or 1
		  wire [0:dim_addr_width-1] addr_delta;
		  if(dim_addr_width > 1)
		    assign addr_delta[0:dim_addr_width-2]
			     = {(dim_addr_width-1){route_down}};
		  assign addr_delta[dim_addr_width-1] = route_down | route_up;
		  
		  assign next_dim_addr = curr_dim_addr + addr_delta;
		  
		  assign port_dec
		    = {next_dim_addr < dest_dim_addr,
		       next_dim_addr > dest_dim_addr};
		  
	       end
	     
	     `ROUTING_FUNCTION_TYPE_FBFLY:
	       begin
		  
		  wire route_dest;
		  assign route_dest
		    = |route_op[dim*num_neighbors_per_dim:
				(dim+1)*num_neighbors_per_dim-1];
		  
		  assign next_dim_addr
		    = route_dest ? dest_dim_addr : curr_dim_addr;
		  
		  wire [0:num_routers_per_dim-1] dest_dim_addr_dec;
		  c_decoder
		    #(.num_ports(num_routers_per_dim))
		  dest_dim_addr_dec_dec
		    (.data_in(dest_dim_addr),
		     .data_out(dest_dim_addr_dec));
		  
		  wire [0:(2*num_routers_per_dim-1)-1] dest_dim_addr_dec_repl;
		  assign dest_dim_addr_dec_repl
		    = {dest_dim_addr_dec,
		       dest_dim_addr_dec[0:(num_routers_per_dim-1)-1]};
		  
		  assign port_dec
		    = dest_dim_addr_dec_repl[(next_dim_addr+1) +:
					     num_neighbors_per_dim];
		  
	       end
	     
	   endcase
	   
	   assign next_route_op[dim*num_neighbors_per_dim:
				(dim+1)*num_neighbors_per_dim-1]
		    = port_dec & {num_neighbors_per_dim{dim_sel}};
	   
	end
      
      if(num_nodes_per_router > 1)
	begin
	   
	   wire [0:node_addr_width-1] 	dest_node_address;
	   assign dest_node_address
	     = route_info[route_info_width-node_addr_width:route_info_width-1];
	   
	   wire [0:num_nodes_per_router-1] node_sel;
	   c_decoder
	     #(.num_ports(num_nodes_per_router))
	   node_sel_dec
	     (.data_in(dest_node_address),
	      .data_out(node_sel));
	   
	   assign next_route_op[num_ports-num_nodes_per_router:num_ports-1]
		    = node_sel & {num_nodes_per_router{eject}};
	   
	end
      else
	assign next_route_op[num_ports-1] = eject;
      
   endgenerate
   
   wire [0:port_idx_width-1] 		   next_route_port;
   c_encoder
     #(.num_ports(num_ports))
   next_route_port_enc
     (.data_in(next_route_op),
      .data_out(next_route_port));
   
   assign la_route_info[0:port_idx_width-1] = next_route_port;
   
endmodule
