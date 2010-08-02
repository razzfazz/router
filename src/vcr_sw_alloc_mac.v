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

//==============================================================================
// switch allocator for VC router
//==============================================================================

module vcr_sw_alloc_mac
  (clk, reset, route_ip_ivc_op, active_op, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   sel_nonspec_ip_ivc, sel_spec_ip_ivc, gnt_nonspec_ip, gnt_spec_ip, gnt_op_ip);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // select implementation variant for switch allocator
   parameter allocator_type = `SW_ALLOC_TYPE_SEP_IF;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type
   parameter spec_type = `SW_ALLOC_SPEC_TYPE_REQ;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // clock enable signals for output controllers
   output [0:num_ports-1] 		   active_op;
   wire [0:num_ports-1] 		   active_op;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_nonspec_ip_ivc;
   
   // speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_spec_ip_ivc;
   
   // indicate which VC at a given port is granted non-speculatively
   output [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   
   // indicate which VC at a given port is granted speculatively
   output [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   
   // non-speculative grants
   output [0:num_ports-1] 		   gnt_nonspec_ip;
   wire [0:num_ports-1] 		   gnt_nonspec_ip;
   
   // speculative grants
   output [0:num_ports-1] 		   gnt_spec_ip;
   wire [0:num_ports-1] 		   gnt_spec_ip;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] 	   gnt_op_ip;
   wire [0:num_ports*num_ports-1] 	   gnt_op_ip;
   
   
   wire [0:num_ports-1] 		   active_nonspec_ip;
   c_mat_mult
     #(.dim1_width(num_ports),
       .dim2_width(num_vcs),
       .dim3_width(1))
   active_nonspec_ip_mmult
     (.input_a(req_nonspec_ip_ivc),
      .input_b({num_vcs{1'b1}}),
      .result(active_nonspec_ip));
   
   wire [0:num_ports-1] 		   active_spec_ip;
   c_mat_mult
     #(.dim1_width(num_ports),
       .dim2_width(num_vcs),
       .dim3_width(1))
   active_spec_ip_mmult
     (.input_a(req_spec_ip_ivc),
      .input_b({num_vcs{1'b1}}),
      .result(active_spec_ip));
   
   wire [0:num_ports-1] 		   active_nonspec_op;
   c_select_mofn
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports))
   active_nonspec_op_sel
     (.select(req_nonspec_ip_ivc),
      .data_in(route_ip_ivc_op),
      .data_out(active_nonspec_op));
   
   wire [0:num_ports-1] 		   active_spec_op;
   c_select_mofn
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports))
   active_spec_op_sel
     (.select(req_spec_ip_ivc),
      .data_in(route_ip_ivc_op),
      .data_out(active_spec_op));
   
   generate
      
      if(spec_type == `SW_ALLOC_SPEC_TYPE_NONE)
	assign active_op = active_nonspec_op;
      else
	assign active_op = active_nonspec_op | active_spec_op;
      
   endgenerate
   
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
	      .active_nonspec_ip(active_nonspec_ip),
	      .active_spec_ip(active_spec_ip),
	      .active_nonspec_op(active_nonspec_op),
	      .active_spec_op(active_spec_op),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .sel_nonspec_ip_ivc(sel_nonspec_ip_ivc),
	      .sel_spec_ip_ivc(sel_spec_ip_ivc),
	      .gnt_nonspec_ip(gnt_nonspec_ip),
	      .gnt_spec_ip(gnt_spec_ip),
	      .gnt_op_ip(gnt_op_ip));
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
	      .active_nonspec_ip(active_nonspec_ip),
	      .active_spec_ip(active_spec_ip),
	      .active_nonspec_op(active_nonspec_op),
	      .active_spec_op(active_spec_op),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .sel_nonspec_ip_ivc(sel_nonspec_ip_ivc),
	      .sel_spec_ip_ivc(sel_spec_ip_ivc),
	      .gnt_nonspec_ip(gnt_nonspec_ip),
	      .gnt_spec_ip(gnt_spec_ip),
	      .gnt_op_ip(gnt_op_ip));
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
	      .active_nonspec_ip(active_nonspec_ip),
	      .active_spec_ip(active_spec_ip),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .sel_nonspec_ip_ivc(sel_nonspec_ip_ivc),
	      .sel_spec_ip_ivc(sel_spec_ip_ivc),
	      .gnt_nonspec_ip(gnt_nonspec_ip),
	      .gnt_spec_ip(gnt_spec_ip),
	      .gnt_op_ip(gnt_op_ip));
	end
      
   endgenerate
   
endmodule
