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

// synopsys_translate off
`default_nettype none
// synopsys_translate on

// routing logic for VC router
module vcr_routing_logic
  (router_address, hop_route_info, route_port, inc_rc);
   
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
   
   // nuber of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
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
   
   // current resource class
   parameter resource_class = 0;
   
   // total number of bits required for storing routing information
   localparam hop_route_info_width
     = (resource_class == (num_resource_classes - 1)) ?
       addr_width :
       router_addr_width;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // routing data
   input [0:hop_route_info_width-1] hop_route_info;
   
   // output port to forward to
   output [0:port_idx_width-1] route_port;
   wire [0:port_idx_width-1] route_port;
   
   // if we have reached our destination for the current resource class, 
   // increment the resource class (unless it's already the highest)
   output inc_rc;
   wire 		inc_rc;
   
   // address of destination router for current resource class
   wire [0:router_addr_width-1] dest_router_address;
   assign dest_router_address
     = hop_route_info[0:router_addr_width-1];
   
   wire 			reached_dest;
   assign reached_dest = (router_address == dest_router_address);
   
   wire [0:num_ports-1] 	route_op;
   wire [0:num_dimensions-1] 	dim_addr_match;
   
   generate
   
      if(resource_class == (num_resource_classes - 1))
	assign inc_rc = 1'b0;
      else
	assign inc_rc = reached_dest;
      
      genvar 			dim;
      
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   wire [0:dim_addr_width-1] dim_addr;
	   assign dim_addr
	     = dest_router_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   wire [0:dim_addr_width-1] local_dim_addr;
	   assign local_dim_addr
	     = router_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   assign dim_addr_match[dim] = (dim_addr == local_dim_addr);
	   
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
	   
	   case(routing_function_type)
	     
	     `ROUTING_FUNCTION_TYPE_MESH:
	       begin
		  
		  assign port_dec
		    = {dim_addr < local_dim_addr, dim_addr > local_dim_addr};
		  
	       end
	     
	     `ROUTING_FUNCTION_TYPE_FBFLY:
	       begin
		  
		  wire [0:num_routers_per_dim-1] dim_addr_dec;
		  c_decoder
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
	   
	   assign route_op[dim*num_neighbors_per_dim:
			   (dim+1)*num_neighbors_per_dim-1]
		    = port_dec & {num_neighbors_per_dim{dim_sel}};
	   
	end
      
      if(resource_class == (num_resource_classes - 1))
	begin
	   
	   if(num_nodes_per_router > 1)
	     begin
		
		wire [0:node_addr_width-1] 	dest_node_address;
		assign dest_node_address
		  = hop_route_info[router_addr_width:hop_route_info_width-1];
		
		wire [0:num_nodes_per_router-1] node_sel;
		c_decoder
		  #(.num_ports(num_nodes_per_router))
		node_sel_dec
		  (.data_in(dest_node_address),
		   .data_out(node_sel));
		
		assign route_op[num_ports-num_nodes_per_router:num_ports-1]
			 = node_sel & {num_nodes_per_router{&dim_addr_match}};
		
	     end
	   else
	     assign route_op[num_ports-1] = &dim_addr_match;
	   
	end
      else
	assign route_op[num_ports-num_nodes_per_router:num_ports-1]
		 = {num_nodes_per_router{1'b0}};
      
   endgenerate
   
   c_encoder
     #(.num_ports(num_ports))
   route_port_enc
     (.data_in(route_op),
      .data_out(route_port));
   
endmodule
