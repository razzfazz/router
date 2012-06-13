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

//==============================================================================
// VC allocator variant using separable input-first allocation
//==============================================================================

module vcr_vc_alloc_SRP
  (clk, reset, route_ip_ivc_op, route_ip_ivc_orc, elig_op_ovc, req_ip_ivc, 
   gnt_ip_ivc, gnt_ip_ivc_ocvc, gnt_op_ovc, gnt_op_ovc_ip, gnt_op_ovc_ivc);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 1;
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port select
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // select next resource class
   input [0:num_ports*num_vcs-1] route_ip_ivc_orc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] 		      elig_op_ovc;
   
   // request VC allocation
   input [0:num_ports*num_vcs-1] 		      req_ip_ivc;
   
   // VC allocation successful (to input controller)
   output [0:num_ports*num_vcs-1] 		      gnt_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		      gnt_ip_ivc;
   
   // granted output VC (to input controller)
   output [0:num_ports*num_vcs*num_vcs_per_class-1]   gnt_ip_ivc_ocvc;
   wire [0:num_ports*num_vcs*num_vcs_per_class-1]     gnt_ip_ivc_ocvc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] 		      gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 		      gnt_op_ovc;
   
   // input port that each output VC was granted to
   output [0:num_ports*num_vcs*num_ports-1] 	      gnt_op_ovc_ip;
   wire [0:num_ports*num_vcs*num_ports-1] 	      gnt_op_ovc_ip;
   
   // input VC that each output VC was granted to
   output [0:num_ports*num_vcs*num_vcs-1] 	      gnt_op_ovc_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	      gnt_op_ovc_ivc;
   

   //global wires passing between message class 1 and 3, assume num_vcs_per_class=1

   wire [0:num_ports*num_vcs_per_class*num_ports*
	 num_vcs_per_class-1] req_to_class_one;
   wire [0:num_ports*num_vcs_per_class*num_ports*
	 num_vcs_per_class-1] gnt_to_class_three;
      
   wire [0:num_ports-1] expired = {num_ports{1'b0}};


   
   generate
      
      genvar 					      mc;
      
      for(mc = 0; mc < num_message_classes; mc = mc + 1)
	begin:mcs
	   
	   //-------------------------------------------------------------------
	   // global wires
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports*num_vcs_per_class*
		 num_ports*num_vcs_per_class-1] req_out_ip_irc_icvc_op_orc_ocvc;
	   wire [0:num_ports*num_vcs_per_class*
		 num_ports*num_vcs_per_class-1] gnt_out_ip_irc_icvc_op_orc_ocvc;
	   
	   wire [0:num_ports*num_vcs_per_class*num_ports*
		 num_vcs_per_class-1] active_ip_irc_icvc_op_orc_ocvc;
	   
	   
	   //-------------------------------------------------------------------
	   // input stage
	   //-------------------------------------------------------------------
	   
	   genvar ip;
	   
	   for(ip = 0; ip < num_ports; ip = ip + 1)
	     begin:ips
		
		wire [0:num_vcs_per_class-1] req_irc_icvc;
		assign req_irc_icvc = req_ip_ivc[(ip*num_message_classes+mc)*
						 num_vcs_per_class:
						 (ip*num_message_classes+mc+1)*num_vcs_per_class-1];
		
		wire 						  active;
		assign active = |req_irc_icvc;
		genvar icvc;
		
		for(icvc = 0; icvc < num_vcs_per_class; icvc = icvc + 1)
		  begin:icvcs
		     
		     //----------------------------------------------------
		     // input-side arbitration stage (select output VC)
		     //----------------------------------------------------
		     
		     wire [0:num_ports-1] route_op;
		     assign route_op
		       = route_ip_ivc_op[(((ip*num_message_classes+mc))*
					  num_vcs_per_class+icvc)*
					 num_ports:
					 (((ip*num_message_classes+mc))*
					  num_vcs_per_class+icvc+1)*
					 num_ports-1];
		     
		     wire route_orc;
		     
		     assign route_orc = 1'b1;
		     
		     wire [0:num_vcs-1]   elig_ovc;
		     c_select_1ofn
		       #(.num_ports(num_ports),
			 .width(num_vcs))
		     elig_ovc_sel
		       (.select(route_op),
			.data_in(elig_op_ovc),
			.data_out(elig_ovc));
		     
		     wire [0:num_vcs_per_class-1] elig_orc_ocvc;
		     assign elig_orc_ocvc = elig_ovc[mc*num_vcs_per_class:
						     (mc+1)*num_vcs_per_class-1];
		     
		     wire 			     req;
		     assign req = req_irc_icvc[icvc];
		     
		     wire [0:num_ports*num_vcs_per_class-1] gnt_out_op_orc_ocvc;
		     assign gnt_out_op_orc_ocvc
		       = gnt_out_ip_irc_icvc_op_orc_ocvc
			 [(ip*num_vcs_per_class+icvc)*
			  num_ports*num_vcs_per_class:
			  (ip*num_vcs_per_class+icvc+1)*
			  num_ports*num_vcs_per_class-1];
		     
		     // NOTE: Logically, what we want to do here is select 
		     // the subvector that corresponds to the current input
		     // VC's selected output port; however, because the 
		     // subvectors for all other ports will never have any 
		     // grants anyway, we can just OR all the subvectors
		     // instead of using a proper MUX.
		     wire [0:num_vcs_per_class-1] gnt_out_orc_ocvc;
		     c_binary_op
		       #(.num_ports(num_ports),
			 .width(num_vcs_per_class),
			 .op(`BINARY_OP_OR))
		     gnt_out_orc_ocvc_or
		       (.data_in(gnt_out_op_orc_ocvc),
			.data_out(gnt_out_orc_ocvc));
		     
		     wire [0:num_vcs_per_class-1] req_unqual_orc_ocvc;
		     wire [0:num_vcs_per_class-1] gnt_in_orc_ocvc;
		     
		     wire [0:num_vcs_per_class-1] req_unqual_ocvc;
		     wire [0:num_vcs_per_class-1] gnt_in_ocvc;
		     
		     wire [0:num_vcs_per_class-1] elig_ocvc;
		     assign elig_ocvc
		       = elig_orc_ocvc[0:num_vcs_per_class-1];
		     
		     wire 			    route;
		     assign route = route_orc;
		     
		     // Perform input-side arbitration regardless
		     // of whether there was a request; instead, 
		     // requests are subsequently only propagated
		     // to the output stage if there was a 
		     // requests.
		     
		     assign req_unqual_ocvc
		       = {num_vcs_per_class{route}};
		     
		     wire [0:num_vcs_per_class-1] req_in_ocvc;
		     assign req_in_ocvc = req_unqual_ocvc & elig_ocvc;
		     
 		     wire [0:num_vcs_per_class-1] gnt_out_ocvc;
		     assign gnt_out_ocvc
		       = gnt_out_orc_ocvc[0:num_vcs_per_class-1];
		     
		     wire 			    update_arb;
		     assign update_arb = |gnt_out_ocvc;
		     
		     c_arbiter
		       #(.num_ports(num_vcs_per_class),
			 .arbiter_type(arbiter_type),
			 .reset_type(reset_type))
		     gnt_in_ocvc_arb
		       (.clk(clk),
			.reset(reset),
			.active(active),
			.update(update_arb),
			.req(req_in_ocvc),
			.gnt(gnt_in_ocvc));
		     
		     assign req_unqual_orc_ocvc = req_unqual_ocvc;
		     
		     assign gnt_in_orc_ocvc = gnt_in_ocvc;

		     //----------------------------------------------------
		     // generate requests for output stage
		     //----------------------------------------------------
		     
		     wire [0:num_ports*num_vcs_per_class-1] active_op_orc_ocvc;
		     
		     wire [0:num_ports*
			   num_vcs_per_class-1] req_out_op_orc_ocvc;
		     
		     genvar 		     op;
		     
		     for(op = 0; op < num_ports; op = op + 1)
		       begin:ops
			  
			  wire route;
			  assign route = route_op[op];
			  
			  wire [0:num_vcs_per_class-1] active_orc_ocvc;
			  assign active_orc_ocvc
			    = {(num_vcs_per_class)
			       {req & route}} & req_unqual_orc_ocvc;
			  
			  assign active_op_orc_ocvc
			    [op*num_vcs_per_class:
			     (op+1)*
			     num_vcs_per_class-1]
			    = active_orc_ocvc;
			  
			  wire [0:num_vcs-1] 	  active_ovc;
			  c_align
			    #(.in_width(num_vcs_per_class),
			      .out_width(num_vcs),
			      .offset(mc*num_vcs_per_class))
			  active_ovc_agn
			    (.data_in(active_orc_ocvc),
			     .dest_in({num_vcs{1'b0}}),
			     .data_out(active_ovc));
			  
			  assign req_out_op_orc_ocvc
			    [op*num_vcs_per_class:
			     (op+1)*num_vcs_per_class-1]
			    = {(num_vcs_per_class){req & route}} & 
			      gnt_in_orc_ocvc;
			  
		       end
		     
		     assign active_ip_irc_icvc_op_orc_ocvc
		       [((ip)*
			 num_vcs_per_class+icvc)*
			num_ports*num_vcs_per_class:
			((ip)*
			 num_vcs_per_class+icvc+1)*
			num_ports*num_vcs_per_class-1]
			 = active_op_orc_ocvc;
		     
		     assign req_out_ip_irc_icvc_op_orc_ocvc
		       [((ip)*
			 num_vcs_per_class+icvc)*
			num_ports*num_vcs_per_class:
			((ip)*
			 num_vcs_per_class+icvc+1)*
			num_ports*num_vcs_per_class-1]
		       = req_out_op_orc_ocvc;
		     
		     
		     //----------------------------------------------------
		     // generate global grants
		     //----------------------------------------------------
		     
		     c_binary_op
		       #(.num_ports(1),
			 .width(num_vcs_per_class),
			 .op(`BINARY_OP_OR))
		     gnt_out_ocvc_or
		       (.data_in(gnt_out_orc_ocvc),
			.data_out(gnt_out_ocvc));
		     
		     assign gnt_ip_ivc_ocvc[(((ip*num_message_classes+mc))*
					     num_vcs_per_class+icvc)*
					    num_vcs_per_class:
					    (((ip*num_message_classes+mc))*
					     num_vcs_per_class+icvc+1)*
					    num_vcs_per_class-1]
		       = gnt_out_ocvc;
		     
		     assign gnt_ip_ivc[((ip*num_message_classes+mc))*
				       num_vcs_per_class+icvc]
		       = |gnt_out_ocvc;
		     
		  end
		
	     end

	   
	   wire [0:num_ports*num_vcs_per_class-1] active_op_orc_ocvc;
	   c_binary_op
	     #(.width(num_ports*num_vcs_per_class),
	       .num_ports(num_ports*num_vcs_per_class),
	       .op(`BINARY_OP_OR))
	   active_op_orc_ocvc_or
	     (.data_in(active_ip_irc_icvc_op_orc_ocvc),
	      .data_out(active_op_orc_ocvc));
	   
	   
	   //-------------------------------------------------------------------
	   // bit shuffling for changing sort order
	   //-------------------------------------------------------------------
	   wire [0:num_ports*num_vcs_per_class*num_ports*
		 num_vcs_per_class-1] req_out_op_orc_ocvc_ip_irc_icvc;
	   wire [0:num_ports*num_vcs_per_class*num_ports*
		 num_vcs_per_class-1] gnt_out_op_orc_ocvc_ip_irc_icvc;
	   if(mc==3)
	     begin
		wire [0:num_ports*num_vcs_per_class*num_ports*
		      num_vcs_per_class-1] req_out_ip_irc_icvc_op_orc_ocvc_class_one;
		wire [0:num_ports*num_vcs_per_class*num_ports*
		      num_vcs_per_class-1] req_out_ip_irc_icvc_op_orc_ocvc_class_three;
		c_gate_bits
		  #(.num_ports		(num_ports),
		    .width		(num_ports),
		    .op			(`BINARY_OP_AND))
		class_one_req
		  (// Outputs
		   .data_out		(req_out_ip_irc_icvc_op_orc_ocvc_class_one),
		   // Inputs
		   .select		(expired),
		   .data_in		(req_out_ip_irc_icvc_op_orc_ocvc));
		c_gate_bits
		  #(.num_ports		(num_ports),
		    .width		(num_ports),
		    .op			(`BINARY_OP_AND))
		class_three_req
		  (// Outputs
		   .data_out		(req_out_ip_irc_icvc_op_orc_ocvc_class_three),
		   // Inputs
		   .select		(~expired),
		   .data_in		(req_out_ip_irc_icvc_op_orc_ocvc));
		
		
		c_interleave
		  #(.width(num_ports*num_vcs_per_class*
			   num_ports*num_vcs_per_class),
		    .num_blocks(num_ports*num_vcs_per_class))
		req_out_op_orc_ocvc_ip_irc_icvc_intl
		  (.data_in(req_out_ip_irc_icvc_op_orc_ocvc_class_three),
		   .data_out(req_out_op_orc_ocvc_ip_irc_icvc));
		c_interleave
		  #(.width(num_ports*num_vcs_per_class*
			   num_ports*num_vcs_per_class),
		    .num_blocks(num_ports*num_vcs_per_class))
		req_out_op_orc_ocvc_ip_irc_icvc_intl_class_one
		  (.data_in(req_out_ip_irc_icvc_op_orc_ocvc_class_one),
		   .data_out(req_to_class_one));

		
		c_interleave
		  #(.width(num_ports*num_vcs_per_class*
			   num_ports*num_vcs_per_class),
		    .num_blocks(num_ports*num_vcs_per_class))
		gnt_out_op_orc_ocvc_ip_irc_iocvc_intl
		  (.data_in((gnt_out_op_orc_ocvc_ip_irc_icvc|gnt_to_class_three)),
		   .data_out(gnt_out_ip_irc_icvc_op_orc_ocvc));
	     end // if (mc==3)
	   else
	     begin
		c_interleave
		  #(.width(num_ports*num_vcs_per_class*
			   num_ports*num_vcs_per_class),
		    .num_blocks(num_ports*num_vcs_per_class))
		req_out_op_orc_ocvc_ip_irc_icvc_intl
		  (.data_in(req_out_ip_irc_icvc_op_orc_ocvc),
		   .data_out(req_out_op_orc_ocvc_ip_irc_icvc));
		
		c_interleave
		  #(.width(num_ports*num_vcs_per_class*
			   num_ports*num_vcs_per_class),
		    .num_blocks(num_ports*num_vcs_per_class))
		gnt_out_op_orc_ocvc_ip_irc_iocvc_intl
		  (.data_in(gnt_out_op_orc_ocvc_ip_irc_icvc),
		   .data_out(gnt_out_ip_irc_icvc_op_orc_ocvc));
	     end // else: !if(mc==3)
	   
	   
	   

	   
	   
	   
	   //
	   //Extra global wires for interaction of class 1 and class 3
	   //  -class 3 requests goes to class 1 or 3 depending on expired
	   //
	   //  -class 3 input arbiter update is triggered by class 1 or 3 output arbs
	   //     -if |class1gnt & expired | class3gnt
	   
	   
	   if(mc==1)
	     begin
		//-------------------------------------------------------------------
		// output stage
		//-------------------------------------------------------------------
		genvar 		      op;
		for (op = 0; op < num_ports; op = op + 1)
		  begin:ops
		     genvar ocvc;
		     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
		       begin:ocvcs
			  //----------------------------------------------------
			  // output-side arbitration (select input port and VC)
			  //----------------------------------------------------
			  
			  wire elig;
			  assign elig = elig_op_ovc[((op*num_message_classes+
						      mc))*
						    num_vcs_per_class+ocvc];
			  
			  wire active;
			  assign active
			    = active_op_orc_ocvc[op*num_vcs_per_class+
						 ocvc];
			  wire [0:num_ports*num_vcs_per_class*2-1] req_out_ip_irc_icvc;
			  wire [0:num_ports*num_vcs_per_class-1] req_from_class_one=
								 req_out_op_orc_ocvc_ip_irc_icvc[(op*num_vcs_per_class+ocvc)*num_ports*num_vcs_per_class:
												 (op*num_vcs_per_class+ocvc+1)*num_ports*num_vcs_per_class-1];
			  wire [0:num_ports*num_vcs_per_class-1] req_to_class_one_out_ip = 
								 req_to_class_one[(op*num_vcs_per_class+ocvc)*num_ports*num_vcs_per_class:
										  (op*num_vcs_per_class+ocvc+1)*num_ports*num_vcs_per_class-1];
			  
			  
			  c_interleave
			    #(.width(num_ports*num_vcs_per_class*2),
			      .num_blocks(2))
			  req_out_ip_irc_icvc_intl
			    (.data_in({req_from_class_one,req_to_class_one_out_ip}),
			     .data_out(req_out_ip_irc_icvc));
			  
			  
			  wire [0:num_ports-1] 	     req_out_ip;
			  c_mat_mult
			    #(.dim1_width(num_ports),
			      .dim2_width(num_vcs_per_class*2),
			      .dim3_width(1),
			      .prod_op(`BINARY_OP_AND),
			      .sum_op(`BINARY_OP_OR))
			  req_out_ip_mmult
			    (.input_a(req_out_ip_irc_icvc),
			     .input_b({(num_vcs_per_class*2){1'b1}}),
			     .result(req_out_ip));
			  
			  wire [0:num_ports-1] 	     gnt_out_ip;
			  wire [0:num_ports*num_vcs_per_class-1] gnt_out_ip_irc_icvc;
			  wire [0:num_ports*num_vcs_per_class-1] gnt_out_ip_irc_icvc_three;
			  
			  wire [0:num_ports*num_vcs-1] gnt_ip_ivc;//
			  
			  
			  //----------------------------------------------------
			  // arbitrate between different VCs on each input port
			  //----------------------------------------------------
			  
			  genvar 		       ip;
			  
			  for(ip = 0; ip < num_ports; ip = ip + 1)
			    begin:ips
			       
			       wire [0:num_vcs_per_class*2-1] req_out_irc_icvc;
			       assign req_out_irc_icvc[0]
				 = req_from_class_one[ip+:1];
			       assign req_out_irc_icvc[1]
				 = req_to_class_one[ip+:1];
			       
			       wire 			  update_arb;
			       assign update_arb = gnt_out_ip[ip];
			       
			       wire [0:num_vcs_per_class*2-1] gnt_out_irc_icvc;
			       c_arbiter
				 #(.num_ports(num_vcs_per_class*2),
				   .arbiter_type(arbiter_type),
				   .reset_type(reset_type))
			       gnt_our_irc_icvc_arb
				 (.clk(clk),
				  .reset(reset),
				  .active(active),
				  .update(update_arb),
				  .req(req_out_irc_icvc),
				  .gnt(gnt_out_irc_icvc));

			       //assuming 1vc/class
			       assign gnt_out_ip_irc_icvc[ip*num_vcs_per_class:
							  (ip+1)*num_vcs_per_class-1]
				 = gnt_out_irc_icvc[0] & 
				   gnt_out_ip[ip];
			       assign gnt_out_ip_irc_icvc_three[ip*num_vcs_per_class:
								(ip+1)*num_vcs_per_class-1]
				 = gnt_out_irc_icvc[1] & 
				   gnt_out_ip[ip];
			       
			       //wire [0:num_vcs-1] 	  gnt_out_ivc;
			       wire [0:num_vcs-1] gnt_out_ivc_one;
			       wire [0:num_vcs-1] gnt_out_ivc_three;
			       
			       c_align
				 #(.in_width(num_vcs_per_class),
				   .out_width(num_vcs),
				   .offset(mc*num_vcs_per_class))
			       gnt_out_ivc_alg_one
				 (.data_in(gnt_out_irc_icvc[0]),
				  .dest_in({num_vcs{1'b0}}),
				  .data_out(gnt_out_ivc_one));
			       c_align
				 #(.in_width(num_vcs_per_class),
				   .out_width(num_vcs),
				   .offset(3*num_vcs_per_class))
			       gnt_out_ivc_alg_three
				 (.data_in(gnt_out_irc_icvc[1]),
				  .dest_in({num_vcs{1'b0}}),
				  .data_out(gnt_out_ivc_three));
			       
			       assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
				 = gnt_out_ivc_one|gnt_out_ivc_three;
			       //gnt_out_ivc;
			    end
			  
			  wire [0:num_vcs-1] 		  gnt_ivc;
			  c_select_mofn
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_ivc_sel
			    (.select(gnt_out_ip),
			     .data_in(gnt_ip_ivc),
			     .data_out(gnt_ivc));
			  
			  wire 				  req_out;
			  assign req_out = |req_out_ip;
			  
			  wire 				  update_arb;
			  assign update_arb = req_out;
			  
			  c_arbiter
			    #(.num_ports(num_ports),
			      .arbiter_type(arbiter_type),
			      .reset_type(reset_type))
			  gnt_out_ip_arb
			    (.clk(clk),
			     .reset(reset),
			     .active(active),
			     .update(update_arb),
			     .req(req_out_ip),
			     .gnt(gnt_out_ip));
			  
			  assign gnt_out_op_orc_ocvc_ip_irc_icvc
			    [(op*num_vcs_per_class+ocvc)*
			     num_ports*num_vcs_per_class:
			     (op*num_vcs_per_class+ocvc+1)*
			     num_ports*num_vcs_per_class-1]
			    = gnt_out_ip_irc_icvc; 
			  assign gnt_to_class_three
			    [(op*num_vcs_per_class+ocvc)*
			     num_ports*num_vcs_per_class:
			     (op*num_vcs_per_class+ocvc+1)*
			     num_ports*num_vcs_per_class-1]
			    = gnt_out_ip_irc_icvc_three; 
			  
			  //----------------------------------------------------
			  // generate control signals to output controller
			  //----------------------------------------------------
			  
			  assign gnt_op_ovc[(op*num_message_classes+mc)*
					    num_vcs_per_class+ocvc]
			    = req_out;
			  
			  assign gnt_op_ovc_ip[((op*num_message_classes+mc)*
						num_vcs_per_class+ocvc)*
					       num_ports:
					       ((op*num_message_classes+mc)*
						num_vcs_per_class+ocvc+1)*
					       num_ports-1]
			    = gnt_out_ip;
			  
			  assign gnt_op_ovc_ivc[((op*num_message_classes+mc)*
						 num_vcs_per_class+ocvc)*
						num_vcs:
						(((op*num_message_classes+mc))*
						 num_vcs_per_class+ocvc+1)*
						num_vcs-1]
			    = gnt_ivc;
			  
		       end // block: ocvcs
		  end // block: ops
	     end // if (mc==1)
	   else
	     begin
		//-------------------------------------------------------------------
		// output stage
		//-------------------------------------------------------------------
		genvar 		      op;
		for (op = 0; op < num_ports; op = op + 1)
		  begin:ops
		     genvar ocvc;
		     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
		       begin:ocvcs
			  //----------------------------------------------------
			  // output-side arbitration (select input port and VC)
			  //----------------------------------------------------
			  
			  wire elig;
			  assign elig = elig_op_ovc[((op*num_message_classes+
						      mc))*
						    num_vcs_per_class+ocvc];
			  
			  wire active;
			  assign active
			    = active_op_orc_ocvc[op*num_vcs_per_class+
						 ocvc];
			  
			  wire [0:num_ports*num_vcs_per_class-1] req_out_ip_irc_icvc;
			  assign req_out_ip_irc_icvc
			    = req_out_op_orc_ocvc_ip_irc_icvc
			      [(op*
				num_vcs_per_class+ocvc)*
			       num_ports*num_vcs_per_class:
			       (op*num_vcs_per_class+ocvc+1)*
			       num_ports*num_vcs_per_class-1];
			  
			  wire [0:num_ports-1] 	     req_out_ip;
			  c_mat_mult
			    #(.dim1_width(num_ports),
			      .dim2_width(num_vcs_per_class),
			      .dim3_width(1),
			      .prod_op(`BINARY_OP_AND),
			      .sum_op(`BINARY_OP_OR))
			  req_out_ip_mmult
			    (.input_a(req_out_ip_irc_icvc),
			     .input_b({(num_vcs_per_class){1'b1}}),
			     .result(req_out_ip));
			  
			  wire [0:num_ports-1] 	     gnt_out_ip;
			  wire [0:num_ports*num_vcs_per_class-1] gnt_out_ip_irc_icvc;
			  
			  wire [0:num_ports*num_vcs-1] gnt_ip_ivc;
			  
			  
			  //----------------------------------------------------
			  // arbitrate between different VCs on each input port
			  //----------------------------------------------------
			  
			  genvar 		       ip;
			  
			  for(ip = 0; ip < num_ports; ip = ip + 1)
			    begin:ips
			       
			       wire [0:num_vcs_per_class-1] req_out_irc_icvc;
			       assign req_out_irc_icvc
				 = req_out_ip_irc_icvc[ip*num_vcs_per_class:
						       (ip+1)*num_vcs_per_class-1];
			       
			       wire 			  update_arb;
			       assign update_arb = gnt_out_ip[ip];
			       
			       wire [0:num_vcs_per_class-1] gnt_out_irc_icvc;
			       c_arbiter
				 #(.num_ports(num_vcs_per_class),
				   .arbiter_type(arbiter_type),
				   .reset_type(reset_type))
			       gnt_our_irc_icvc_arb
				 (.clk(clk),
				  .reset(reset),
				  .active(active),
				  .update(update_arb),
				  .req(req_out_irc_icvc),
				  .gnt(gnt_out_irc_icvc));
			       
			       assign gnt_out_ip_irc_icvc[ip*num_vcs_per_class:
							  (ip+1)*num_vcs_per_class-1]
				 = gnt_out_irc_icvc & 
				   {(num_vcs_per_class){gnt_out_ip[ip]}};
			       
			       wire [0:num_vcs-1] 	  gnt_out_ivc;
			       c_align
				 #(.in_width(num_vcs_per_class),
				   .out_width(num_vcs),
				   .offset(mc*num_vcs_per_class))
			       gnt_out_ivc_alg
				 (.data_in(gnt_out_irc_icvc),
				  .dest_in({num_vcs{1'b0}}),
				  .data_out(gnt_out_ivc));
			       
			       assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
				 = gnt_out_ivc;
			       
			    end
			  
			  wire [0:num_vcs-1] 		  gnt_ivc;
			  c_select_mofn
			    #(.num_ports(num_ports),
			      .width(num_vcs))
			  gnt_ivc_sel
			    (.select(gnt_out_ip),
			     .data_in(gnt_ip_ivc),
			     .data_out(gnt_ivc));
			  
			  wire 				  req_out;
			  assign req_out = |req_out_ip;
			  
			  wire 				  update_arb;
			  assign update_arb = req_out;
			  
			  c_arbiter
			    #(.num_ports(num_ports),
			      .arbiter_type(arbiter_type),
			      .reset_type(reset_type))
			  gnt_out_ip_arb
			    (.clk(clk),
			     .reset(reset),
			     .active(active),
			     .update(update_arb),
			     .req(req_out_ip),
			     .gnt(gnt_out_ip));
			  
			  assign gnt_out_op_orc_ocvc_ip_irc_icvc
			    [(op*num_vcs_per_class+ocvc)*
			     num_ports*num_vcs_per_class:
			     (op*num_vcs_per_class+ocvc+1)*
			     num_ports*num_vcs_per_class-1]
			    = gnt_out_ip_irc_icvc;
			  
			  
			  //----------------------------------------------------
			  // generate control signals to output controller
			  //----------------------------------------------------
			  
			  assign gnt_op_ovc[(op*num_message_classes+mc)*
					    num_vcs_per_class+ocvc]
			    = req_out;
			  
			  assign gnt_op_ovc_ip[((op*num_message_classes+mc)*
						num_vcs_per_class+ocvc)*
					       num_ports:
					       ((op*num_message_classes+mc)*
						num_vcs_per_class+ocvc+1)*
					       num_ports-1]
			    = gnt_out_ip;
			  
			  assign gnt_op_ovc_ivc[((op*num_message_classes+mc)*
						 num_vcs_per_class+ocvc)*
						num_vcs:
						(((op*num_message_classes+mc))*
						 num_vcs_per_class+ocvc+1)*
						num_vcs-1]
			    = gnt_ivc;
			  
		       end // block: ocvcs
		  end // block: ops
	     end // else: !if(mc==1)
	end // block: mcs
      
      
      
   endgenerate
   
endmodule
