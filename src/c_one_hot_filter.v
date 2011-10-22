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
// generic one-hot filter logic
//==============================================================================

module c_one_hot_filter
  (data_in, data_out);
   
   // width of input vector
   parameter width = 8;
   
   // input data
   input [0:width-1] data_in;
   
   // output data
   output [0:width-1] data_out;
   wire [0:width-1]   data_out;
   
   generate
      
      if(width == 1)
	assign data_out = data_in;
      else
	begin
	   
	   genvar 		 pos;
	   
	   for(pos = 0; pos < width; pos = pos + 1)
	     begin:poss
		
		wire [0:(width-1)-1] others;
		
		if(pos > 0)
		  assign others[0:pos-1] = data_in[0:pos-1];
		if(pos < (width - 1))
		  assign others[pos:(width-1)-1] = data_in[(pos+1):width-1];
		
		assign data_out[pos] = data_in[pos] & ~|others;
		
	     end
	   
	end
      
   endgenerate
   
endmodule
