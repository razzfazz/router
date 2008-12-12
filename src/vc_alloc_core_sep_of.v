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

// VC allocator variant using separable output-first allocation
module vc_alloc_core_sep_of
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, elig_op_ovc, gnt_ip_ivc_ovc, 
   gnt_op_ovc);
   
`include "constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // request VC allocation for given port (for each input VC)
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   
   // allowable VCs for VC allocation (for each input VC)
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // granted output VC (to inpt controller)
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 	gnt_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_in_ip_ivc_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   genvar ivc;
	   
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		//--------------------------------------------------------------
		// generate requests for output stage
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 	     req_op;
		assign req_op
		  = req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				  (ip*num_vcs+ivc+1)*num_ports-1];
		
		wire [0:num_vcs-1] 	     req_ovc;
		assign req_ovc
		  = req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				   (ip*num_vcs+ivc+1)*num_vcs-1];
		
		wire [0:num_ports*num_vcs-1] req_op_ovc;
		replicator
		  #(.width(num_ports),
		    .count(num_vcs))
		req_op_ovc_repl
		  (.data_in(req_op),
		   .data_out(req_op_ovc));
		
		wire [0:num_ports*num_vcs-1] req_out_op_ovc;
		assign req_out_op_ovc = req_op_ovc & {num_ports{req_ovc}};
		
		assign req_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					     (ip*num_vcs+ivc+1)*num_ports*
					     num_vcs-1]
			 = req_out_op_ovc;
		
		
		//--------------------------------------------------------------
		// input arbitration stage (select output VC)
		//--------------------------------------------------------------
		
		wire [0:num_ports*num_vcs-1] gnt_out_op_ovc;
		assign gnt_out_op_ovc
		  = gnt_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					  (ip*num_vcs+ivc+1)*num_ports*num_vcs
					  -1];
		
		wire [0:num_vcs-1] 	     gnt_out_ovc;
		or_nto1
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		gnt_out_ovc_or
		  (.data_in(gnt_out_op_ovc),
		   .data_out(gnt_out_ovc));
		
		wire 			     update_arb;
		assign update_arb = |gnt_out_ovc;
		
		wire [0:num_vcs-1] 	     req_in_ovc;
		assign req_in_ovc = gnt_out_ovc;
		
		wire [0:num_vcs-1] 	     gnt_in_ovc;
		
		if(num_vcs_per_class > 1)
		  begin
		     arbiter
		       #(.num_ports(num_vcs),
			 .arbiter_type(arbiter_type),
			 .reset_type(reset_type))
		     gnt_in_ovc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb),
			.req(req_in_ovc),
			.gnt(gnt_in_ovc));
		  end
		else
		  assign gnt_in_ovc = req_in_ovc;
		
		wire [0:num_ports*num_vcs-1] gnt_in_op_ovc;
		assign gnt_in_op_ovc = req_op_ovc & {num_ports{gnt_in_ovc}};
		
		assign gnt_in_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					    (ip*num_vcs+ivc+1)*num_ports*num_vcs
					    -1]
			 = gnt_in_op_ovc;
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		assign gnt_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1]
			 = gnt_in_ovc;
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	     gnt_in_op_ovc;
   or_nto1
     #(.width(num_ports*num_vcs),
       .num_ports(num_ports*num_vcs))
   gnt_in_op_ovc_or
     (.data_in(gnt_in_ip_ivc_op_ovc),
      .data_out(gnt_in_op_ovc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   req_out_op_ovc_ip_ivc_intl
     (.data_in(req_out_ip_ivc_op_ovc),
      .data_out(req_out_op_ovc_ip_ivc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   gnt_out_ip_ivc_op_ovc_intl
     (.data_in(gnt_out_op_ovc_ip_ivc),
      .data_out(gnt_out_ip_ivc_op_ovc));
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  op;
      
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   genvar ovc;
	   
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		//--------------------------------------------------------------
		// second stage arbitration (select input port and VC)
		//--------------------------------------------------------------
		
		wire gnt_in;
		assign gnt_in = gnt_in_op_ovc[op*num_vcs+ovc];
		
		wire [0:num_ports*num_vcs-1] req_out_ip_ivc;
		assign req_out_ip_ivc
		  = req_out_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					  (op*num_vcs+ovc+1)*num_ports*num_vcs
					  -1];
		
		wire [0:num_ports-1] 	     req_out_ip;
		wire [0:num_ports-1] 	     gnt_out_ip;
		
		wire [0:num_ports-1] 	     update_arb_ip;
		assign update_arb_ip = {num_ports{gnt_in}} & gnt_out_ip;
		
		wire 			     elig;
		assign elig = elig_op_ovc[op*num_vcs+ovc];
		
		wire [0:num_ports*num_vcs-1] gnt_out_ip_ivc;
		
		genvar 			     ip;
		
		for(ip = 0; ip < num_ports; ip = ip + 1)
		  begin:ips
		     
		     wire [0:num_vcs-1] req_out_ivc;
		     assign req_out_ivc
		       = req_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		     
		     assign req_out_ip[ip] = |req_out_ivc;
		     
		     wire [0:num_vcs-1] gnt_out_ivc;
		     arbiter
		       #(.num_ports(num_vcs),
			 .arbiter_type(arbiter_type),
			 .reset_type(reset_type))
		     gnt_out_ivc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb_ip[ip]),
			.req(req_out_ivc),
			.gnt(gnt_out_ivc));
		     
		     assign gnt_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
			      = gnt_out_ivc & {num_vcs{gnt_out_ip[ip] & elig}};
		     
		  end
		
		wire 			update_arb;
		assign update_arb = gnt_in;
		
		arbiter
		  #(.num_ports(num_ports),
		    .arbiter_type(arbiter_type),
		    .reset_type(reset_type))
		gnt_out_ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req_out_ip),
		   .gnt(gnt_out_ip));
		
		assign gnt_out_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					     (op*num_vcs+ovc+1)*num_ports*
					     num_vcs-1]
			 = gnt_out_ip_ivc;
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grant
   //---------------------------------------------------------------------------
   
   assign gnt_op_ovc = gnt_in_op_ovc;
   
endmodule
