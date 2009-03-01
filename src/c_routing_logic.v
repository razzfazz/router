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

// module to determine the output port and VC based on routing information 
// (e.g. destination address) and the current input port and VC)
module c_routing_logic
  (router_address, hop_route_info, route_op, inc_rc, error);
   
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
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // nuber of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
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
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // ID of current port
   parameter port_id = 0;
   
   // current traffic class
   parameter traffic_class = 0;
   
   // current routing class
   parameter routing_class = 0;
   
   // total number of bits required for storing routing information
   localparam hop_route_info_width
     = (routing_class == (num_routing_classes - 1)) ?
       addr_width :
       router_addr_width;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // routing data
   input [0:hop_route_info_width-1] hop_route_info;
   
   // output port to forward to
   output [0:num_ports-1] route_op;
   wire [0:num_ports-1] route_op;
   
   // if we have reached our destination for the current routing class, 
   // increment the routing class (unless it's already the highest)
   output inc_rc;
   wire 		inc_rc;
   
   // internal error condition detected
   output error;
   wire 		error;   
   
   // address of destination router for current routing class
   wire [0:router_addr_width-1] dest_router_address;
   assign dest_router_address
     = hop_route_info[0:router_addr_width-1];
   
   wire 			reached_dest;
   assign reached_dest = (router_address == dest_router_address);
   
   wire [0:num_ports-1] 	route_unmasked_op;
   wire [0:num_dimensions-1] 	dim_addr_match;
   
   generate
   
      if(routing_class == (num_routing_classes - 1))
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
	   
	   if((dimension_order == `DIMENSION_ORDER_ASCENDING) ||
	      ((dimension_order == `DIMENSION_ORDER_BY_CLASS) &&
	       ((routing_class % 2) == 0)))
	     begin
		if(dim == 0)
		  assign dim_sel = ~dim_addr_match[dim];
		else
		  assign dim_sel = &dim_addr_match[0:dim-1] &
				   ~dim_addr_match[dim];
	     end
	   else if((dimension_order == `DIMENSION_ORDER_DESCENDING) ||
		   ((dimension_order == `DIMENSION_ORDER_BY_CLASS) &&
		    ((routing_class % 2) == 1)))
	     begin
		if(dim == (num_dimensions - 1))
		  assign dim_sel = ~dim_addr_match[dim];
		else
		  assign dim_sel = ~dim_addr_match[dim] &
				   dim_addr_match[(dim+1):(num_dimensions-1)];
	     end
	   
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
	   
	   assign route_unmasked_op[dim*num_neighbors_per_dim:
				    (dim+1)*num_neighbors_per_dim-1]
		    = port_dec & {num_neighbors_per_dim{dim_sel}};
	   
	end
      
      if(routing_class == (num_routing_classes - 1))
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
		
		assign route_unmasked_op[num_ports-num_nodes_per_router:
					 num_ports-1]
			 = node_sel & {num_nodes_per_router{&dim_addr_match}};
		
	     end
	   else
	     assign route_unmasked_op[num_ports-1] = &dim_addr_match;
	   
	end
      else
	assign route_unmasked_op[num_ports-num_nodes_per_router:num_ports-1]
		 = {num_nodes_per_router{1'b0}};
      
   endgenerate
   
   c_port_filter
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_ports(num_ports),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .num_nodes_per_router(num_nodes_per_router),
       .restrict_turns(restrict_turns),
       .routing_function_type(routing_function_type),
       .port_id(port_id),
       .traffic_class(traffic_class),
       .routing_class(routing_class))
   pf
     (.route_in_op(route_unmasked_op),
      .inc_rc(inc_rc),
      .route_out_op(route_op),
      .error(error));
   
endmodule
