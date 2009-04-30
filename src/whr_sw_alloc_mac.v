// $Id$

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
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

// switch allocator for wormhole router
module whr_sw_alloc_mac
  (clk, reset, route_ip_op, elig_op, free_op, req_ip, gnt_ip, gnt_ip_op, 
   gnt_op);
   
`include "c_constants.v"
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_ports-1] route_ip_op;
   
   // ports eligible for allocation?
   input  [0:num_ports-1] elig_op;
   
   // ports have buffer space available?
   input [0:num_ports-1] free_op;
   
   // switch requests
   input [0:num_ports-1] req_ip;
   
   // grants per input port
   output [0:num_ports-1] gnt_ip;
   wire [0:num_ports-1] gnt_ip;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] gnt_ip_op;
   wire [0:num_ports*num_ports-1] gnt_ip_op;
   
   // grants per output port
   output [0:num_ports-1] gnt_op;
   wire [0:num_ports-1] 	  gnt_op;
   
   
   wire [0:num_ports*num_ports-1] route_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   route_op_ip_intl
     (.data_in(route_ip_op),
      .data_out(route_op_ip));
   
   wire [0:num_ports*num_ports-1] gnt_op_ip;
   
   generate
      
      genvar 			  op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire elig;
	   assign elig = elig_op[op];
	   
	   wire free;
	   assign free = free_op[op];
	   
	   wire [0:num_ports-1] route_ip;
	   assign route_ip = route_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire [0:num_ports-1] req_int_ip;
	   assign req_int_ip = req_ip & route_ip;
	   
	   wire 		req_int;
	   assign req_int = |req_int_ip;
	   
	   wire 		update;
	   assign update = elig & req_int & free;
	   
	   wire [0:num_ports-1] gnt_int_ip;
	   c_arbiter
	     #(.num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .reset_type(reset_type))
	   gnt_in_ip_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update),
	      .req(req_int_ip),
	      .gnt(gnt_int_ip));
	   
	   wire [0:num_ports-1] hold_mask_ip_s, hold_mask_ip_q;
	   assign hold_mask_ip_s
	     = (elig & req_int) ? gnt_int_ip : hold_mask_ip_q;
	   c_dff
	     #(.width(num_ports),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   hold_mask_ipq
	     (.clk(clk),
	      .reset(reset),
	      .d(hold_mask_ip_s),
	      .q(hold_mask_ip_q));
	   
	   wire [0:num_ports-1] held_gnt_ip;
	   assign held_gnt_ip = req_int_ip & hold_mask_ip_q;

	   wire 		held_gnt;
	   assign held_gnt = |held_gnt_ip;
	   
	   wire [0:num_ports-1] gnt_ip;
	   assign gnt_ip = elig ? gnt_int_ip : held_gnt_ip;
	   
	   assign gnt_op_ip[op*num_ports:(op+1)*num_ports-1] = gnt_ip;
	   
	   wire 		gnt;
	   assign gnt = (elig ? req_int : held_gnt) & free;
	   
	   assign gnt_op[op] = gnt;
	   
	end
      
   endgenerate
   
   // mask grant signals to input controllers to ensure credit availability
   c_select_mofn
     #(.num_ports(num_ports),
       .width(num_ports))
   gnt_ip_sel
     (.select(free_op),
      .data_in(gnt_op_ip),
      .data_out(gnt_ip));
   
   // for the crossbar control signals, we don't need the credit check: in the 
   // absence of credit, the flit valid indicator bit being sent across the
   // corssbar is low, so no flit is transmitted
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_ip_op_intl
     (.data_in(gnt_op_ip),
      .data_out(gnt_ip_op));
   
endmodule
