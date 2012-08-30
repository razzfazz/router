// $Id$

/*
 Copyright (c) 2007-2012, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

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

// switch allocator synthesis wrapper
module sw_alloc_wrap
  (clk, reset, route_ip_ivc_op, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   gnt_nonspec_ip_ivc, gnt_spec_ip_ivc, gnt_ip_op);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 4;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select implementation variant for switch allocator
   parameter allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select implementation variant for wavefront allocator
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level
   parameter spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs-1] req_nonspec_ip_ivc;
   
   // speculative switch requests
   input [0:num_ports*num_vcs-1] req_spec_ip_ivc;
   
   // grants corresponding to non-speculative requests (to input controller)
   output [0:num_ports*num_vcs-1] gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] gnt_nonspec_ip_ivc;
   
   // grants corresponding to speculative requests (to input controller)
   output [0:num_ports*num_vcs-1] gnt_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] gnt_spec_ip_ivc;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] gnt_ip_op;
   wire [0:num_ports*num_ports-1] gnt_ip_op;
   
   wire [0:num_ports*num_vcs*num_ports-1] route_masked_ip_ivc_op;
   
   generate
      
      genvar 				  ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   genvar itc;
	   
	   for(itc = 0; itc < num_traffic_classes; itc = itc + 1)
	     begin:itcs
		
		genvar irc;
		
		for(irc = 0; irc < num_routing_classes; irc = irc + 1)
		  begin:ircs
		     
		     genvar icvc;
		     
		     for(icvc = 0; icvc < num_vcs_per_class; icvc = icvc + 1)
		       begin:icvcs
			  
			  wire [0:num_ports-1] route_op;
			  assign route_op
			    = route_ip_ivc_op[(((ip*num_traffic_classes+itc)*
						num_routing_classes+irc)*
					       num_vcs_per_class+icvc)*
					      num_ports:
					      (((ip*num_traffic_classes+itc)*
						num_routing_classes+irc)*
					       num_vcs_per_class+icvc+1)*
					      num_ports-1];
			  
			  wire [0:num_ports-1] route_masked_op;
			  wire 		       error;
			  
			  vcr_port_filter
			    #(.num_traffic_classes(num_traffic_classes),
			      .num_routing_classes(num_routing_classes),
			      .num_vcs_per_class(num_vcs_per_class),
			      .num_ports(num_ports),
			      .num_neighbors_per_dim(num_neighbors_per_dim),
			      .num_nodes_per_router(num_nodes_per_router),
			      .restrict_turns(restrict_turns),
			      .routing_function_type(routing_function_type),
			      .port_id(ip),
			      .traffic_class(itc),
			      .routing_class(irc))
			  pf
			    (.route_in_op(route_op),
			     .inc_rc(/*inc_rc*/ 1'b0),
			     .route_out_op(route_masked_op),
			     .error(error));
			  
			  assign route_masked_ip_ivc_op[(((ip*
							   num_traffic_classes+
							   itc)*
							  num_routing_classes+
							  irc)*
							 num_vcs_per_class+
							 icvc)*
							num_ports:
							(((ip*
							   num_traffic_classes+
							   itc)*
							  num_routing_classes+
							  irc)*
							 num_vcs_per_class+
							 icvc+1)*
							num_ports-1]
				   = route_masked_op;
			  
		       end
		     
		  end
		
	     end
	   
	end
      
   endgenerate
   
   vcr_sw_alloc
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .allocator_type(allocator_type),
       .arbiter_type(arbiter_type),
       .spec_level(spec_level),
       .reset_type(reset_type))
   swa
     (.clk(clk),
      .reset(reset),
      .route_ip_ivc_op(route_masked_ip_ivc_op),
      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
      .req_spec_ip_ivc(req_spec_ip_ivc),
      .gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
      .gnt_spec_ip_ivc(gnt_spec_ip_ivc),
      .gnt_ip_op(gnt_ip_op));
   
endmodule
