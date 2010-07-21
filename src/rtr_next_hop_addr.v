// $Id$

/*
Copyright (c) 2007-2010, Trustees of The Leland Stanford Junior University
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



// lookahead routing logic for VC router
module rtr_next_hop_addr
  (router_address, route_port, sel_rc, route_info, next_router_address);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // nuber of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = ((connectivity == `CONNECTIVITY_LINE) ||
	(connectivity == `CONNECTIVITY_RING)) ?
       2 :
       (connectivity == `CONNECTIVITY_FULL) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // current resource class
   parameter resource_class = 0;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // current resource class
   input [0:num_resource_classes-1] sel_rc;
   
   // routing data
   input [0:route_info_width-1] route_info;
   
   // port on which the packet will leave the current router
   input [0:port_idx_width-1] route_port;
   
   // lookahead routing information for next router
   output [0:router_addr_width-1] next_router_address;
   wire [0:router_addr_width-1] next_router_address;
   
   // all router addresses (intermediate + final)
   wire [0:num_resource_classes*router_addr_width-1] route_info_addresses;
   assign route_info_addresses
     = route_info[0:num_resource_classes*router_addr_width-1];
   
   // address of destination router for current resource class
   wire [0:router_addr_width-1]   dest_router_address;
   c_select_1ofn
     #(.num_ports(num_resource_classes),
       .width(router_addr_width))
   dest_router_address_sel
     (.select(sel_rc),
      .data_in(route_info_addresses),
      .data_out(dest_router_address));
   
   wire [0:num_ports-1] 	  route_op;
   c_decode
     #(.num_ports(num_ports))
   route_op_dec
     (.data_in(route_port),
      .data_out(route_op));
   
   generate
      
      genvar 			  dim;
      
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   wire [0:dim_addr_width-1] dest_dim_addr;
	   assign dest_dim_addr
	     = dest_router_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
           wire [0:dim_addr_width-1] curr_dim_addr;
           assign curr_dim_addr
             = router_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
           
	   wire [0:dim_addr_width-1] next_dim_addr;
	   
	   assign next_router_address[dim*dim_addr_width:
				      (dim+1)*dim_addr_width-1]
	     = next_dim_addr;
	   
	   case(connectivity)
	     
	     `CONNECTIVITY_LINE:
	       begin
		  
		  wire route_down;
		  assign route_down = route_op[dim*2];
		  
		  wire route_up;
		  assign route_up = route_op[dim*2+1];
		  
		  // Assemble a delta value for the address segment 
		  // corresponding to the current dimension; the delta can have 
		  // the values -1 (i.e., all ones in two's complement), 0 or 1.
		  
		  wire [0:dim_addr_width-1] addr_delta;
		  if(dim_addr_width > 1)
		    assign addr_delta[0:dim_addr_width-2]
		      = {(dim_addr_width-1){route_down}};
		  assign addr_delta[dim_addr_width-1] = route_down | route_up;
		  
		  assign next_dim_addr = curr_dim_addr + addr_delta;
		  
	       end
	     
	     `CONNECTIVITY_RING:
	       begin
		  
		  wire [0:dim_addr_width-1] dim_addr_plus1;
		  c_incr
		    #(.width(dim_addr_width),
		      .min_value(0),
		      .max_value(num_routers_per_dim-1))
		  dim_addr_plus1_incr
		    (.data_in(curr_dim_addr),
		     .data_out(dim_addr_plus1));
		  
		  wire [0:dim_addr_width-1] dim_addr_minus1;
		  c_decr
		    #(.width(dim_addr_width),
		      .min_value(0),
		      .max_value(num_routers_per_dim-1))
		  dim_addr_minus1_decr
		    (.data_in(curr_dim_addr),
		     .data_out(dim_addr_minus1));
		  
		  // The first port in each dimension connects to smaller 
		  // neighbors, while the second one connects to larger ones.
		  // Thus, interpreted as a two-bit value, we get 0 if neither
		  // of the ports is selected, 1 if the second port is selected
		  // (route up) and 2 if the first port is selected (route 
		  // down); the value 3 is a don't-care, as route_op is the
		  // output of a decoder, so at most one of the bits can be set.
		  
		  wire [0:1] 		    route_sel;
		  assign route_sel = route_op[dim*2:(dim+1)*2-1];
		  
		  wire [0:3*dim_addr_width-1] next_dim_addrs;
		  assign next_dim_addrs
		    = {curr_dim_addr, dim_addr_plus1, dim_addr_minus1};
		  
		  assign next_dim_addr
		    = next_dim_addrs[route_sel*dim_addr_width +: 
				     dim_addr_width];
		  
	       end
	     
	     `CONNECTIVITY_FULL:
	       begin
		  
		  // With full connectivity, if one of the ports in a given
		  // dimension is selected, the corresponding part of the 
		  // address will be changed to the respective part of the 
		  // destination address when going to the next hop.
		  
		  wire route_dest;
		  assign route_dest
		    = |route_op[dim*num_neighbors_per_dim:
				(dim+1)*num_neighbors_per_dim-1];
		  
		  assign next_dim_addr
		    = route_dest ? dest_dim_addr : curr_dim_addr;
		  
	       end
	     
	   endcase
	   
	end
      
   endgenerate
   
endmodule
