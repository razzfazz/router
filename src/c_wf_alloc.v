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
// generic wavefront allocator
//==============================================================================

module c_wf_alloc
  (clk, reset, active, req_pr, gnt_pr, gnt, update);
   
`include "c_constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // select implementation variant
   parameter wf_alloc_type = `WF_ALLOC_TYPE_REP;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // request matrix
   input [0:num_priorities*num_ports*num_ports-1] req_pr;
   
   // grant matrix
   output [0:num_priorities*num_ports*num_ports-1] gnt_pr;
   wire [0:num_priorities*num_ports*num_ports-1]   gnt_pr;
   
   // combined grant matrix
   output [0:num_ports*num_ports-1] 		   gnt;
   wire [0:num_ports*num_ports-1] 		   gnt;
   
   // update port priorities
   input 					   update;
   
   generate
      
      // synopsys translate_off
      
      if(num_priorities > 1)
	begin
	   
	   initial
	     begin
		$display({"ERROR: Wavefront allocator does not yet support ", 
			  "multiple priorities."});
		$stop;
	     end
	   
	end
      
      // synopsys translate_on
      
      case(wf_alloc_type)
	`WF_ALLOC_TYPE_MUX:
	  begin
	     c_wf_alloc_mux
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     core_mux
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req(req_pr),
		.gnt(gnt_pr),
		.update(update));
	  end
	`WF_ALLOC_TYPE_REP:
	  begin
	     c_wf_alloc_rep
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     core_rep
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req(req_pr),
		.gnt(gnt_pr),
		.update(update));
	  end
	`WF_ALLOC_TYPE_DPA:
	  begin
	     c_wf_alloc_dpa
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     core_dpa
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req(req_pr),
		.gnt(gnt_pr),
		.update(update));
	  end      
	`WF_ALLOC_TYPE_ROT:
	  begin
	     c_wf_alloc_rot
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     core_rot
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req(req_pr),
		.gnt(gnt_pr),
		.update(update));
	  end
	`WF_ALLOC_TYPE_LOOP:
	  begin
	     c_wf_alloc_loop
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     core_loop
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req(req_pr),
		.gnt(gnt_pr),
		.update(update));
	  end
      endcase
      
   endgenerate
   
   assign gnt = gnt_pr;
   
endmodule
