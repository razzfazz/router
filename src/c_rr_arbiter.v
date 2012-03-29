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
// round-robin arbiter
//==============================================================================

module c_rr_arbiter
  (clk, reset, active, req_pr, gnt_pr, gnt, update);
   
`include "c_constants.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // perform masking between priorities
   parameter mask_priorities = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // vector of requests
   input [0:num_priorities*num_ports-1] req_pr;
   
   // vector of grants
   output [0:num_priorities*num_ports-1] gnt_pr;
   wire [0:num_priorities*num_ports-1] 	 gnt_pr;
   
   // merged vector of grants
   output [0:num_ports-1] 		 gnt;
   wire [0:num_ports-1] 		 gnt;
   
   // update port priorities
   input 				 update;
   
   generate
      
      if(num_ports == 1)
	begin
	   
	   if(mask_priorities)
	     begin
		
		c_lod
		  #(.width(num_priorities),
		    .num_priorities(1))
		gnt_lod
		  (.data_in_pr(req_pr),
		   .data_out_pr(gnt_pr),
		   .data_out(),
		   .mask_out());
		
	     end
	   else
	     assign gnt_pr = req_pr;
	   
	   assign gnt = |req_pr;
	   
	end
      else if(num_ports > 1)
	begin
	   
	   wire [0:num_ports-1] mask;
	   
	   wire [0:num_priorities*2*num_ports-1] req_exp;
	   wire [0:num_priorities*2*num_ports-1] gnt_exp;
	   
	   genvar 				 prio;
	   
	   for(prio = 0; prio < num_priorities; prio = prio + 1)
	     begin:prios
		
		wire [0:num_ports-1] req_unqual;
		assign req_unqual = req_pr[prio*num_ports:(prio+1)*num_ports-1];
		
		wire [0:num_ports-1] req_qual;
		assign req_qual = req_unqual & mask;
		
		assign req_exp[prio*2*num_ports:(prio+1)*2*num_ports-1]
		  = {req_qual, req_unqual};
		
		wire [0:num_ports-1] gnt_qual;
		assign gnt_qual
		  = gnt_exp[prio*2*num_ports:(prio*2+1)*num_ports-1];
		
		wire [0:num_ports-1] gnt_unqual;
		assign gnt_unqual
		  = gnt_exp[(prio*2+1)*num_ports:(prio*2+2)*num_ports-1];
		
		if(mask_priorities)
		  assign gnt_pr[prio*num_ports:(prio+1)*num_ports-1]
		    = gnt_qual | gnt_unqual;
		else
		  assign gnt_pr[prio*num_ports:(prio+1)*num_ports-1]
		    = (|req_qual) ? gnt_qual : gnt_unqual;
		
	     end
	   
	   wire [0:num_ports-1]      gnt_intm;
	   wire [0:num_ports-1]      next_mask;
	   c_lod
	     #(.width(num_ports),
	       .num_priorities(num_priorities*2),
	       .mask_priorities(mask_priorities))
	   gnt_lod
	     (.data_in_pr(req_exp),
	      .data_out_pr(gnt_exp),
	      .data_out(gnt_intm),
	      .mask_out(next_mask));
	   
	   if(mask_priorities || (num_priorities == 1))
	     assign gnt = gnt_intm;
	   else
	     begin
		
		c_binary_op
		  #(.num_ports(num_priorities),
		    .width(num_ports),
		    .op(`BINARY_OP_OR))
		gnt_or
		  (.data_in(gnt_pr),
		   .data_out(gnt));
		
	     end
	   
	   wire [0:num_ports-2] mask_s, mask_q;
	   assign mask_s = update ? next_mask[1:num_ports-1] : mask_q;
	   c_dff
	     #(.width(num_ports-1),
	       .reset_type(reset_type))
	   maskq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(mask_s),
	      .q(mask_q));
	   
	   assign mask = {1'b0, mask_q};
	   
	end	
      
   endgenerate
   
endmodule
