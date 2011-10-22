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

// wavefront allocator variant which uses multiplexers to permute inputs and
// outputs based on priority
module c_wf_alloc_mux
  (clk, reset, update, req, gnt);
   
`include "c_constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   // try to recover from errors
   parameter error_recovery = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // reset value for priority pointer
   localparam [0:num_ports-1] prio_init = {1'b1, {(num_ports-1){1'b0}}};
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // request matrix
   input [0:num_ports*num_ports-1] req;
   
   // grant matrix
   output [0:num_ports*num_ports-1] gnt;
   wire [0:num_ports*num_ports-1] gnt;
   
   // Need to make sure this stays one-hot, as bit errors can lead to
   // conflicting grants being generated!
   wire [0:num_ports-1] 	  prio_s, prio_q;
   wire 			  prio_bad;
   assign prio_bad = ~^prio_q;
   wire [0:num_ports-1] 	  prio_fixed;
   assign prio_fixed = (error_recovery && prio_bad) ? prio_init : prio_q;
   assign prio_s = update ?
		   {prio_fixed[num_ports-1], prio_fixed[0:num_ports-2]} :
		   prio_fixed;
   c_dff
     #(.width(num_ports),
       .reset_type(reset_type),
       .reset_value(prio_init))
   prioq
     (.clk(clk),
      .reset(reset),
      .d(prio_s),
      .q(prio_q));
   
   wire [0:num_ports*num_ports-1] y;
   
   generate
      
      genvar 			  row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   wire [0:num_ports-1] x_in, y_in;
	   wire [0:num_ports] 	x_out, y_out;
	   
	   assign x_in = x_out[0:num_ports-1];
	   assign y_in = y[((row+num_ports)%num_ports)*num_ports:
			   ((row+num_ports)%num_ports+1)*num_ports-1];
	   
	   wire [0:num_ports-1] req_in;
	   
	   assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
	   assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
	   
	   wire [0:num_ports-1] gnt_out;
	   assign gnt_out = req_in & x_in & y_in;
	   
	   assign y[((row+num_ports+1)%num_ports)*num_ports:
		    ((row+num_ports+1)%num_ports+1)*num_ports-1]
		    = y_out[0:num_ports-1];
	   
	   wire [0:num_ports-1] gnt_row;
	   
	   assign gnt[row*num_ports:(row+1)*num_ports-1] = gnt_row;
	   
	   wire [0:num_ports-1] req_row;
	   assign req_row = req[row*num_ports:(row+1)*num_ports-1];
	   
	   wire [0:2*num_ports-1] req_dup;
	   assign req_dup = {2{req_row}};
	   
	   wire [0:2*num_ports-1] gnt_dup;
	   
	   genvar 		  col;
	   for(col = 0; col < num_ports; col = col + 1)
	     begin:cols
		
		wire [0:num_ports-1] req_rot;
		assign req_rot
		  = req_dup[(col+num_ports-row)%num_ports:
			    (col+num_ports-row)%num_ports+num_ports-1];
		
		c_select_1ofn
		  #(.width(1),
		    .num_ports(num_ports))
		req_sel
		  (.select(prio_q),
		   .data_in(req_rot),
		   .data_out(req_in[col]));
		
		// need to reverse the grant vector
		assign gnt_dup[num_ports-col-1] = gnt_out[col];
		assign gnt_dup[2*num_ports-col-1] = gnt_out[col];
		
		wire [0:num_ports-1] gnt_rot;
		assign gnt_rot
		  = gnt_dup[(2*num_ports-row-col-1)%num_ports:
			    (2*num_ports-row-col-1)%num_ports+
			    num_ports-1];
		
		c_select_1ofn
		  #(.width(1),
		    .num_ports(num_ports))
		gnt_sel
		  (.select(prio_q),
		   .data_in(gnt_rot),
		   .data_out(gnt_row[col]));
		
	     end		
	end
      
   endgenerate
   
endmodule
