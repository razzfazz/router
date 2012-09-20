// $Id$

/*
 Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
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

//==============================================================================
// switch allocator for VC router
//==============================================================================

module vcr_sw_alloc_mac
  (clk, reset, active_ip, active_op, route_ip_ivc_op, req_nonspec_ip_ivc, 
   req_spec_ip_ivc, gnt_ip, sel_ip_ivc, gnt_op, sel_op_ip, sel_op_ivc);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select implementation variant for switch allocator
   parameter allocator_type = `SW_ALLOC_TYPE_SEP_IF;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN_BINARY;
   
   // select speculation type
   parameter spec_type = `SW_ALLOC_SPEC_TYPE_REQ;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // clock enable signals
   input [0:num_ports-1] active_ip;
   input [0:num_ports-1] active_op;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_nonspec_ip_ivc;
   
   // speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_spec_ip_ivc;
   
   // grants
   output [0:num_ports-1] 		   gnt_ip;
   wire [0:num_ports-1] 		   gnt_ip;
   
   // indicate which VC at a given port is granted
   output [0:num_ports*num_vcs-1] 	   sel_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_ip_ivc;
   
   // grants for output ports
   output [0:num_ports-1] 		   gnt_op;
   wire [0:num_ports-1] 		   gnt_op;
   
   // selected input ports (if any)
   output [0:num_ports*num_ports-1] 	   sel_op_ip;
   wire [0:num_ports*num_ports-1] 	   sel_op_ip;
   
   // selected input VCs (if any)
   output [0:num_ports*num_vcs-1] 	   sel_op_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_op_ivc;
   
   generate
      
      if(allocator_type == `SW_ALLOC_TYPE_SEP_IF)
	begin
	   vcr_sw_alloc_sep_if
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .spec_type(spec_type),
	       .reset_type(reset_type))
	   core_sep_if
	     (.clk(clk),
	      .reset(reset),
	      .active_ip(active_ip),
	      .active_op(active_op),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .gnt_ip(gnt_ip),
	      .sel_ip_ivc(sel_ip_ivc),
	      .gnt_op(gnt_op),
	      .sel_op_ip(sel_op_ip),
	      .sel_op_ivc(sel_op_ivc));
	end
      else if(allocator_type == `SW_ALLOC_TYPE_SEP_OF)
	begin
	   vcr_sw_alloc_sep_of
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .spec_type(spec_type),
	       .reset_type(reset_type))
	   core_sep_of
	     (.clk(clk),
	      .reset(reset),
	      .active_ip(active_ip),
	      .active_op(active_op),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .gnt_ip(gnt_ip),
	      .sel_ip_ivc(sel_ip_ivc),
	      .gnt_op(gnt_op),
	      .sel_op_ip(sel_op_ip),
	      .sel_op_ivc(sel_op_ivc));
	end
      else if((allocator_type >= `SW_ALLOC_TYPE_WF_BASE) &&
	      (allocator_type <= `SW_ALLOC_TYPE_WF_LIMIT))
	begin
	   vcr_sw_alloc_wf
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .wf_alloc_type(allocator_type - `SW_ALLOC_TYPE_WF_BASE),
	       .arbiter_type(arbiter_type),
	       .spec_type(spec_type),
	       .reset_type(reset_type))
	   core_wf
	     (.clk(clk),
	      .reset(reset),
	      .active_ip(active_ip),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .gnt_ip(gnt_ip),
	      .sel_ip_ivc(sel_ip_ivc),
	      .gnt_op(gnt_op),
	      .sel_op_ip(sel_op_ip),
	      .sel_op_ivc(sel_op_ivc));
	end
      
   endgenerate
   
endmodule
