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



// generic round-robin arbiter state
module c_rr_arb_state
  (clk, reset, active, update, gnt, state);
   
`include "c_constants.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // update arbiter state
   input update;
   
   // vector of grants
   input [0:num_ports-1] gnt;
   
   // current arbiter state
   output [0:num_ports-1] state;
   wire [0:num_ports-1] state;
   
   generate
      
      if(num_ports > 1)
	begin
	   
	   // if a grant was generated in the current cycle, we prioritize the 
	   // inputs to the right of this grant (if any) in the next cycle; if 
	   // no grant was generated, the priorities are left unchanged
	   wire [0:num_ports-1] prio_s, prio_q;
	   assign prio_s = update ? (gnt - 1'b1) : prio_q;
	   assign prio_q[0] = 1'b0;
	   c_dff
	     #(.width(num_ports-1),
	       .reset_type(reset_type))
	   prioq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(prio_s[1:num_ports-1]),
	      .q(prio_q[1:num_ports-1]));
	   
	   assign state = prio_q;
	   
	end
      else
	assign state = 1'b0;
      
   endgenerate
   
endmodule
