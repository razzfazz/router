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
  (clk, reset, route_ip_ivc_op, inc_rc_ip_ivc, elig_op_ovc, req_ip_ivc, 
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
   
   // transition to next routing class
   input [0:num_ports*num_vcs-1] inc_rc_ip_ivc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // request VC allocation
   input [0:num_ports*num_vcs-1] req_ip_ivc;
   
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
	   
	   wire [0:num_vcs-1] req_ivc;
	   assign req_ivc = req_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   assign route_ivc_op = route_ip_ivc_op[ip*num_vcs*num_ports:
						 (ip+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_vcs-1] 		inc_rc_ivc;
	   assign inc_rc_ivc = inc_rc_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_wf_ivc_op_ovc;
	   assign gnt_wf_ivc_op_ovc
	     = gnt_wf_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
				    (ip+1)*num_vcs*num_ports*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] req_wf_ivc_op_ovc;
	   wire [0:num_vcs-1] 			gnt_ivc;
	   wire [0:num_vcs*num_vcs-1] 		gnt_ivc_ovc;
	   
	   genvar 			itc;
	   
	   for(itc = 0; itc < num_traffic_classes; itc = itc + 1)
	     begin:itcs
		
		genvar irc;
		
		for(irc = 0; irc < num_routing_classes; irc = irc + 1)
		  begin:ircs
		     
		     genvar icvc;
		     
		     for(icvc = 0; icvc < num_vcs_per_class; icvc = icvc + 1)
		       begin:icvcs
			  
			  wire req;
			  assign req
			    = req_ivc[(itc*num_routing_classes+irc)*
				      num_vcs_per_class+icvc];
			  
			  wire [0:num_ports-1] route_op;
			  assign route_op
			    = route_ivc_op[((itc*num_routing_classes+irc)*
					    num_vcs_per_class+icvc)*
					   num_ports:
					   ((itc*num_routing_classes+irc)*
					    num_vcs_per_class+icvc+1)*
					   num_ports-1];
			  
			  wire 		       inc_rc;
			  assign inc_rc
			    = inc_rc_ivc[(itc*num_routing_classes+irc)*
					 num_vcs_per_class+icvc];
			  
			  wire [0:num_ports*num_vcs-1] req_wf_op_ovc;
			  
			  genvar 		       op;
			  
			  for(op = 0; op < num_ports; op = op + 1)
			    begin:ops
			       
			       wire [0:num_vcs-1] elig_ovc;
			       assign elig_ovc
				 = elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
			       
			       wire 		  route;
			       assign route = route_op[op];
			       
			       wire [0:num_vcs-1] req_wf_ovc;
			       
			       genvar otc;
			       
			       for(otc = 0; otc < num_traffic_classes;
				   otc = otc + 1)
				 begin:otcs
				    
				    genvar orc;
				    
				    for(orc = 0; orc < num_routing_classes;
					orc = orc + 1)
				      begin:orcs

					 wire class_match;
					 
					 if(otc == itc)
					   begin
					      if(orc == irc)
						assign class_match = ~inc_rc;
					      else if(orc == (irc + 1))
						assign class_match  = inc_rc;
					      else
						assign class_match = 1'b0;
					   end
					 else
					   assign class_match = 1'b0;
					 
					 wire [0:num_vcs_per_class-1] elig_ocvc;
					 assign elig_ocvc
					   = elig_ovc[(otc*num_routing_classes+
						       orc)*
						      num_vcs_per_class:
						      (otc*num_routing_classes+
						       orc+1)*
						      num_vcs_per_class-1];
					 
					 wire [0:num_vcs_per_class-1]
					   req_wf_ocvc;
					 assign req_wf_ocvc
					   = {num_vcs_per_class{
						(req & route & class_match)}} &
					     elig_ocvc;
					 
					 assign req_wf_ovc[(otc*
							    num_routing_classes+
							    orc)*
							   num_vcs_per_class:
							   (otc*
							    num_routing_classes+
							    orc+1)*
							   num_vcs_per_class-1]
						  = req_wf_ocvc;
					 
				      end
				    
				 end
			       
			       assign req_wf_op_ovc[op*num_vcs:
						    (op+1)*num_vcs-1]
					= req_wf_ovc;
			       
			    end
			  
			  assign req_wf_ivc_op_ovc[((itc*num_routing_classes+
						     irc)*
						    num_vcs_per_class+icvc)*
						   num_ports*num_vcs:
						   ((itc*num_routing_classes+
						     irc)*
						    num_vcs_per_class+icvc+1)*
						   num_ports*num_vcs-1]
				   = req_wf_op_ovc;
			  
			  wire [0:num_ports*num_vcs-1] gnt_wf_op_ovc;
			  assign gnt_wf_op_ovc
			    = gnt_wf_ivc_op_ovc[((itc*num_traffic_classes+irc)*
						 num_vcs_per_class+icvc)*
						num_ports*num_vcs:
						((itc*num_traffic_classes+irc)*
						 num_vcs_per_class+icvc+1)*
						num_ports*num_vcs-1];
			  
			  wire [0:num_vcs-1] 	       gnt_ovc;
			  or_nto1
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_ovc_or
			    (.data_in(gnt_wf_op_ovc),
			     .data_out(gnt_ovc));
			  
			  assign gnt_ivc_ovc[((itc*num_routing_classes+irc)*
					      num_vcs_per_class+icvc)*
					     num_vcs:
					     ((itc*num_routing_classes+irc)*
					      num_vcs_per_class+icvc+1)*
					     num_vcs-1]
				   = gnt_ovc;
			  
			  if(irc == (num_routing_classes - 1))
			    assign gnt_ivc[(itc*num_routing_classes+irc)*
					   num_vcs_per_class+icvc]
				     = |gnt_ovc[(itc*num_routing_classes+irc)*
						num_vcs_per_class:
						(itc*num_routing_classes+irc+1)*
						num_vcs_per_class-1];
			  else
			    assign gnt_ivc[(itc*num_routing_classes+irc)*
					   num_vcs_per_class+icvc]
				     = |gnt_ovc[(itc*num_routing_classes+irc)*
						num_vcs_per_class:
						(itc*num_routing_classes+irc+2)*
						num_vcs_per_class-1];
			  
		       end
		     
		  end
		
	     end
	   
	   assign req_wf_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
				       (ip+1)*num_vcs*num_ports*num_vcs-1]
		    = req_wf_ivc_op_ovc;
	   assign gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:(ip+1)*num_vcs*num_vcs-1]
		    = gnt_ivc_ovc;
	   assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = gnt_ivc;
	   
	end
      
      genvar 					       op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_wf_ovc_ip_ivc;
	   assign gnt_wf_ovc_ip_ivc
		  = gnt_wf_op_ovc_ip_ivc[op*num_vcs*num_ports*num_vcs:
					 (op+1)*num_vcs*num_ports*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] 	gnt_ovc_ip;
	   wire [0:num_vcs*num_vcs-1] 		gnt_ovc_ivc;
	   
	   genvar 				otc;
	   
	   for(otc = 0; otc < num_traffic_classes; otc = otc + 1)
	     begin:otcs
		
		genvar orc;
		
		for(orc = 0; orc < num_routing_classes; orc = orc + 1)
		  begin:orcs
		     
		     genvar ocvc;
		     
		     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
		       begin:ocvcs
			  
			  wire [0:num_ports*num_vcs-1] gnt_wf_ip_ivc;
			  assign gnt_wf_ip_ivc
			    = gnt_wf_ovc_ip_ivc[((otc*num_routing_classes+orc)*
						 num_vcs_per_class+ocvc)*
						num_ports*num_vcs:
						((otc*num_routing_classes+orc)*
						 num_vcs_per_class+ocvc+1)*
						num_ports*num_vcs-1];
			  
			  wire [0:num_ports-1] 	       gnt_wf_ip;
			  
			  genvar 		       ip;
			  
			  for(ip = 0; ip < num_ports; ip = ip + 1)
			    begin:ips
			       
			       wire [0:num_vcs-1] gnt_wf_ivc;
			       assign gnt_wf_ivc
				 = gnt_wf_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
			       
			       if(orc == 0)
				 assign gnt_wf_ip[ip]
					  = |gnt_wf_ivc[otc*
							num_routing_classes*
							num_vcs_per_class:
							(otc*
							 num_routing_classes+1)*
							num_vcs_per_class-1];
			       else
				 assign gnt_wf_ip[ip]
					  = |gnt_wf_ivc[(otc*
							 num_routing_classes+
							 orc-1)*
							num_vcs_per_class:
							(otc*
							 num_routing_classes+
							 orc+1)*
							num_vcs_per_class-1];
			       
			    end

			  wire [0:num_vcs-1] 	  gnt_wf_ivc;
			  or_nto1
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_wf_ivc_or
			    (.data_in(gnt_wf_ip_ivc),
			     .data_out(gnt_wf_ivc));
			  
			  assign gnt_ovc_ip[((otc*num_routing_classes+orc)*
					     num_vcs_per_class+ocvc)*
					    num_ports:
					    ((otc*num_routing_classes+orc)*
					     num_vcs_per_class+ocvc+1)*
					    num_ports-1]
				   = gnt_wf_ip;
			  assign gnt_ovc_ivc[((otc*num_routing_classes+orc)*
					      num_vcs_per_class+ocvc)*
					     num_vcs:
					     ((otc*num_routing_classes+orc)*
					      num_vcs_per_class+ocvc+1)*
					     num_vcs-1]
				   = gnt_wf_ivc;
			  
		       end
		     
		  end
		
	     end
	   
	   assign gnt_op_ovc_ip[op*num_vcs*num_ports:(op+1)*num_vcs*num_ports-1]
		    = gnt_ovc_ip;
	   assign gnt_op_ovc_ivc[op*num_vcs*num_vcs:(op+1)*num_vcs*num_vcs-1]
		    = gnt_ovc_ivc;
	   
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
