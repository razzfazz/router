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
module vc_alloc
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, elig_op_ovc, gnt_ip_ivc_ovc, 
   gnt_op_ovc);
   
`include "constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
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
   
   // request VC allocation for given port (for each input VC)
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   
   // allowable VCs for VC allocation (for each input VC)
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // granted output VC (to inpt controller)
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 	gnt_op_ovc;
   
   generate
      
      case(allocator_type)
	`VC_ALLOCATOR_TYPE_SEP_IF:
	  begin
	     vc_alloc_core_sep_if
	       #(.num_vcs(num_vcs),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .reset_type(reset_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc));
	  end
	`VC_ALLOCATOR_TYPE_SEP_OF:
	  begin
	     vc_alloc_core_sep_of
	       #(.num_vcs(num_vcs),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .reset_type(reset_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc));
	  end
      endcase
      
      if(allocator_type >= `VC_ALLOCATOR_TYPE_WF_BASE)
	begin
	   vc_alloc_core_wf
	       #(.num_vcs(num_vcs),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .wf_allocator_type(wf_allocator_type),
		 .reset_type(reset_type))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc));
	end
      
   endgenerate
   
endmodule
