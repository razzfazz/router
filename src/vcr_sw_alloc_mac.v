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



// switch allocator for VC router
module vcr_sw_alloc_mac
  (clk, reset, route_port_ip_ivc, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   gnt_nonspec_ip_ivc, gnt_spec_ip_ivc, gnt_op_ip);
   
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
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
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
   input [0:num_ports*num_vcs*port_idx_width-1] route_port_ip_ivc;
   
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
   output [0:num_ports*num_ports-1] gnt_op_ip;
   wire [0:num_ports*num_ports-1] gnt_op_ip;
   
   
   generate
      
      case(allocator_type)
	`SW_ALLOCATOR_TYPE_SEP_IF:
	  begin
	     vcr_sw_alloc_sep_if
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .reset_type(reset_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.route_port_ip_ivc(route_port_ip_ivc),
		.req_nonspec_ip_ivc(req_nonspec_ip_ivc),
		.req_spec_ip_ivc(req_spec_ip_ivc),
		.gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
		.gnt_spec_ip_ivc(gnt_spec_ip_ivc),
		.gnt_op_ip(gnt_op_ip));
	  end
	`SW_ALLOCATOR_TYPE_SEP_OF:
	  begin
	     vcr_sw_alloc_sep_of
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .reset_type(reset_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.route_port_ip_ivc(route_port_ip_ivc),
		.req_nonspec_ip_ivc(req_nonspec_ip_ivc),
		.req_spec_ip_ivc(req_spec_ip_ivc),
		.gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
		.gnt_spec_ip_ivc(gnt_spec_ip_ivc),
		.gnt_op_ip(gnt_op_ip));
	  end
      endcase
      
      if(allocator_type >= `SW_ALLOCATOR_TYPE_WF_BASE)
	begin
	   vcr_sw_alloc_wf
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .wf_allocator_type(wf_allocator_type),
	       .arbiter_type(arbiter_type),
	       .spec_level(spec_level),
	       .reset_type(reset_type))
	   core_wf
	     (.clk(clk),
	      .reset(reset),
	      .route_port_ip_ivc(route_port_ip_ivc),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .gnt_nonspec_ip_ivc(gnt_nonspec_ip_ivc),
	      .gnt_spec_ip_ivc(gnt_spec_ip_ivc),
	      .gnt_op_ip(gnt_op_ip));
	end
      
   endgenerate
   
endmodule
