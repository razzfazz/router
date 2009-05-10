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

// VC allocator variant using separable input-first allocation
module vcr_vc_alloc_sep_if
  (clk, reset, route_port_ip_ivc, inc_rc_ip_ivc, elig_op_ovc, req_ip_ivc, 
   gnt_ip_ivc, gnt_ip_ivc_ovc, gnt_op_ovc, gnt_op_ovc_ip, gnt_op_ovc_ivc);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port select
   input [0:num_ports*num_vcs*port_idx_width-1] route_port_ip_ivc;
   
   // transition to next resource class
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
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   wire [0:num_vcs-1] req_ivc;
	   assign req_ivc = req_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*port_idx_width-1] route_port_ivc;
	   assign route_port_ivc
	     = route_port_ip_ivc[ip*num_vcs*port_idx_width:
				 (ip+1)*num_vcs*port_idx_width-1];
	   
	   wire [0:num_vcs-1] 		inc_rc_ivc;
	   assign inc_rc_ivc = inc_rc_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_out_ivc_op_ovc;
	   assign gnt_out_ivc_op_ovc
	     = gnt_out_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
				     (ip+1)*num_vcs*num_ports*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] req_out_ivc_op_ovc;
	   wire [0:num_vcs*num_vcs-1] 		gnt_ivc_ovc;
	   wire [0:num_vcs-1] 			gnt_ivc;
	   
	   genvar imc;
	   
	   for(imc = 0; imc < num_message_classes; imc = imc + 1)
	     begin:imcs
		
		genvar irc;
		
		for(irc = 0; irc < num_resource_classes; irc = irc + 1)
		  begin:ircs
		     
		     genvar icvc;
		     
		     for(icvc = 0; icvc < num_vcs_per_class; icvc = icvc + 1)
		       begin:icvcs
			  
			  //----------------------------------------------------
			  // input-side arbitration stage (select output VC)
			  //----------------------------------------------------
			  
			  wire [0:port_idx_width-1] route_port;
			  assign route_port
			    = route_port_ivc[((imc*num_resource_classes+irc)*
					      num_vcs_per_class+icvc)*
					     port_idx_width:
					     ((imc*num_resource_classes+irc)*
					      num_vcs_per_class+icvc+1)*
					     port_idx_width-1];
			  
			  wire 			     inc_rc;
			  assign inc_rc
			    = inc_rc_ivc[(imc*num_resource_classes+irc)*
					 num_vcs_per_class+icvc];
			  
			  wire [0:num_vcs-1] 	     elig_ovc;
			  assign elig_ovc
			    = elig_op_ovc[route_port*num_vcs +: num_vcs];
			  
			  wire [0:num_ports*num_vcs-1] gnt_out_op_ovc;
			  assign gnt_out_op_ovc
			    = gnt_out_ivc_op_ovc[((imc*num_resource_classes+
						   irc)*
						  num_vcs_per_class+icvc)*
						 num_ports*num_vcs:
						 ((imc*num_resource_classes+
						   irc)*
						  num_vcs_per_class+icvc+1)*
						 num_ports*num_vcs-1];
			  
			  wire [0:num_vcs-1] 	       gnt_out_ovc;
			  c_or_nto1
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_out_ovc_or
			    (.data_in(gnt_out_op_ovc),
			     .data_out(gnt_out_ovc));
			  
			  wire [0:num_vcs-1] 	       gnt_in_ovc;
			  
			  genvar 		       omc;
			  
			  for(omc = 0; omc < num_message_classes; omc = omc + 1)
			    begin:omcs
			       
			       if(omc == imc)
				 begin
				    
				    genvar orc;
				    
				    for(orc = 0; orc < num_resource_classes;
					orc = orc + 1)
				      begin:orcs
					 
					 wire [0:num_vcs_per_class-1] 
                                           gnt_in_ocvc;
					 
					 if((orc == irc) || (orc == (irc + 1)))
					   begin

					      wire [0:num_vcs_per_class-1]
						elig_ocvc;
					      assign elig_ocvc
						= elig_ovc[
						      (omc*
						       num_resource_classes+
						       orc)*
						      num_vcs_per_class:
						      (omc*
						       num_resource_classes+
						       orc+1)*
						      num_vcs_per_class-1];
					      
					      wire [0:num_vcs_per_class-1] 
						req_in_ocvc;
					      
					      // Perform input-side arbitration
					      // regardless of whether there was
					      // a request; instead, requests 
					      // are subsequently only 
					      // propagated to the output stage 
					      // if there was a requests.
					      if((orc == irc) &&
						 (irc == 
						  (num_resource_classes - 1)))
						assign req_in_ocvc
						 = elig_ocvc;
					      else if(orc == irc)
						assign req_in_ocvc
						 = elig_ocvc &
						   {num_vcs_per_class{~inc_rc}};
					      else if (orc == (irc + 1))
						assign req_in_ocvc
						 = elig_ocvc &
						   {num_vcs_per_class{inc_rc}};
					      
					      if(num_vcs_per_class > 1)
						begin
						   
 						   wire [0:num_vcs_per_class-1]
						     gnt_out_ocvc;
						   
						   assign gnt_out_ocvc
						     = gnt_out_ovc[
							 (omc*
							  num_resource_classes+
						          orc)*
							 num_vcs_per_class:
							 (omc*
							  num_resource_classes+
							  orc+1)*
							 num_vcs_per_class-1
								   ];
						   
						   wire update_arb;
						   assign update_arb
						     = |gnt_out_ocvc;
					      
						   c_arbiter
						     #(.num_ports(
							  num_vcs_per_class),
						       .arbiter_type(
							  arbiter_type),
						       .reset_type(reset_type))
						   gnt_in_ocvc_arb
						     (.clk(clk),
						      .reset(reset),
						      .update(update_arb),
						      .req(req_in_ocvc),
						      .gnt(gnt_in_ocvc));
						   
						end
					      else
						assign gnt_in_ocvc
						  = req_in_ocvc;
					 
					   end
					 else
					   assign gnt_in_ocvc
					     = {num_vcs_per_class{1'b0}};
					 
					 assign gnt_in_ovc[
						       (omc*
							num_resource_classes+
							orc)*
						       num_vcs_per_class:
						       (omc*
							num_resource_classes+
							orc+1)*
						       num_vcs_per_class-1]
						  = gnt_in_ocvc;
					 
				      end
				    
				 end
			       else
				 assign gnt_in_ovc[omc*num_resource_classes*
						   num_vcs_per_class:
						   (omc+1)*num_resource_classes*
						   num_vcs_per_class-1]
					  = {(num_resource_classes*
					      num_vcs_per_class){1'b0}};
			       
			    end
			  
			  
			  //----------------------------------------------------
			  // generate requests for output stage
			  //----------------------------------------------------
			  
			  wire 					 req;
			  assign req = req_ivc[(imc*num_resource_classes+irc)*
					       num_vcs_per_class+icvc];
			  
			  genvar 				 op;
			  
			  for(op = 0; op < num_ports; op = op + 1)
			    begin:ops
			       
			       wire route;
			       assign route = (route_port == op);
			       
			       wire [0:num_vcs-1] req_out_ovc;
			       assign req_out_ovc
				 = {num_vcs{req & route}} & gnt_in_ovc;
			       
			       assign req_out_ivc_op_ovc[
                                  (((imc*num_resource_classes+irc)*
				    num_vcs_per_class+icvc)*
				   num_ports+op)*num_vcs:
				  (((imc*num_resource_classes+irc)*
				    num_vcs_per_class+icvc)*
				   num_ports+op+1)*num_vcs-1]
					= req_out_ovc;
			       
			    end
			  
			  
			  //----------------------------------------------------
			  // generate global grants
			  //----------------------------------------------------
			  
			  wire [0:num_vcs-1] 		  gnt_ovc;
			  c_or_nto1
			    #(.width(num_vcs),
			      .num_ports(num_ports))
			  gnt_ovc_or
			    (.data_in(gnt_out_op_ovc),
			     .data_out(gnt_ovc));
			  
			  assign gnt_ivc_ovc[((imc*num_resource_classes+irc)*
					      num_vcs_per_class+icvc)*
					     num_vcs:
					     ((imc*num_resource_classes+irc)*
					      num_vcs_per_class+icvc+1)*
					     num_vcs-1]
				   = gnt_ovc;
			  
			  wire 				  gnt;
			  if(irc == (num_resource_classes - 1))
			    assign gnt
			      = |gnt_ovc[(imc*num_resource_classes+irc)*
					 num_vcs_per_class:
					 (imc*num_resource_classes+irc+1)*
					 num_vcs_per_class-1];
			  else
			    assign gnt
			      = |gnt_ovc[(imc*num_resource_classes+irc)*
					 num_vcs_per_class:
					 (imc*num_resource_classes+irc+2)*
					 num_vcs_per_class-1];
			  
			  assign gnt_ivc[(imc*num_resource_classes+irc)*
					 num_vcs_per_class+icvc]
				   = gnt;
			  
		       end
		     
		  end
		
	     end
	   
	   assign req_out_ip_ivc_op_ovc[ip*num_vcs*num_ports*num_vcs:
					(ip+1)*num_vcs*num_ports*num_vcs-1]
		    = req_out_ivc_op_ovc;
	   
	   assign gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:(ip+1)*num_vcs*num_vcs-1]
		    = gnt_ivc_ovc;
	   
	   assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = gnt_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
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
   gnt_out_op_ovc_ip_ivc_intl
     (.data_in(gnt_out_op_ovc_ip_ivc),
      .data_out(gnt_out_ip_ivc_op_ovc));
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  op;
      
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] req_out_ovc_ip_ivc;
	   assign req_out_ovc_ip_ivc
	     = req_out_op_ovc_ip_ivc[op*num_vcs*num_ports*num_vcs:
				     (op+1)*num_vcs*num_ports*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports*num_vcs-1] gnt_out_ovc_ip_ivc;
	   wire [0:num_vcs-1] 			gnt_ovc;
	   wire [0:num_vcs*num_ports-1] 	gnt_ovc_ip;
	   wire [0:num_vcs*num_vcs-1] 		gnt_ovc_ivc;
	   
	   genvar 				omc;
	   
	   for(omc = 0; omc < num_message_classes; omc = omc + 1)
	     begin:omcs
		
		genvar orc;
		
		for(orc = 0; orc < num_resource_classes; orc = orc + 1)
		  begin:orcs
		     
		     genvar ocvc;
		     
		     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
		       begin:ocvcs
			  
			  //----------------------------------------------------
			  // output-side arbitration (select input port and VC)
			  //----------------------------------------------------
			  
			  wire [0:num_ports*num_vcs-1] req_out_ip_ivc;
			  assign req_out_ip_ivc
			    = req_out_ovc_ip_ivc[((omc*num_resource_classes+
						   orc)*
						  num_vcs_per_class+ocvc)*
						 num_ports*num_vcs:
						 ((omc*num_resource_classes+
						   orc)*
						  num_vcs_per_class+ocvc+1)*
						 num_ports*num_vcs-1];
			  
			  wire [0:num_vcs*num_ports-1] req_out_ivc_ip;
			  c_interleaver
			    #(.width(num_ports*num_vcs),
			      .num_blocks(num_ports))
			  req_out_ivc_op_intl
			    (.data_in(req_out_ip_ivc),
			     .data_out(req_out_ivc_ip));
			  
			  wire [0:num_resource_classes*num_vcs_per_class*
				num_ports-1] 	       req_out_irc_icvc_ip;
			  assign req_out_irc_icvc_ip
			    = req_out_ivc_ip[omc*num_resource_classes*
					     num_vcs_per_class*num_ports:
					     (omc+1)*num_resource_classes*
					     num_vcs_per_class*num_ports-1];
			  
			  wire [0:num_ports-1] 	       req_out_ip;
			  c_or_nto1
			    #(.width(num_ports),
			      .num_ports(num_resource_classes*
					 num_vcs_per_class))
			  req_out_ip_or
			    (.data_in(req_out_irc_icvc_ip),
			     .data_out(req_out_ip));
			  
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
			       
			       genvar 		  imc;
			       
			       for(imc = 0; imc < num_message_classes;
				   imc = imc + 1)
				 begin:imcs
				    
				    wire [0:num_resource_classes*
					  num_vcs_per_class-1] gnt_out_irc_icvc;
				    
				    if(imc == omc)
				      begin
					 
					 wire [0:num_resource_classes*
					       num_vcs_per_class-1]
					   req_out_irc_icvc;
					 assign req_out_irc_icvc
					   = req_out_ivc[imc*
							 num_resource_classes*
							 num_vcs_per_class:
							 (imc+1)*
							 num_resource_classes*
							 num_vcs_per_class-1];
					 
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
						     = gnt_out_ip[ip];
						   
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
					      if(num_resource_classes > 1)
						assign gnt_out_irc_icvc[
						       num_vcs_per_class:
						       num_resource_classes*
						       num_vcs_per_class-1]
						  = {((num_resource_classes-1)*
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
						= gnt_out_ip[ip];
					      
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

					      if(orc < (num_resource_classes-1))
						assign gnt_out_irc_icvc[
							 (orc+1)*
							 num_vcs_per_class:
							 num_resource_classes*
							 num_vcs_per_class-1]
						  = {(((num_resource_classes-1)-
						       orc)*
						      num_vcs_per_class){1'b0}};
					      
					   end
					 
				      end
				    else
				      assign gnt_out_irc_icvc
					= {(num_resource_classes*
					    num_vcs_per_class){1'b0}};
				    
				    assign gnt_out_ivc[imc*
						       num_resource_classes*
						       num_vcs_per_class:
						       (imc+1)*
						       num_resource_classes*
						       num_vcs_per_class-1]
					       = gnt_out_irc_icvc;

				 end
			       
			       assign gnt_out_ip_ivc[ip*num_vcs:
						     (ip+1)*num_vcs-1]
					= gnt_out_ivc & 
					  {num_vcs{gnt_out_ip[ip]}};
			       assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
					= gnt_out_ivc;
			       
			    end
			  
			  wire [0:num_vcs-1] 	   gnt_ivc;
			  c_select_1ofn
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_ivc_sel
			    (.select(gnt_out_ip),
			     .data_in(gnt_ip_ivc),
			     .data_out(gnt_ivc));
			  
			  wire 			   req_out;
			  assign req_out = |req_out_ip;
			  
			  wire 			   update_arb;
			  assign update_arb = req_out;
			  
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
			  
			  assign gnt_out_ovc_ip_ivc[((omc*num_resource_classes+
						      orc)*
						     num_vcs_per_class+ocvc)*
						    num_ports*num_vcs:
						    ((omc*num_resource_classes+
						      orc)*
						     num_vcs_per_class+ocvc+1)*
						    num_ports*num_vcs-1]
				   = gnt_out_ip_ivc;
			  assign gnt_ovc[(omc*num_resource_classes+orc)*
					 num_vcs_per_class+ocvc]
				   = req_out;
			  assign gnt_ovc_ip[((omc*num_resource_classes+orc)*
					     num_vcs_per_class+ocvc)*
					    num_ports:
					    ((omc*num_resource_classes+orc)*
					     num_vcs_per_class+ocvc+1)*
					    num_ports-1]
				   = gnt_out_ip;
			  assign gnt_ovc_ivc[((omc*num_resource_classes+orc)*
					      num_vcs_per_class+ocvc)*
					     num_vcs:
					     ((omc*num_resource_classes+orc)*
					      num_vcs_per_class+ocvc+1)*
					     num_vcs-1]
				   = gnt_ivc;
			  
		       end
		     
		  end
		
	     end
	   
	   assign gnt_out_op_ovc_ip_ivc[op*num_vcs*num_ports*num_vcs:
					(op+1)*num_vcs*num_ports*num_vcs-1]
		    = gnt_out_ovc_ip_ivc;
	   
	   assign gnt_op_ovc[op*num_vcs:(op+1)*num_vcs-1]
		    = gnt_ovc;
	   
	   assign gnt_op_ovc_ip[op*num_vcs*num_ports:(op+1)*num_vcs*num_ports-1]
 		    = gnt_ovc_ip;
	   
	   assign gnt_op_ovc_ivc[op*num_vcs*num_vcs:(op+1)*num_vcs*num_vcs-1]
 		    = gnt_ovc_ivc;
	   
	end
      
   endgenerate
   
endmodule
