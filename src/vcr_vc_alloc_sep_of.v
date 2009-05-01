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
module vcr_vc_alloc_sep_of
  (clk, reset, route_ip_ivc_op, inc_rc_ip_ivc, elig_op_ovc, req_ip_ivc, 
   gnt_ip_ivc, gnt_ip_ivc_ovc, gnt_op_ovc, gnt_op_ovc_ip, gnt_op_ovc_ivc);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
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
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
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
	   
	   wire [0:num_vcs-1] req_ivc;
	   assign req_ivc = req_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   assign route_ivc_op = route_ip_ivc_op[ip*num_vcs*num_ports:
						 (ip+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_vcs-1] 		inc_rc_ivc;
	   assign inc_rc_ivc = inc_rc_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_out_ivc_op_ovc;
	   assign gnt_out_ivc_op_ovc
	     = gnt_out_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
				     (ip+1)*num_vcs*num_ports*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] req_out_ivc_op_ovc;
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_in_ivc_op_ovc;
	   wire [0:num_vcs*num_vcs-1] 		gnt_ivc_ovc;
	   wire [0:num_vcs-1] 			gnt_ivc;
	   
	   genvar 				itc;
	   
	   for(itc = 0; itc < num_traffic_classes; itc = itc + 1)
	     begin:itcs
		
		genvar irc;
		
		for(irc = 0; irc < num_routing_classes; irc = irc + 1)
		  begin:ircs
		     
		     genvar icvc;
		     
		     for(icvc = 0; icvc < num_vcs_per_class; icvc = icvc + 1)
		       begin:icvcs
			  
			  //----------------------------------------------------
			  // generate requests for output stage
			  //----------------------------------------------------
			  
			  wire req;
			  assign req = req_ivc[(itc*num_routing_classes+irc)*
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
			  
			  wire [0:num_ports*num_vcs-1] mask_op_ovc;
			  
			  genvar 		       op;
			  
			  for(op = 0; op < num_ports; op = op + 1)
			    begin:ops
			       
			       wire route;
			       assign route = route_op[op];
			       
			       wire [0:num_vcs-1] mask_ovc;
			       wire [0:num_vcs-1] req_out_ovc;
			       
			       genvar 		  otc;
			       
			       for(otc = 0; otc < num_traffic_classes;
				   otc = otc + 1)
				 begin:otcs
				    
				    if(otc == itc)
				      begin
					 
					 genvar orc;
					 
					 for(orc = 0; orc < num_routing_classes;
					     orc = orc + 1)
					   begin:orcs
					      
					      wire mask;
					      
					      if((orc == irc) ||
						 (orc == (irc + 1)))
						assign mask = req & route;
					      else
						assign mask = 1'b0;
					      
					      wire req_out;
					      
					      if(orc == irc)
						assign req_out = mask & ~inc_rc;
					      else if(orc == (irc + 1))
						assign req_out = mask & inc_rc;
					      else
                                                assign req_out = 1'b0;

					      assign mask_ovc[
						       (otc*
							num_routing_classes+
							orc)*
						       num_vcs_per_class:
						       (otc*
							num_routing_classes+
							orc+1)*
						       num_vcs_per_class-1
							      ]
						       = {num_vcs_per_class{
							    mask}};
					      
					      assign req_out_ovc[
						       (otc*
							num_routing_classes+
							orc)*
						       num_vcs_per_class:
						       (otc*
							num_routing_classes+
							orc+1)*
						       num_vcs_per_class-1
							      ]
						       = {num_vcs_per_class{
							    req_out}};
					      
					   end
					 
				      end
				    else
				      begin

					 assign mask_ovc[otc*
							 num_routing_classes*
							 num_vcs_per_class:
							 (otc+1)*
							 num_routing_classes*
							 num_vcs_per_class-1]
						  = {(num_routing_classes*
						      num_vcs_per_class){1'b0}};

					 assign req_out_ovc[otc*
							    num_routing_classes*
							    num_vcs_per_class:
							    (otc+1)*
							    num_routing_classes*
							    num_vcs_per_class-1]
						  = {(num_routing_classes*
						      num_vcs_per_class){1'b0}};

				      end
				    
				 end
			       
			       assign mask_op_ovc[op*num_vcs:(op+1)*num_vcs-1]
					= mask_ovc;
			       
			       assign req_out_ivc_op_ovc[
					 (((itc*num_routing_classes+irc)*
					   num_vcs_per_class+icvc)*
					  num_ports+op)*num_vcs:
					 (((itc*num_routing_classes+irc)*
					   num_vcs_per_class+icvc)*
					  num_ports+op+1)*num_vcs-1]
					= req_out_ovc;
			       
			    end
			  
			  
			  //----------------------------------------------------
			  // input arbitration stage (select output VC)
			  //----------------------------------------------------
			  
			  wire [0:num_ports*num_vcs-1] gnt_out_op_ovc;
			  assign gnt_out_op_ovc
			    = gnt_out_ivc_op_ovc[((itc*num_routing_classes+irc)*
						  num_vcs_per_class+icvc)*
						 num_ports*num_vcs:
						 ((itc*num_routing_classes+irc)*
						  num_vcs_per_class+icvc+1)*
						 num_ports*num_vcs-1];
			  
			  wire [0:num_vcs-1] 	       gnt_out_ovc;
			  c_or_nto1
			    #(.width(num_vcs),
			      .num_ports(num_ports))
			  gnt_out_ovc_or
			    (.data_in(gnt_out_op_ovc),
			     .data_out(gnt_out_ovc));
			  
			  wire 			       gnt_out;
			  if(irc == (num_routing_classes - 1))
			    assign gnt_out
			      = |gnt_out_ovc[(itc*num_routing_classes+irc)*
					     num_vcs_per_class:
					     (itc*num_routing_classes+irc+1)*
					     num_vcs_per_class-1];
			  else
			    assign gnt_out
			      = |gnt_out_ovc[(itc*num_routing_classes+irc)*
					     num_vcs_per_class:
					     (itc*num_routing_classes+irc+2)*
					     num_vcs_per_class-1];
			  
			  wire [0:num_vcs-1] 	       req_in_ovc;
			  assign req_in_ovc = gnt_out_ovc;
			  
			  wire [0:num_vcs-1] 	       gnt_in_ovc;
			  
			  genvar 		       otc;
			  
			  for(otc = 0; otc < num_traffic_classes; otc = otc + 1)
			    begin:otcs
			       
			       genvar orc;
			       
			       for(orc = 0; orc < num_routing_classes;
				   orc = orc + 1)
				 begin:orcs
				    
				    if((otc == itc) &&
				       ((orc == irc) || (orc == (irc + 1))))
				      begin
					 
					 wire [0:num_vcs_per_class-1]
					   req_in_ocvc;
					 
					 assign req_in_ocvc
					   = req_in_ovc[(otc*
							 num_routing_classes+
							 orc)*
							num_vcs_per_class:
							(otc*
							 num_routing_classes+
							 orc+1)*
							num_vcs_per_class-1];
					 
					 wire [0:num_vcs_per_class-1]
					   gnt_in_ocvc;
					 
					 if(num_vcs_per_class > 1)
					   begin
					      
					      wire [0:num_vcs_per_class-1]
						gnt_out_ocvc;
					      
					      assign gnt_out_ocvc
						= gnt_out_ovc[
						    (otc*num_routing_classes+
						     orc)*num_vcs_per_class:
						    (otc*num_routing_classes+
						     orc+1)*num_vcs_per_class
							      -1];
					      
					      wire update_arb;
					      assign update_arb = |gnt_out_ocvc;
					      
					      c_arbiter
						#(.num_ports(num_vcs_per_class),
						  .arbiter_type(arbiter_type),
						  .reset_type(reset_type))
					      gnt_in_ocvc_arb
						(.clk(clk),
						 .reset(reset),
						 .update(update_arb),
						 .req(req_in_ocvc),
						 .gnt(gnt_in_ocvc));

					   end
					 else
					   assign gnt_in_ocvc = req_in_ocvc;
					 
					 assign gnt_in_ovc[(otc*
							    num_routing_classes+
							    orc)*
							   num_vcs_per_class:
							   (otc*
							    num_routing_classes+
							    orc+1)*
							   num_vcs_per_class-1]
						  = gnt_in_ocvc;
					 
				      end
				    else
				      assign gnt_in_ovc[(otc*
							 num_routing_classes+
							 orc)*
							num_vcs_per_class:
							(otc*
							 num_routing_classes+
							 orc+1)*
							num_vcs_per_class-1]
					       = {num_vcs_per_class{1'b0}};
				    
				 end
			       
			    end
			  
			  wire [0:num_ports*num_vcs-1] 	     gnt_in_op_ovc;
			  assign gnt_in_op_ovc
			    = mask_op_ovc & {num_ports{gnt_in_ovc}};
			  
			  assign gnt_in_ivc_op_ovc[((itc*num_routing_classes+
						     irc)*
						    num_vcs_per_class+
						    icvc)*
						   num_ports*num_vcs:
						   ((itc*num_routing_classes+
						     irc)*
						    num_vcs_per_class+
						    icvc+1)*
						   num_ports*num_vcs-1]
				   = gnt_in_op_ovc;
			  
			  
			  //----------------------------------------------------
			  // generate global grants
			  //----------------------------------------------------
			  
			  assign gnt_ivc_ovc[((itc*num_routing_classes+irc)*
					      num_vcs_per_class+icvc)*
					     num_vcs:
					     ((itc*num_routing_classes+irc)*
					      num_vcs_per_class+icvc+1)*
					     num_vcs-1]
				   = gnt_in_ovc;
			  
			  assign gnt_ivc[(itc*num_routing_classes+irc)*
					 num_vcs_per_class+icvc]
				   = gnt_out;
			  
		       end
		     
		  end
		
	     end
	   
	   assign req_out_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
					(ip+1)*num_vcs*num_ports*num_vcs-1]
		    = req_out_ivc_op_ovc;
	   
	   assign gnt_in_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
				       (ip+1)*num_vcs*num_ports*num_vcs-1]
		    = gnt_in_ivc_op_ovc;
	   
	   assign gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:(ip+1)*num_vcs*num_vcs-1]
		    = gnt_ivc_ovc;
	   
	   assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = gnt_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	     gnt_in_op_ovc;
   c_or_nto1
     #(.width(num_ports*num_vcs),
       .num_ports(num_ports*num_vcs))
   gnt_in_op_ovc_or
     (.data_in(gnt_in_ip_ivc_op_ovc),
      .data_out(gnt_in_op_ovc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_op_ovc_ip_ivc;
   c_interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   req_out_op_ovc_ip_ivc_intl
     (.data_in(req_out_ip_ivc_op_ovc),
      .data_out(req_out_op_ovc_ip_ivc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_op_ovc_ip_ivc;
   c_interleaver
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
	   
	   wire [0:num_vcs-1] gnt_in_ovc;
	   assign gnt_in_ovc = gnt_in_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] req_out_ovc_ip_ivc;
	   assign req_out_ovc_ip_ivc
	     = req_out_op_ovc_ip_ivc[op*num_vcs*num_ports*num_vcs:
				     (op+1)*num_vcs*num_ports*num_vcs-1];
	   
	   wire [0:num_vcs-1] 			elig_ovc;
	   assign elig_ovc = elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_out_ovc_ip_ivc;
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
			  
			  //----------------------------------------------------
			  // second stage arbitration (select input port and VC)
			  //----------------------------------------------------
			  
			  wire gnt_in;
			  assign gnt_in
			    = gnt_in_ovc[(otc*num_routing_classes+orc)*
					 num_vcs_per_class+ocvc];
			  
			  wire [0:num_ports*num_vcs-1] req_out_ip_ivc;
			  assign req_out_ip_ivc
			    = req_out_ovc_ip_ivc[((otc*num_routing_classes+orc)*
						  num_vcs_per_class+ocvc)*
						 num_ports*num_vcs:
						 ((otc*num_routing_classes+orc)*
						  num_vcs_per_class+ocvc+1)*
						 num_ports*num_vcs-1];
			  
			  wire 			       elig;
			  assign elig
			    = elig_ovc[(otc*num_routing_classes+orc)*
				       num_vcs_per_class+ocvc];
			  
			  wire [0:num_ports-1] 	       req_out_ip;
			  wire [0:num_ports-1] 	       gnt_out_ip;
			  
			  wire [0:num_ports*num_vcs-1] gnt_out_ip_ivc;
			  wire [0:num_ports*num_vcs-1] gnt_ip_ivc;
			  
			  genvar 		       ip;
			  
			  for(ip = 0; ip < num_ports; ip = ip + 1)
			    begin:ips
			       
			       wire [0:num_vcs-1] req_out_ivc;
			       assign req_out_ivc
				 = req_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
			       
			       wire [0:num_vcs-1] gnt_out_ivc;
			       
			       genvar 		  itc;
			       
			       for(itc = 0; itc < num_traffic_classes;
				   itc = itc + 1)
				 begin:itcs
				    
				    wire [0:num_routing_classes*
					  num_vcs_per_class-1] gnt_out_irc_icvc;
				    
				    if(itc == otc)
				      begin
					 
					 wire [0:num_routing_classes*
					       num_vcs_per_class-1]
					   req_out_irc_icvc;
					 assign req_out_irc_icvc
					   = req_out_ivc[itc*
							 num_routing_classes*
							 num_vcs_per_class:
							 (itc+1)*
							 num_routing_classes*
							 num_vcs_per_class-1];
					 
					 assign req_out_ip[ip]
						  = |req_out_irc_icvc;
					 
					 if(orc == 0)
					   begin
					      
					      wire [0:num_vcs_per_class-1]
						req_out_icvc;
					      assign req_out_icvc
						= req_out_irc_icvc[
						    0:num_vcs_per_class-1];

					      wire [0:num_vcs_per_class-1]
						gnt_out_icvc;
					      
					      if(num_vcs_per_class > 1)
						begin
						   
						   wire update_arb;
						   assign update_arb
						     = gnt_in & gnt_out_ip[ip];
						   
						   c_arbiter
						     #(.num_ports(
							     num_vcs_per_class),
						       .arbiter_type(
							     arbiter_type),
						       .reset_type(reset_type))
						   gnt_out_icvc_arb
						     (.clk(clk),
						      .reset(reset),
						      .update(update_arb),
						      .req(req_out_icvc),
						      .gnt(gnt_out_icvc));
						   
						end
					      else
						assign gnt_out_icvc
						  = req_out_icvc;
					      
					      assign gnt_out_irc_icvc[
						       0:num_vcs_per_class-1]
						       = gnt_out_icvc;
					      if(num_routing_classes > 1)
						assign gnt_out_irc_icvc[
						       num_vcs_per_class:
						       num_routing_classes*
						       num_vcs_per_class-1]
						  = {((num_routing_classes-1)*
						      num_vcs_per_class){1'b0}};
					      
					   end
					 else
					   begin
					      
					      wire [0:num_vcs_per_class-1]
						req_out_low_icvc;
					      assign req_out_low_icvc
						= req_out_irc_icvc[
						   (orc-1)*num_vcs_per_class:
						   orc*num_vcs_per_class-1];
					      
					      wire [0:num_vcs_per_class-1]
						req_out_high_icvc;
					      assign req_out_high_icvc
					        = req_out_irc_icvc[
						   orc*num_vcs_per_class:
						   (orc+1)*num_vcs_per_class-1];

					      wire [0:num_vcs_per_class-1]
						gnt_out_low_icvc;
					      wire [0:num_vcs_per_class-1]
						gnt_out_high_icvc;
					      
					      wire update_arb;
					      assign update_arb
						= gnt_in & gnt_out_ip[ip];
					      
					      c_arbiter
						#(.num_ports(
							  2*num_vcs_per_class),
						  .arbiter_type(arbiter_type),
						  .reset_type(reset_type))
					      gnt_out_icvc_arb
						(.clk(clk),
						 .reset(reset),
						 .update(update_arb),
						 .req({req_out_low_icvc,
						       req_out_high_icvc}),
						 .gnt({gnt_out_low_icvc,
						       gnt_out_high_icvc}));
					      
					      if(orc > 1)
						assign gnt_out_irc_icvc[
						         0:(orc-1)*
							 num_vcs_per_class-1]
						  = {((orc-1)*
						      num_vcs_per_class){1'b0}};
					      
					      assign gnt_out_irc_icvc[
						       (orc-1)*
						       num_vcs_per_class:
						       (orc+1)*
						       num_vcs_per_class-1]
						       = {gnt_out_low_icvc,
							  gnt_out_high_icvc};

					      if(orc < (num_routing_classes-1))
						assign gnt_out_irc_icvc[
							 (orc+1)*
							 num_vcs_per_class:
							 num_routing_classes*
							 num_vcs_per_class-1]
						  = {(((num_routing_classes-1)-
						       orc)*
						      num_vcs_per_class){1'b0}};
					      
					   end
					 
				      end
				    else
				      assign gnt_out_irc_icvc
					= {(num_routing_classes*
					    num_vcs_per_class){1'b0}};
				    
				    assign gnt_out_ivc[itc*
						       num_routing_classes*
						       num_vcs_per_class:
						       (itc+1)*
						       num_routing_classes*
						       num_vcs_per_class-1]
					     = gnt_out_irc_icvc;
				    
				 end
			       
			       assign gnt_out_ip_ivc[ip*num_vcs:
						     (ip+1)*num_vcs-1]
					= gnt_out_ivc &
					  {num_vcs{gnt_out_ip[ip] & elig}};
			       assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
					= gnt_out_ivc;
			       
			    end
			  
			  wire [0:num_vcs-1] 	  gnt_ivc;
			  c_select_1ofn
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_ivc_sel
			    (.select(gnt_out_ip),
			     .data_in(gnt_ip_ivc),
			     .data_out(gnt_ivc));
			  
			  wire 			  update_arb;
			  assign update_arb = gnt_in;
			  
			  c_arbiter
			    #(.num_ports(num_ports),
			      .arbiter_type(arbiter_type),
			      .reset_type(reset_type))
			  gnt_out_ip_arb
			    (.clk(clk),
			     .reset(reset),
			     .update(update_arb),
			     .req(req_out_ip),
			     .gnt(gnt_out_ip));
			  
			  assign gnt_out_ovc_ip_ivc[((otc*num_routing_classes+
						      orc)*
						     num_vcs_per_class+
						     ocvc)*
						    num_ports*num_vcs:
						    ((otc*num_routing_classes+
						      orc)*
						     num_vcs_per_class+
						     ocvc+1)*
						    num_ports*num_vcs-1]
				   = gnt_out_ip_ivc;
			  assign gnt_ovc_ip[((otc*num_routing_classes+orc)*
					     num_vcs_per_class+ocvc)*
					    num_ports:
					    ((otc*num_routing_classes+orc)*
					     num_vcs_per_class+ocvc+1)*
					    num_ports-1]
				   = gnt_out_ip;
			  assign gnt_ovc_ivc[((otc*num_routing_classes+orc)*
					      num_vcs_per_class+ocvc)*
					     num_vcs:
					     ((otc*num_routing_classes+orc)*
					      num_vcs_per_class+ocvc+1)*
					     num_vcs-1]
				   = gnt_ivc;
			  
		       end
		     
		  end
		
	     end
	   
	   assign gnt_out_op_ovc_ip_ivc[op*num_vcs*num_ports*num_vcs:
					(op+1)*num_vcs*num_ports*num_vcs-1]
		    = gnt_out_ovc_ip_ivc;
	   
	   assign gnt_op_ovc_ip[op*num_vcs*num_ports:(op+1)*num_vcs*num_ports-1]
		    = gnt_ovc_ip;
	   
	   assign gnt_op_ovc_ivc[op*num_vcs*num_vcs:(op+1)*num_vcs*num_vcs-1]
		    = gnt_ovc_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grant
   //---------------------------------------------------------------------------
   
   assign gnt_op_ovc = gnt_in_op_ovc;
   
endmodule
