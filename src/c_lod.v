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
// leading one detector
//==============================================================================

module c_lod
  (data_in, data_out);
   
   // number of input ports
   parameter width = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // vector of requests
   input [0:num_priorities*width-1] data_in;
   
   // vector of grants
   output [0:width-1] 		    data_out;
   wire [0:width-1] 		    data_out;
   
   wire [0:num_priorities-1] 	    enable_prio;
   assign enable_prio[0] = 1'b1;
   
   wire [0:num_priorities*width-1]  data_out_by_prio;
   
   genvar 			    prio;
   
   generate
      
      for(prio = 0; prio < num_priorities; prio = prio + 1)
	begin:prios
	   
	   wire [0:width-1] prio_data_in;
	   assign prio_data_in = data_in[prio*width:(prio+1)*width-1];
	   
	   if(prio < (num_priorities - 1))
	     assign enable_prio[prio+1] = enable_prio[prio] & ~|prio_data_in;
	   
	   wire [0:width-1] prio_data_out;
	   
	   if(width == 1)
	     assign prio_data_out = prio_data_in;
	   else
	     begin
		
		// To find the first non-zero bit from the left, we must 
		// reverse the input and output vectors.
		
		wire [0:width-1] prio_data_in_rev;
		c_reverse
		  #(.width(width))
		prio_data_in_rev_revr
		  (.data_in(prio_data_in),
		   .data_out(prio_data_in_rev));
		
		wire [0:width-1] prio_data_out_rev;
		assign prio_data_out_rev = prio_data_in_rev & -prio_data_in_rev;
		
		c_reverse
		  #(.width(width))
		prio_data_out_revr
		  (.data_in(prio_data_out_rev),
		   .data_out(prio_data_out));
		
	     end
	   
	   assign data_out_by_prio[prio*width:(prio+1)*width-1] = prio_data_out;
	   
	end
      
   endgenerate
   
   c_select_mofn
     #(.num_ports(num_priorities),
       .width(width))
   data_out_sel
     (.select(enable_prio),
      .data_in(data_out_by_prio),
      .data_out(data_out));
   
endmodule
