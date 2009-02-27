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

// VC allocator
module vcr_vc_alloc_mac
  (clk, reset, route_ip_ivc_op, inc_rc_ip_ivc, elig_op_ovc, req_ip_ivc, 
   gnt_ip_ivc, gnt_ip_ivc_ovc, gnt_op_ovc, gnt_op_ovc_ip, gnt_op_ovc_ivc);
   
`include "constants.v"
   
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
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for VC allocator
   parameter allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select implementation variant for wavefront allocator
   // (note: only valid for VC_ALLOCATOR_TYPE_WF_BASE+x
   localparam wf_allocator_type = allocator_type-`VC_ALLOCATOR_TYPE_WF_BASE;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
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
   
   generate
      
      case(allocator_type)
	`VC_ALLOCATOR_TYPE_SEP_IF:
	  begin
	     vc_alloc_core_sep_if
	       #(.num_traffic_classes(num_traffic_classes),
		 .num_routing_classes(num_routing_classes),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .reset_type(reset_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.route_ip_ivc_op(route_ip_ivc_op),
		.inc_rc_ip_ivc(inc_rc_ip_ivc),
		.elig_op_ovc(elig_op_ovc),
		.req_ip_ivc(req_ip_ivc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc),
		.gnt_op_ovc_ip(gnt_op_ovc_ip),
		.gnt_op_ovc_ivc(gnt_op_ovc_ivc));
	  end
	`VC_ALLOCATOR_TYPE_SEP_OF:
	  begin
	     vc_alloc_core_sep_of
	       #(.num_traffic_classes(num_traffic_classes),
		 .num_routing_classes(num_routing_classes),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .reset_type(reset_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.route_ip_ivc_op(route_ip_ivc_op),
		.inc_rc_ip_ivc(inc_rc_ip_ivc),
		.elig_op_ovc(elig_op_ovc),
		.req_ip_ivc(req_ip_ivc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc),
		.gnt_op_ovc_ip(gnt_op_ovc_ip),
		.gnt_op_ovc_ivc(gnt_op_ovc_ivc));
	  end
      endcase
      
      if(allocator_type >= `VC_ALLOCATOR_TYPE_WF_BASE)
	begin
	   vc_alloc_core_wf
	       #(.num_traffic_classes(num_traffic_classes),
		 .num_routing_classes(num_routing_classes),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .wf_allocator_type(wf_allocator_type),
		 .reset_type(reset_type))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.route_ip_ivc_op(route_ip_ivc_op),
		.inc_rc_ip_ivc(inc_rc_ip_ivc),
		.elig_op_ovc(elig_op_ovc),
		.req_ip_ivc(req_ip_ivc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc),
		.gnt_op_ovc_ip(gnt_op_ovc_ip),
		.gnt_op_ovc_ivc(gnt_op_ovc_ivc));
	end
      
   endgenerate
   
endmodule
