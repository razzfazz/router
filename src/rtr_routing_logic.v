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



// routing logic for VC router
module rtr_routing_logic
  (router_address, sel_mc, sel_irc, route_info, route_op, inc_rc);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
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
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // select current message class
   input [0:num_message_classes-1] sel_mc;
   
   // select current resource class
   input [0:num_resource_classes-1] sel_irc;
   
   // routing data
   input [0:route_info_width-1] route_info;
   
   // output port to forward to
   output [0:num_ports-1] route_op;
   wire [0:num_ports-1] route_op;
   
   // if we have reached our destination for the current resource class, 
   // increment the resource class (unless it's already the highest)
   output inc_rc;
   wire 		inc_rc;
   
   // all router addresses (intermediate + final)
   wire [0:num_resource_classes*router_addr_width-1] route_info_addresses;
   assign route_info_addresses
     = route_info[0:num_resource_classes*router_addr_width-1];
   
   // address of destination router for current resource class
   wire [0:router_addr_width-1] 		     dest_router_address;
   c_select_1ofn
     #(.width(router_addr_width),
       .num_ports(num_resource_classes))
   dest_router_address_sel
     (.select(sel_irc),
      .data_in(route_info_addresses),
      .data_out(dest_router_address));
   
   wire 					     reached_dest;
   assign reached_dest = (router_address == dest_router_address);
   
   wire 					     final_rc;
   assign final_rc = sel_irc[num_resource_classes-1];
   
   assign inc_rc = reached_dest & ~final_rc;
   
   wire [0:num_dimensions-1] 			     dim_addr_match;
   
   generate
      
      case(routing_type)
	
	`ROUTING_TYPE_DOR:
	  begin
	     
	     genvar dim;
	     
	     for(dim = 0; dim < num_dimensions; dim = dim + 1)
	       begin:dims
		  
		  wire [0:dim_addr_width-1] dest_dim_addr;
		  assign dest_dim_addr
		    = dest_router_address[dim*dim_addr_width:
					  (dim+1)*dim_addr_width-1];
		  
		  wire [0:dim_addr_width-1] curr_dim_addr;
		  assign curr_dim_addr
		    = router_address[dim*dim_addr_width:
				     (dim+1)*dim_addr_width-1];
		  
		  assign dim_addr_match[dim] = (dest_dim_addr == curr_dim_addr);
		  
		  wire 			    dim_sel;
		  
		  case(dim_order)
		    
		    `DIM_ORDER_ASCENDING:
		      begin
			 if(dim == 0)
			   assign dim_sel = 1'b1;
			 else
			   assign dim_sel = &dim_addr_match[0:dim-1];
		      end
		    
		    `DIM_ORDER_DESCENDING:
		      begin
			 if(dim == (num_dimensions - 1))
			   assign dim_sel = 1'b1;
			 else
			   assign dim_sel
			     = &dim_addr_match[dim+1:num_dimensions-1];
		    end
		    
		    `DIM_ORDER_BY_CLASS:
		      begin
			 
			 wire [0:num_message_classes-1] shuffled_mcs;
			 c_interleaver
			   #(.width(num_message_classes),
			     .num_blocks(num_message_classes/2))
			 shuffled_mcs_intl
			   (.data_in(sel_mc),
			    .data_out(shuffled_mcs));
			 
			 wire mc_even;
			 assign mc_even
			   = |shuffled_mcs[0:(num_message_classes/2)-1];
			 
			 if(num_dimensions == 1)
			   assign dim_sel = 1'b1;
			 else if(dim == 0)
			   assign dim_sel
			     = &dim_addr_match[1:num_dimensions-1] | mc_even;
			 else if(dim == (num_dimensions - 1))
			   assign dim_sel
			     = &dim_addr_match[0:num_dimensions-2] | ~mc_even;
			 else
			   assign dim_sel
			     = mc_even ? 
			       &dim_addr_match[0:dim-1] : 
			       &dim_addr_match[dim+1:num_dimensions-1];
			 
		      end
		    
		  endcase
		  
		  wire 	      curr_gt_dest;
		  assign curr_gt_dest = (curr_dim_addr > dest_dim_addr);
		  
		  wire 	      curr_lt_dest;
		  assign curr_lt_dest = (curr_dim_addr < dest_dim_addr);
		  
		  wire [0:num_neighbors_per_dim-1] port_dec;
		  
		  case(connectivity)
		    
		    `CONNECTIVITY_LINE:
		      begin
			 
			 assign port_dec = {curr_gt_dest, curr_lt_dest};
			 
		      end
		    
		    `CONNECTIVITY_RING, `CONNECTIVITY_FULL:
		      begin
			 
			 // compute distance in upwards direction
			 wire [0:dim_addr_width-1] dim_addr_diff_up;
			 assign dim_addr_diff_up
			   = dest_dim_addr - curr_dim_addr;
			 
			 // compute distance in downwards direction
			 wire [0:dim_addr_width-1] dim_addr_diff_down;
			 assign dim_addr_diff_down
			   = curr_dim_addr - dest_dim_addr;
			 
			 case(connectivity)
			   
			   `CONNECTIVITY_RING:
			     begin
				
				// In cases where the destination is equally far
				// away in either direction, we need some kind 
				// of tie breaker to avoid load imbalance; one 
				// simple solution is to break the tie based on 
				// whether the current router's address is even 
				// or odd.
				// NOTE: This can create load balance when using
				// concentration, as all nodes sharing a router 
				// will pick the same direction.
				wire tie_break;
				assign tie_break
				  = curr_dim_addr[dim_addr_width-1];
				
			 	// multiply by 2 and add tiebreaker
				
				wire [0:dim_addr_width] dim_addr_diff_up_x2;
				assign dim_addr_diff_up_x2
				  = {dim_addr_diff_up, tie_break};
				
				wire [0:dim_addr_width] dim_addr_diff_down_x2;
				assign dim_addr_diff_down_x2
				  = {dim_addr_diff_down, ~tie_break};
				
				wire 			route_down;
				assign route_down
				  = (curr_lt_dest && 
				     (dim_addr_diff_up_x2 > 
				      num_routers_per_dim)) ||
				    (curr_gt_dest && 
				     (dim_addr_diff_down_x2 <= 
				      num_routers_per_dim));
				
				wire 			route_up;
				assign route_down
				  = (curr_lt_dest && 
				     (dim_addr_diff_up_x2 <= 
				      num_routers_per_dim)) ||
				    (curr_gt_dest && 
				     (dim_addr_diff_down_x2 > 
				      num_routers_per_dim));
				
				assign port_dec = {route_down, route_up};
				
			     end
			   
			   `CONNECTIVITY_FULL:
			     begin
				
				wire [0:num_routers_per_dim-1] port_sel_up;
				c_decode
				  #(.num_ports(num_routers_per_dim))
				port_sel_up_dec
				  (.data_in(dim_addr_diff_up),
				   .data_out(port_sel_up));
				
				wire [0:num_routers_per_dim-1] port_sel_down_r;
				c_decode
				  #(.num_ports(num_routers_per_dim))
				port_sel_down_r_dec
				  (.data_in(dim_addr_diff_down),
				   .data_out(port_sel_down_r));
				
				wire [0:num_routers_per_dim-1] port_sel_down;
				c_reverse
				  #(.width(num_routers_per_dim))
				port_sel_down_rev
				  (.data_in(port_sel_down_r),
				   .data_out(port_sel_down));
				
				wire [0:num_neighbors_per_dim-1] port_dec_up;
				assign port_dec_up
				  = port_sel_up[1:num_routers_per_dim-1];
				
				wire [0:num_neighbors_per_dim-1] port_dec_down;
				assign port_dec_down
				  = port_sel_down[0:num_routers_per_dim-2];
				
				c_select_mofn
				  #(.num_ports(2),
				    .width(num_neighbors_per_dim))
				port_dec_sel
				  (.select({curr_gt_dest, curr_lt_dest}),
				   .data_in({port_dec_down, port_dec_up}),
				   .data_out(port_dec));
				
			     end
			   
			 endcase
			 
		      end
		    
		  endcase
		  
		  assign route_op[dim*num_neighbors_per_dim:
				  (dim+1)*num_neighbors_per_dim-1]
		    = port_dec & {num_neighbors_per_dim{dim_sel}};
		  
	       end
	     
	  end
	
      endcase
      
      wire 						      eject;
      assign eject = &dim_addr_match & final_rc;
      
      if(num_nodes_per_router > 1)
	begin
	   
	   wire [0:node_addr_width-1] dest_node_address;
	   assign dest_node_address
	     = route_info[route_info_width-node_addr_width:route_info_width-1];
	   
	   wire [0:num_nodes_per_router-1] node_sel;
	   c_decode
	     #(.num_ports(num_nodes_per_router))
	   node_sel_dec
	     (.data_in(dest_node_address),
	      .data_out(node_sel));
	   
	   assign route_op[num_ports-num_nodes_per_router:num_ports-1]
		    = node_sel & {num_nodes_per_router{eject}};
	   
	end
      else
	assign route_op[num_ports-1] = eject;
      
   endgenerate
   
endmodule
