// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
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



// generic matrix arbiter grant generation logic
module c_matrix_arbiter
  (state, req, gnt);
   
   // number of inputs ports
   parameter num_ports = 32;
   
   // current arbiter state
   input [0:num_ports*num_ports-1] state;
   
   // request vector
   input [0:num_ports-1] req;
   
   // grant vector
   output [0:num_ports-1] gnt;
   wire [0:num_ports-1] gnt;
   
   generate
      
      if(num_ports > 1)
	begin
	   
	   // port priority matrix
	   wire [0:num_ports*num_ports-1] prio;
	   assign prio = state;
	   
	   genvar 			  row;
	   
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:rows
		
		// grant requests if we have priority over all other requestors
		assign gnt[row]
			 = req[row] &
			   (&(prio[row*num_ports:(row+1)*num_ports-1] | ~req));
		
	     end
	   
	end
      else
	assign gnt = req;
      
   endgenerate
   
endmodule
