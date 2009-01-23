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

// VC allocator variant based using wavefront allocation
module vc_alloc_core_wf
  (clk, reset, route_ip_ivc_op, req_ip_ivc, req_ip_ivc_ovc, elig_op_ovc, 
   gnt_ip_ivc, gnt_ip_ivc_ovc, gnt_op_ovc, gnt_op_ovc_ip, gnt_op_ovc_ivc);
   
`include "constants.v"
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which wavefront allocator variant to use
   parameter wf_allocator_type = `WF_ALLOCATOR_TYPE_REP;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // request VC allocation
   input [0:num_ports*num_vcs-1] req_ip_ivc;
   
   // allowable VCs for VC allocation
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // VC allocation successful (to input controller)
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   wire [0:num_ports*num_vcs-1] gnt_ip_ivc;
   
   // granted output VC (to input controller)
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 	gnt_op_ovc;
   
   // input port that each output VC was granted to
   output [0:num_ports*num_vcs*num_ports-1] gnt_op_ovc_ip;
   wire [0:num_ports*num_vcs*num_ports-1] gnt_op_ovc_ip;
   
   // input VC that each output VC was granted to
   output [0:num_ports*num_vcs*num_vcs-1] gnt_op_ovc_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1]   gnt_op_ovc_ivc;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_wf_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_wf_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_wf_op_ovc_ip_ivc;
   
   
   //---------------------------------------------------------------------------
   // generate request vector
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   genvar ivc;
	   
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		wire req;
		assign req = req_ip_ivc[ip*num_vcs+ivc];
		
		wire [0:num_ports-1] route_op;
		assign route_op
		  = route_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				    (ip*num_vcs+ivc+1)*num_ports-1];
		
		wire [0:num_vcs-1]   req_ovc;
		assign req_ovc
		  = req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				   (ip*num_vcs+ivc+1)*num_vcs-1];
		
		genvar 		     op;
		
		for(op = 0; op < num_ports; op = op + 1)
		  begin:ops
		     
		     wire [0:num_vcs-1] 	     elig_ovc;
		     assign elig_ovc = elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
		     
		     wire [0:num_vcs-1] 	     req_wf_ovc;
		     assign req_wf_ovc
		       = {num_vcs{req & route_op[op]}} & req_ovc & elig_ovc;
		     
		     assign req_wf_ip_ivc_op_ovc[((ip*num_vcs+ivc)*
						  num_ports+op)*num_vcs:
						 ((ip*num_vcs+ivc)*
						  num_ports+op+1)*num_vcs-1]
			      = req_wf_ovc;
		     
		  end
		
		wire [0:num_ports*num_vcs-1] 	     gnt_wf_op_ovc;
		assign gnt_wf_op_ovc
		  = gnt_wf_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					 (ip*num_vcs+ivc+1)*num_ports*num_vcs
					 -1];
		
		wire [0:num_vcs-1] 		     gnt_ovc;
		or_nto1
		  #(.num_ports(num_ports),
		    .width(num_vcs))
		gnt_ovc_or
		  (.data_in(gnt_wf_op_ovc),
		   .data_out(gnt_ovc));
		
		assign gnt_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1]
			 = gnt_ovc;
		
		wire 				     gnt;
		assign gnt = |gnt_ovc;
		
		assign gnt_ip_ivc[ip*num_vcs+ivc] = gnt;
		
	     end
	   
	end
      
      genvar 					     op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   genvar ovc;
	   
	   for(ovc = 0; ovc < num_ports; ovc = ovc + 1)
	     begin:ovcs
		
		wire [0:num_ports*num_vcs-1] gnt_ip_ivc;
		assign gnt_ip_ivc
		  = gnt_wf_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					 (op*num_vcs+ovc+1)*num_ports*num_vcs
					 -1];
		
		wire [0:num_ports-1] gnt_ip;
		
		genvar ip;
		
		for(ip = 0; ip < num_ports; ip = ip + 1)
		  begin:ips
		     
		     assign gnt_ip[ip]
			      = |gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		     
		  end
		
		wire [0:num_vcs-1] gnt_ivc;
		or_nto1
		  #(.num_ports(num_ports),
		    .width(num_vcs))
		gnt_ivc_or
		  (.data_in(gnt_ip_ivc),
		   .data_out(gnt_ivc));
		
		assign gnt_op_ovc_ip[(op*num_vcs+ovc)*num_ports:
				     (op*num_vcs+ovc+1)*num_ports-1]
			 = gnt_ip;
		assign gnt_op_ovc_ivc[(op*num_vcs+ovc)*num_vcs:
				      (op*num_vcs+ovc+1)*num_vcs-1]
			 = gnt_ivc;
		
	     end
	   
	end
      
   endgenerate
   
   wire 					     update_alloc;
   assign update_alloc = |req_ip_ivc;
   
   wf_alloc
     #(.num_ports(num_ports*num_vcs),
       .wf_allocator_type(wf_allocator_type),
       .reset_type(reset_type))
   gnt_wf_ip_ivc_op_ovc_alloc
     (.clk(clk),
      .reset(reset),
      .update(update_alloc),
      .req(req_wf_ip_ivc_op_ovc),
      .gnt(gnt_wf_ip_ivc_op_ovc));
   
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   gnt_wf_op_ovc_ip_ivc_intl
     (.data_in(gnt_wf_ip_ivc_op_ovc),
      .data_out(gnt_wf_op_ovc_ip_ivc));

   or_nto1
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports*num_vcs))
   gnt_op_ovc_or
     (.data_in(gnt_wf_ip_ivc_op_ovc),
      .data_out(gnt_op_ovc));
   
endmodule
