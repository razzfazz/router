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

// switch allocator
module vcr_sw_alloc_mac
  (clk, reset, route_ip_ivc_op, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   gnt_nonspec_ip_ivc, gnt_spec_ip_ivc, gnt_ip_op);
   
`include "constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select implementation variant for switch allocator
   parameter allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select implementation variant for wavefront allocator
   // (note: only valid for SW_ALLOCATOR_TYPE_WF_BASE+x
   localparam wf_allocator_type = allocator_type-`SW_ALLOCATOR_TYPE_WF_BASE;
   
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
   
   
   generate
      
      case(allocator_type)
	`SW_ALLOCATOR_TYPE_SEP_IF:
	  begin
	     sw_alloc_core_sep_if
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .reset_type(reset_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.route_ip_ivc_op(route_ip_ivc_op),
		.req_nonspec_ip_ivc(req_nonspec_ip_ivc),
		.req_spec_ip_ivc(req_spec_ip_ivc),
		.gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
		.gnt_spec_ip_ivc(gnt_spec_ip_ivc),
		.gnt_ip_op(gnt_ip_op));
	  end
	`SW_ALLOCATOR_TYPE_SEP_OF:
	  begin
	     sw_alloc_core_sep_of
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .reset_type(reset_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.route_ip_ivc_op(route_ip_ivc_op),
		.req_nonspec_ip_ivc(req_nonspec_ip_ivc),
		.req_spec_ip_ivc(req_spec_ip_ivc),
		.gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
		.gnt_spec_ip_ivc(gnt_spec_ip_ivc),
		.gnt_ip_op(gnt_ip_op));
	  end
      endcase
      
	if(allocator_type >= `SW_ALLOCATOR_TYPE_WF_BASE)
	  begin
	     sw_alloc_core_wf
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .wf_allocator_type(wf_allocator_type),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .reset_type(reset_type))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.route_ip_ivc_op(route_ip_ivc_op),
		.req_nonspec_ip_ivc(req_nonspec_ip_ivc),
		.req_spec_ip_ivc(req_spec_ip_ivc),
		.gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
		.gnt_spec_ip_ivc(gnt_spec_ip_ivc),
		.gnt_ip_op(gnt_ip_op));
	  end
      
   endgenerate
   
endmodule
