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



// generic round-robin arbiter grant generation logic
module c_rr_arb_logic
  (state, req, gnt);
   
   // number of input ports
   parameter num_ports = 32;
   
   // current arbiter state
   input [0:num_ports-1] state;
   
   // vector of requests
   input [0:num_ports-1] req;
   
   // vector of grants
   output [0:num_ports-1] gnt;
   wire [0:num_ports-1] gnt;
   
   generate
      
      if(num_ports > 1)
	begin
	   
	   // which ports have priority?
	   wire [0:num_ports-1] prio;
	   assign prio = state;
	   
	   // generate qualified requests (w/ priority)
	   wire [0:num_ports-1] req_qual;
	   assign req_qual = req & prio;
	   
	   // qualified grant (w/ priority)
	   wire [0:num_ports-1] gnt_qual;
	   assign gnt_qual[0] = 1'b0;
	   c_fp_arbiter
	     #(.num_ports(num_ports-1))
	   gnt_qual_arb
	     (.req(req_qual[1:num_ports-1]),
	      .gnt(gnt_qual[1:num_ports-1]));
	   
	   // unqualified grant (ignoring priority)
	   wire [0:num_ports-1] gnt_unqual;
	   c_fp_arbiter
	     #(.num_ports(num_ports))
	   gnt_unqual_arb
	     (.req(req),
	      .gnt(gnt_unqual));
	   
	   // generate grant vector
	   assign gnt = |req_qual ? gnt_qual : gnt_unqual;
	   
	end
      else
	assign gnt = req;
      
   endgenerate
   
endmodule
