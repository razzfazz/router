// $Id$

/*
Copyright (c) 2007-2010, Trustees of The Leland Stanford Junior University
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
// round-robin arbiter
//==============================================================================

module c_rr_arbiter
  (clk, reset, active, req, gnt, update);
   
`include "c_constants.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // vector of requests
   input [0:num_priorities*num_ports-1] req;
   
   // vector of grants
   output [0:num_ports-1] 		gnt;
   wire [0:num_ports-1] 		gnt;
   
   // update port priorities
   input 				update;
   
   generate
      
      if(num_ports == 1)
	assign gnt = |req;
      else if(num_ports > 1)
	begin
	   
	   wire [0:num_ports-1] state;
	   
	   wire [0:num_priorities-1] enable_prio;
	   assign enable_prio[0] = 1'b1;
	   
	   wire [0:num_priorities*num_ports-1] gnt_by_prio;
	   wire [0:num_priorities*num_ports-1] 	next_state_by_prio;
	   
	   genvar 		prio;
	   
	   for(prio = 0; prio < num_priorities; prio = prio + 1)
	     begin:prios
		
		wire [0:num_ports-1] req_unqual;
		assign req_unqual = req[prio*num_ports:(prio+1)*num_ports-1];
		
		if(prio < (num_priorities - 1))
		  assign enable_prio[prio+1] = enable_prio[prio] & ~|req_unqual;
		
		wire [0:num_ports-1] req_unqual_rev;
		c_reverse
		  #(.width(num_ports))
		req_unqual_rev_revr
		  (.data_in(req_unqual),
		   .data_out(req_unqual_rev));
		
		wire [0:num_ports-1] req_unqual_rev_compl;
		assign req_unqual_rev_compl = -req_unqual_rev;
		
		wire [0:num_ports-1] gnt_unqual_rev;
		assign gnt_unqual_rev = req_unqual_rev & req_unqual_rev_compl;
		
		wire [0:num_ports-1] gnt_unqual;
		c_reverse
		  #(.width(num_ports))
		gnt_unqual_revr
		  (.data_in(gnt_unqual_rev),
		   .data_out(gnt_unqual));
		
		wire [0:num_ports-1] next_state_unqual_rev;
		assign next_state_unqual_rev
		  = req_unqual_rev ^ req_unqual_rev_compl;
		
		wire [0:num_ports-1] next_state_unqual;
		c_reverse
		  #(.width(num_ports))
		next_state_unqual_revr
		  (.data_in(next_state_unqual_rev),
		   .data_out(next_state_unqual));
		
		wire [0:num_ports-1] req_qual;
		assign req_qual = req_unqual & state;
		
		wire [0:num_ports-1] req_qual_rev;
		c_reverse
		  #(.width(num_ports))
		req_qual_rev_revr
		  (.data_in(req_qual),
		   .data_out(req_qual_rev));
		
		wire [0:num_ports-1] req_qual_rev_compl;
		assign req_qual_rev_compl = -req_qual_rev;
		
		wire [0:num_ports-1] gnt_qual_rev;
		assign gnt_qual_rev = req_qual_rev & req_qual_rev_compl;
		
		wire [0:num_ports-1] gnt_qual;
		c_reverse
		  #(.width(num_ports))
		gnt_qual_revr
		  (.data_in(gnt_qual_rev),
		   .data_out(gnt_qual));
		
		wire [0:num_ports-1] next_state_qual_rev;
		assign next_state_qual_rev = req_qual_rev ^ req_qual_rev_compl;
		
		wire [0:num_ports-1] next_state_qual;
		c_reverse
		  #(.width(num_ports))
		next_state_qual_revr
		  (.data_in(next_state_qual_rev),
		   .data_out(next_state_qual));
		
		assign gnt_by_prio[prio*num_ports:(prio+1)*num_ports-1] 
		  = (|req_qual) ? gnt_qual : gnt_unqual;
		
		assign next_state_by_prio[prio*num_ports:(prio+1)*num_ports-1] 
		  = (|req_qual) ? next_state_qual : next_state_unqual;
		
	     end
	   
	   c_select_mofn
	     #(.num_ports(num_priorities),
	       .width(num_ports))
	   gnt_sel
	     (.select(enable_prio),
	      .data_in(gnt_by_prio),
	      .data_out(gnt));
	   
	   wire [0:num_ports-1]      next_state;
	   c_select_mofn
	     #(.num_ports(num_priorities),
	       .width(num_ports))
	   next_state_sel
	     (.select(enable_prio),
	      .data_in(next_state_by_prio),
	      .data_out(next_state));
	   
	   wire [0:num_ports-1]      state_s, state_q;
	   assign state_s = update ? next_state : state_q;
	   assign state_q[0] = 1'b0;
	   c_dff
	     #(.width(num_ports-1),
	       .reset_type(reset_type))
	   stateq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(state_s[1:num_ports-1]),
	      .q(state_q[1:num_ports-1]));
	   
	   assign state = state_q;
	   
	end	
      
   endgenerate
   
endmodule
