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

// VC allocator synthesis wrapper
module vc_alloc_wrap
  (clk, reset, route_port_ip_ivc, inc_rc_ip_ivc, elig_op_ovc, req_ip_ivc, 
   gnt_ip_ivc, gnt_ip_ivc_ovc, gnt_op_ovc, gnt_op_ovc_ip, gnt_op_ovc_ivc);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // compute ceiling of base-th root of argument
   function integer croot(input integer argument, input integer base);
      integer 		     i;
      integer 		     j;
      begin
	 croot = 0;
	 i = 0;
	 while(i < argument)
	   begin
	      croot = croot + 1;
	      i = 1;
	      for(j = 0; j < base; j = j + 1)
		i = i * croot;
	   end
      end
   endfunction
   
   // select network topology
   parameter network_topology = `NETWORK_TOPOLOGY_FBFLY;
   
   // number of traffic classes (e.g. request, reply)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // total number of nodes
   parameter num_nodes = 64;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 4;
   
   // total number of routers
   localparam num_routers
     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   
   // number of routers in each dimension
   localparam num_routers_per_dim = croot(num_routers, num_dimensions);
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       2 :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // select routing function type
   localparam routing_function_type
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       `ROUTING_FUNCTION_TYPE_MESH :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       `ROUTING_FUNCTION_TYPE_FBFLY :
       -1;
   
   // select implementation variant for VC allocator
   parameter allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*port_idx_width-1] route_port_ip_ivc;
   
   // transition to next routing class
   input [0:num_ports*num_vcs-1] inc_rc_ip_ivc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // request VC allocation
   input [0:num_ports*num_vcs-1] req_ip_ivc;
   
   // VC allocation successful (to input controller)
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   wire [0:num_ports*num_vcs-1] gnt_ip_ivc;
   
   // granted output VC (to input controller)
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 	gnt_op_ovc;
   
   // input port that each output VC was granted to
   output [0:num_ports*num_vcs*num_ports-1] gnt_op_ovc_ip;
   wire [0:num_ports*num_vcs*num_ports-1] gnt_op_ovc_ip;
   
   // input VC that each output VC was granted to
   output [0:num_ports*num_vcs*num_vcs-1] gnt_op_ovc_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1]   gnt_op_ovc_ivc;
   
   vcr_vc_alloc_mac
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .arbiter_type(arbiter_type),
       .allocator_type(allocator_type),
       .reset_type(reset_type))
   vca
     (.clk(clk),
      .reset(reset),
      .route_port_ip_ivc(route_port_ip_ivc),
      .inc_rc_ip_ivc(inc_rc_ip_ivc),
      .elig_op_ovc(elig_op_ovc),
      .req_ip_ivc(req_ip_ivc),
      .gnt_ip_ivc(gnt_ip_ivc),
      .gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
      .gnt_op_ovc(gnt_op_ovc),
      .gnt_op_ovc_ip(gnt_op_ovc_ip),
      .gnt_op_ovc_ivc(gnt_op_ovc_ivc));
   
endmodule
