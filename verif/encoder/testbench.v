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

`default_nettype none

module testbench
  #(parameter num_ports = 8,
    parameter num_tests = 1000,
    parameter initial_seed = 0)
   ();

`include "c_functions.v"

   localparam width = clogb(num_ports);
   
   reg [0:num_ports-1] data_in;
   wire [0:width-1]    data_out;

   c_encode
     #(.num_ports(num_ports))
   dut
     (.data_in(data_in),
      .data_out(data_out));

   integer 	       test;
   integer 	       i;
   integer 	       seed = initial_seed;

   reg [0:width-1]     data_ref;
   
   initial
   begin

      for(test = 0; test < num_tests; test = test + 1)
	begin
	   i = $dist_uniform(seed, 0, num_ports-1);
	   data_in = {num_ports{1'b0}};
	   data_in[i] = 1'b1;
	   data_ref = i;
	   #1;
	   if(data_out != data_ref)
	     $display("ERROR: in=%b, out=%d, expected=%d",
		      data_in, data_out, data_ref);
	   #1;
	end
      
      $finish;
      
   end
   
endmodule
