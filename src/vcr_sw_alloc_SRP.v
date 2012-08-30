// $Id$

/*
 Copyright (c) 2007-2012, Trustees of The Leland Stanford Junior University
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
// switch allocator variant usign separable input-first allocation
//==============================================================================

module vcr_sw_alloc_SRP
  (/*autoarg*/
   // Outputs
   sel_nonspec_ip_ivc, gnt_nonspec_ip, gnt_op_taken, gnt_op_ip,
   // Inputs
   clk, reset, active_ip, active_op, route_ip_ivc_op,
   req_nonspec_ip_ivc, gnt_op_disable
   );
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type
   parameter spec_type = `SW_ALLOC_SPEC_TYPE_REQ;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // clock enable signals
   input [0:num_ports-1] active_ip;
   input [0:num_ports-1] active_op;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_nonspec_ip_ivc;
   
   
   // indicate which VC at a given port is granted non-speculatively
   output [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   
   // indicate which VC at a given port is granted speculatively
   //output [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   
   // non-speculative grants
   output [0:num_ports-1] 		   gnt_nonspec_ip;
   wire [0:num_ports-1] 		   gnt_nonspec_ip;

   //output port masking from higher priority allocators
   input [0:num_ports-1] 		   gnt_op_disable;
   //output port masking to lower priority allocator
   output [0:num_ports-1] 		   gnt_op_taken;
   
   // speculative grants
   //output [0:num_ports-1] 		   gnt_spec_ip;
   wire [0:num_ports-1] 		   gnt_spec_ip;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] 	   gnt_op_ip;
   wire [0:num_ports*num_ports-1] 	   gnt_op_ip;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	   req_in_nonspec_ip_op;   
   wire [0:num_ports*num_ports-1] 	   req_out_nonspec_ip_op;
   wire [0:num_ports*num_ports-1] 	   gnt_out_nonspec_ip_op;
   
   wire [0:num_ports*num_ports-1] 	   req_out_spec_ip_op;
   wire [0:num_ports*num_ports-1] 	   gnt_out_spec_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				   ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   wire active;
	   assign active = active_ip[ip];
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   assign route_ivc_op
	     = route_ip_ivc_op[ip*num_vcs*num_ports:(ip+1)*num_vcs*num_ports-1];
	   
	   
	   //-------------------------------------------------------------------
	   // perform input-side arbitration
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	gnt_out_nonspec_op;
	   assign gnt_out_nonspec_op
	     = gnt_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire 			gnt_out_nonspec;
	   assign gnt_out_nonspec = |gnt_out_nonspec_op;
	   
	   wire 			update_arb_nonspec;
	   assign update_arb_nonspec = gnt_out_nonspec;
	   
	   wire [0:num_vcs-1] 		req_nonspec_ivc;
	   assign req_nonspec_ivc
	     = req_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] 		req_in_nonspec_ivc;
	   assign req_in_nonspec_ivc = req_nonspec_ivc;
	   
	   wire [0:num_vcs-1] 		gnt_in_nonspec_ivc;
	   

	   c_arbiter
	     #(.num_ports(num_vcs),
		    .reset_type(reset_type),
	       .arbiter_type(arbiter_type))
	   gnt_in_nonspec_ivc_arb
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .update(update_arb_nonspec),
	      .req(req_in_nonspec_ivc),
	      .gnt(gnt_in_nonspec_ivc));
	   
	   wire [0:num_ports-1] req_in_nonspec_op;
	   c_select_mofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_in_nonspec_ip_op_sel
	     (.select(req_in_nonspec_ivc),
	      .data_in(route_ivc_op),
	      .data_out(req_in_nonspec_op));
	   
	   assign req_in_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
	     = req_in_nonspec_op;
	   
	   //-------------------------------------------------------------------
	   // generate requests for output stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_nonspec_op;
	   c_select_mofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_out_nonspec_op_sel
	     (.select(gnt_in_nonspec_ivc),
	      .data_in(route_ivc_op),
	      .data_out(req_out_nonspec_op));
	   
	   assign req_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
	     = req_out_nonspec_op;
	   
	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	sel_nonspec_ivc;
	   assign sel_nonspec_ivc = gnt_in_nonspec_ivc;
	   
	   wire 		gnt_nonspec;
	   assign gnt_nonspec = gnt_out_nonspec;
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	sel_spec_ivc;
	   wire 		gnt_spec;
	   
	    
		
	   assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
	     = {num_ports{1'b0}};
	   assign sel_spec_ivc = {num_vcs{1'b0}};
	   assign gnt_spec = 1'b0;
	   
	   //-------------------------------------------------------------------
	   // combine global grants
	   //-------------------------------------------------------------------
	   
	   assign sel_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sel_nonspec_ivc;
	   assign gnt_nonspec_ip[ip] = gnt_nonspec;
	   assign sel_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sel_spec_ivc;
	   assign gnt_spec_ip[ip] = gnt_spec;
	   	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] req_in_nonspec_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_in_nonspec_op_ip_intl
     (.data_in(req_in_nonspec_ip_op),
      .data_out(req_in_nonspec_op_ip));
   
   wire [0:num_ports*num_ports-1] req_out_nonspec_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_nonspec_op_ip_intl
     (.data_in(req_out_nonspec_ip_op),
      .data_out(req_out_nonspec_op_ip));
   
   wire [0:num_ports*num_ports-1] gnt_out_nonspec_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_nonspec_op_ip_intl
     (.data_in(gnt_out_nonspec_op_ip),
      .data_out(gnt_out_nonspec_ip_op));
   
   wire [0:num_ports*num_ports-1] req_out_spec_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_spec_op_ip_intl
     (.data_in(req_out_spec_ip_op),
      .data_out(req_out_spec_op_ip));
   
   wire [0:num_ports*num_ports-1] gnt_out_spec_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_spec_op_ip_intl
     (.data_in(gnt_out_spec_op_ip),
      .data_out(gnt_out_spec_ip_op));
   
   
   //---------------------------------------------------------------------------
   // mask speculative requests that conflict with non-speculative ones
   //---------------------------------------------------------------------------

   wire [0:num_ports-1] 	  unused_by_nonspec_ip;
   wire [0:num_ports-1] 	  unused_by_nonspec_op;

	     
   assign unused_by_nonspec_ip = {num_ports{1'b0}};
   assign unused_by_nonspec_op = {num_ports{1'b0}};
	     

   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				    op;
      
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire active;
	   assign active = active_op[op];
	   
	   
	   //-------------------------------------------------------------------
	   // perform output-side arbitration (select input port)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_nonspec_ip;
	   assign req_out_nonspec_ip
	     = req_out_nonspec_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   // if any VC requesting this output port was granted at any input
	   // port in the first stage, one of these input ports will be granted
	   // here as well, and we can thus update priorities
	   wire 		update_arb_nonspec;
	   assign update_arb_nonspec  = |req_out_nonspec_ip & ~gnt_op_disable[op];
	   
	   assign gnt_op_taken[op]    = update_arb_nonspec | gnt_op_disable[op];
	   wire [0:num_ports-1] gnt_out_nonspec_ip;

	   
	   c_arbiter
	     #(.num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .reset_type(reset_type))
	   gnt_out_nonspec_ip_arb
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .update(update_arb_nonspec),
	      .req(req_out_nonspec_ip),
	      .gnt(gnt_out_nonspec_ip));

	   
	   
	   //-------------------------------------------------------------------
	   // feed grants back to input stage
	   //-------------------------------------------------------------------

	   //op_disable from high priority allocator kill all grants
	  
	   assign gnt_out_nonspec_op_ip[op*num_ports:(op+1)*num_ports-1]
		    = gnt_op_disable[op]?{num_ports{1'b0}}:gnt_out_nonspec_ip;
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   assign gnt_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1]
	     = {num_ports{1'b0}};
	   
	end      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global outputs
   //---------------------------------------------------------------------------

   assign gnt_op_ip = gnt_out_nonspec_op_ip | gnt_out_spec_op_ip;
   
endmodule
