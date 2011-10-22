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



// multiple-input signature register
module c_misr
  (clk, reset, load, run, feedback, d, q);
   
`include "c_constants.v"
   
   // width of register
   parameter width = 32;
   
   // offset (left index) of register
   parameter offset = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   parameter [offset:(offset+width)-1] reset_value = {width{1'b0}};
   
   input clk;
   input reset;
   
   // load data input into signature register
   input load;
   
   // activate signature updates
   input run;
   
   // feedback polynomial
   input [offset:(offset+width)-1] feedback;
   
   // data input
   input [offset:(offset+width)-1] d;
   
   // data output
   output [offset:(offset+width)-1] q;
   reg [offset:(offset+width)-1] q;

   
   wire [offset:(offset+width)-1] fb_val;
   assign fb_val = {width{~load & misr_q[offset+width-1]}} & feedback;
   
   wire [offset:(offset+width)-1] toggle_val;
   assign toggle_val = fb_val ^ d;
   
   wire [offset:(offset+width)-1] base_val;
   assign base_val[offset] = 1'b0;
   
   wire [offset:(offset+width)-1] misr_q;
   
   generate
      
      if(width > 1)
	assign base_val[(offset+1):(offset+width)-1]
		 = {(width-1){~load}} & misr_q[offset:(offset+width-1)-1];
      
   endgenerate
   
   wire [offset:(offset+width)-1] misr_s;
   assign misr_s = (load | run) ? (base_val ^ toggle_val) : misr_q;
   c_dff
     #(.width(width),
       .offset(offset),
       .reset_type(reset_type),
       .reset_value(reset_value))
   misrq
     (.clk(clk),
      .reset(reset),
      .d(misr_s),
      .q(misr_q));
   
   assign q = misr_q;
   
endmodule
