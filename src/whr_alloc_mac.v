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
// allocator module
//==============================================================================

module whr_alloc_mac
  (clk, reset, route_ip_op, arb_active_op, req_ip, req_head_ip, req_tail_ip, 
   gnt_ip, gnt_op, gnt_head_op, gnt_tail_op, xbr_ctrl_op_ip, elig_op, cred_op);
   
`include "c_constants.v"
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects from input ports
   input [0:num_ports*num_ports-1] route_ip_op;
   
   // 
   output [0:num_ports-1] 	   arb_active_op;
   wire [0:num_ports-1] 	   arb_active_op;
   
   // requests from input ports
   input [0:num_ports-1] 	   req_ip;
   
   // requests are for head flits
   input [0:num_ports-1] 	   req_head_ip;
   
   // requests are for tail flits
   input [0:num_ports-1] 	   req_tail_ip;
   
   // grants to input ports
   output [0:num_ports-1] 	   gnt_ip;
   wire [0:num_ports-1] 	   gnt_ip;
   
   // grant to output port
   output [0:num_ports-1] 	   gnt_op;
   wire [0:num_ports-1] 	   gnt_op;
   
   // granted flit is head flit
   output [0:num_ports-1] 	   gnt_head_op;
   wire [0:num_ports-1] 	   gnt_head_op;
   
   // granted flit is tail flit
   output [0:num_ports-1] 	   gnt_tail_op;
   wire [0:num_ports-1] 	   gnt_tail_op;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] xbr_ctrl_op_ip;
   wire [0:num_ports*num_ports-1]   xbr_ctrl_op_ip;
   
   // can output port accept a new packet?
   input [0:num_ports-1] 	    elig_op;
   
   // can output port accept a new flit?
   input [0:num_ports-1] 	    cred_op;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1]   route_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   route_op_ip_intl
     (.data_in(route_ip_op),
      .data_out(route_op_ip));
   
   wire [0:num_ports*num_ports-1]   gnt_op_ip;
   
   genvar 			    op;
   
   generate
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   
	   //-------------------------------------------------------------------
	   // connect inputs and outputs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] route_ip;
	   assign route_ip = route_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire 		arb_active;
	   assign arb_active_op[op] = arb_active;
	   
	   wire 		elig;
	   assign elig = elig_op[op];
	   
	   wire 		cred;
	   assign cred = cred_op[op];
	   
	   wire [0:num_ports-1] gnt_ip;
	   assign gnt_op_ip[op*num_ports:(op+1)*num_ports-1] = gnt_ip;
	   
	   wire 		gnt;
	   assign gnt_op[op] = gnt;
	   
	   wire 		gnt_head;
	   assign gnt_head_op[op] = gnt_head;
	   
	   wire 		gnt_tail;
	   assign gnt_tail_op[op] = gnt_tail;
	   
	   wire [0:num_ports-1] xbr_ctrl_ip;
	   assign xbr_ctrl_op_ip[op*num_ports:(op+1)*num_ports-1] = xbr_ctrl_ip;
	   
	   
	   //-------------------------------------------------------------------
	   // arbitration
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] arb_req_ip;
	   assign arb_req_ip
	     = req_ip & route_ip & (~req_head_ip | {num_ports{elig}});
	   
	   wire 		arb_gnt;
	   assign arb_gnt = |arb_req_ip;
	   
	   
	   // NOTE: For the wormhole router, credit and eligibility checking is 
	   // performed after arbitration, so request generation is simple and 
	   // fast; however, if clock gating based on requests should prove to 
	   // be timing-critical, we could just enable all output controllers 
	   // whenever any input controller has data available.
	   
	   assign arb_active = |(req_ip & route_ip);
	   
	   wire 		arb_update;
	   
	   wire [0:num_ports-1] arb_gnt_ip;
	   c_arbiter
	     #(.num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .reset_type(reset_type))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .active(arb_active),
	      .update(arb_update),
	      .req(arb_req_ip),
	      .gnt(arb_gnt_ip));
	   
	   // update arbiter priorities any time a new packet is granted
	   assign arb_update = |(arb_gnt_ip & req_head_ip) & cred;
	   
	   assign gnt_ip = arb_gnt_ip & {num_ports{cred}};
	   
	   assign gnt = arb_gnt & cred;
	   
	   c_select_1ofn
	     #(.num_ports(num_ports),
	       .width(1))
	   gnt_head_sel
	     (.select(arb_gnt_ip),
	      .data_in(req_head_ip),
	      .data_out(gnt_head));
	   
	   c_select_1ofn
	     #(.num_ports(num_ports),
	       .width(1))
	   gnt_tail_sel
	     (.select(arb_gnt_ip),
	      .data_in(req_tail_ip),
	      .data_out(gnt_tail));
	   
	   assign xbr_ctrl_ip = arb_gnt_ip;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate input-side grants
   //---------------------------------------------------------------------------
   
   c_binary_op
     #(.num_ports(num_ports),
       .width(num_ports),
       .op(`BINARY_OP_OR))
   gnt_ip_or
     (.data_in(gnt_op_ip),
      .data_out(gnt_ip));
   
endmodule
