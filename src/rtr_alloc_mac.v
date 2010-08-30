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
// VC and switch allocator module
//==============================================================================

module rtr_alloc_mac
  (clk, reset, route_valid_in_ip_ivc, route_in_ip_ivc_op, route_in_ip_ivc_orc, 
   flit_valid_in_ip_ivc, flit_last_in_ip_ivc, flit_head_in_ip_ivc, 
   flit_tail_in_ip_ivc, route_fast_in_ip_op, route_fast_in_ip_orc, 
   flit_valid_fast_in_ip, flit_head_fast_in_ip, flit_tail_fast_in_ip, 
   flit_sel_fast_in_ip_ivc, flit_sel_out_ip_ivc, flit_sel_fast_out_ip, 
   flit_sent_out_ip, flit_sel_out_op_ip, empty_out_op, flit_valid_out_op, 
   flit_head_out_op, flit_tail_out_op, flit_sel_out_op_ovc, 
   fc_event_valid_in_op, fc_event_sel_in_op_ovc, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // precompute input-side arbitration decision one cycle ahead
   parameter precomp_ivc_sel = 1;
   
   // select which arbiter type to use for switch allocation
   parameter sw_alloc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select which arbiter type to use for VC allocation
   parameter vc_alloc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // enable dual-path allocation
   parameter dual_path_alloc = 1;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = ((connectivity == `CONNECTIVITY_LINE) ||
	(connectivity == `CONNECTIVITY_RING)) ?
       2 :
       (connectivity == `CONNECTIVITY_FULL) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // required address width for tail FIFO
   localparam tff_addr_width = clogb(num_flits_per_vc);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // routing information valid
   input [0:num_ports*num_vcs-1] route_valid_in_ip_ivc;
   
   // output port select signals for each input port and VC
   input [0:num_ports*num_vcs*num_ports-1] route_in_ip_ivc_op;
   
   // output resource class select signals for each input port and VC
   input [0:num_ports*num_vcs*num_resource_classes-1] route_in_ip_ivc_orc;
   
   // incoming flit control signals
   input [0:num_ports*num_vcs-1] 		      flit_valid_in_ip_ivc;
   input [0:num_ports*num_vcs-1] 		      flit_last_in_ip_ivc;
   input [0:num_ports*num_vcs-1] 		      flit_head_in_ip_ivc;
   input [0:num_ports*num_vcs-1] 		      flit_tail_in_ip_ivc;
   
   // 
   input [0:num_ports*num_ports-1] 		      route_fast_in_ip_op;
   
   // 
   input [0:num_ports*num_resource_classes-1] 	      route_fast_in_ip_orc;
   
   // 
   input [0:num_ports-1] 			      flit_valid_fast_in_ip;
   input [0:num_ports-1] 			      flit_head_fast_in_ip;
   input [0:num_ports-1] 			      flit_tail_fast_in_ip;
   input [0:num_ports*num_vcs-1] 		      flit_sel_fast_in_ip_ivc;
   
   // indicate which input VC is candidate for being sent
   output [0:num_ports*num_vcs-1] 		      flit_sel_out_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		      flit_sel_out_ip_ivc;
   
   //
   output [0:num_ports-1] 			      flit_sel_fast_out_ip;
   wire [0:num_ports-1] 			      flit_sel_fast_out_ip;
   
   // grants to input controllers
   output [0:num_ports-1] 			      flit_sent_out_ip;
   wire [0:num_ports-1] 			      flit_sent_out_ip;
   
   // input-to-output port assignments for crossbar
   output [0:num_ports*num_ports-1] 		      flit_sel_out_op_ip;
   wire [0:num_ports*num_ports-1] 		      flit_sel_out_op_ip;
   
   // all VCs at given port empty?
   output [0:num_ports-1] 			      empty_out_op;
   wire [0:num_ports-1] 			      empty_out_op;
   
   // outgoing flit control signals
   output [0:num_ports-1] 			      flit_valid_out_op;
   wire [0:num_ports-1] 			      flit_valid_out_op;
   output [0:num_ports-1] 			      flit_head_out_op;
   wire [0:num_ports-1] 			      flit_head_out_op;
   output [0:num_ports-1] 			      flit_tail_out_op;
   wire [0:num_ports-1] 			      flit_tail_out_op;
   
   // indicate which output VC the transmitted flit belongs to
   output [0:num_ports*num_vcs-1] 		      flit_sel_out_op_ovc;
   wire [0:num_ports*num_vcs-1] 		      flit_sel_out_op_ovc;
   
   // flow control event occurred
   input [0:num_ports-1] 			      fc_event_valid_in_op;
   
   // output VC to which flow control event belongs
   input [0:num_ports*num_vcs-1] 		      fc_event_sel_in_op_ovc;
   
   // internal error condition detected
   output 					      error;
   wire 					      error;
   
   
   //---------------------------------------------------------------------------
   // input side
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 		      ovs_almost_full_op_ovc;
   wire [0:num_ports*num_vcs-1] 		      ovs_full_op_ovc;
   
   wire [0:num_ports*num_vcs-1] 		      nvs_next_elig_op_ovc;
   
   wire [0:num_ports*num_ports-1] 		      active_ip_op;
   
   wire [0:num_ports*num_ports-1] 		      ial_flit_valid_ip_op;
   wire [0:num_ports-1] 			      ial_flit_head_ip;
   wire [0:num_ports-1] 			      ial_flit_tail_ip;
   wire [0:num_ports*num_vcs-1] 		      ial_flit_sel_ip_ovc;
   
   wire [0:num_ports*num_ports-1] 		      oal_flit_sent_ip_op;
   
   generate
      
      //------------------------------------------------------------------------
      // input ports
      //------------------------------------------------------------------------
      
      genvar 					      ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] flit_valid_in_ivc;
	   assign flit_valid_in_ivc
	     = flit_valid_in_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] flit_last_in_ivc;
	   assign flit_last_in_ivc
	     = flit_last_in_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] flit_head_in_ivc;
	   assign flit_head_in_ivc
	     = flit_head_in_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] flit_tail_in_ivc;
	   assign flit_tail_in_ivc
	     = flit_tail_in_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_ports-1] oal_flit_sent_op;
	   assign oal_flit_sent_op
	     = oal_flit_sent_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_ports-1] route_fast_in_op;
	   assign route_fast_in_op
	     = route_fast_in_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_resource_classes-1] route_fast_in_orc;
	   assign route_fast_in_orc
	     = route_fast_in_ip_orc[ip*num_resource_classes:
				    (ip+1)*num_resource_classes-1];
	   
	   wire 			   flit_valid_fast_in;
	   assign flit_valid_fast_in = flit_valid_fast_in_ip[ip];
	   
	   wire 			   flit_head_fast_in;
	   assign flit_head_fast_in = flit_head_fast_in_ip[ip];
	   
	   wire 			   flit_tail_fast_in;
	   assign flit_tail_fast_in = flit_tail_fast_in_ip[ip];
	   
	   wire [0:num_vcs-1] 		   flit_sel_fast_in_ivc;
	   assign flit_sel_fast_in_ivc
	     = flit_sel_fast_in_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	   active_op;
	   assign active_ip_op[ip*num_ports:(ip+1)*num_ports-1] = active_op;
	   
	   wire [0:num_ports-1] 	   ial_flit_valid_op;
	   assign ial_flit_valid_ip_op[ip*num_ports:(ip+1)*num_ports-1]
	     = ial_flit_valid_op;
	   
	   wire 			   ial_flit_head;
	   assign ial_flit_head_ip[ip] = ial_flit_head;
	   
	   wire 			   ial_flit_tail;
	   assign ial_flit_tail_ip[ip] = ial_flit_tail;
	   
	   wire [0:num_vcs-1] 		   ial_flit_sel_ovc;
	   assign ial_flit_sel_ip_ovc[ip*num_vcs:(ip+1)*num_vcs-1]
	     = ial_flit_sel_ovc;
	   
	   wire 			   flit_sel_fast_out;
	   assign flit_sel_fast_out_ip[ip] = flit_sel_fast_out;
	   
	   wire 			   flit_sent_out;
	   assign flit_sent_out_ip[ip] = flit_sent_out;
	   
	   wire [0:num_vcs-1] 		   flit_sel_out_ivc;
	   assign flit_sel_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
	     = flit_sel_out_ivc;
	   
	   
	   //-------------------------------------------------------------------
	   // fast-path logic
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 		   flit_valid_fast_in_ivc;
	   assign flit_valid_fast_in_ivc
	     = {num_vcs{flit_valid_fast_in}} & flit_sel_fast_in_ivc;
	   
	   wire 			   oal_flit_sent;
	   assign oal_flit_sent = |oal_flit_sent_op;
	   
	   wire [0:num_vcs*num_ports-1]    rf_route_ivc_op;
	   
	   wire [0:num_vcs*num_vcs-1] 	   ivs_flit_sel_ivc_ovc;
	   wire [0:num_vcs-1] 		   ivs_cred_ivc;
	   
	   wire [0:num_vcs_per_class-1]    ifl_next_elig_ocvc;
	   wire [0:num_vcs_per_class-1]    ifl_almost_full_ocvc;
	   wire [0:num_vcs_per_class-1]    ifl_full_ocvc;
	   wire [0:num_ports-1] 	   ifl_flit_valid_op;
	   wire [0:num_vcs-1] 		   ifl_flit_sel_ovc;
	   wire 			   ifl_flit_kill;
	   
	   begin:ifl
	      
	      if(dual_path_alloc)
		begin
		   
		   wire [0:num_message_classes-1] sel_mc;
		   c_mat_mult
		     #(.dim1_width(num_message_classes),
		       .dim2_width(num_resource_classes*num_vcs_per_class),
		       .dim3_width(1),
		       .prod_op(`BINARY_OP_AND),
		       .sum_op(`BINARY_OP_OR))
		   sel_mc_mmult
		     (.input_a(flit_sel_fast_in_ivc),
		      .input_b({(num_resource_classes*
				 num_vcs_per_class){1'b1}}),
		      .result(sel_mc));
		   
		   wire [0:num_vcs_per_class-1] next_elig_ocvc;
		   rtr_vc_flags_mux
		     #(.num_message_classes(num_message_classes),
		       .num_resource_classes(num_resource_classes),
		       .num_vcs_per_class(num_vcs_per_class),
		       .num_ports(num_ports))
		   next_elig_ocvc_fmux
		     (.sel_mc(sel_mc),
		      .route_op(route_fast_in_op),
		      .route_orc(route_fast_in_orc),
		      .flags_op_ovc(nvs_next_elig_op_ovc),
		      .flags_ocvc(next_elig_ocvc));
		   
		   wire [0:num_vcs_per_class-1] almost_full_ocvc;
		   rtr_vc_flags_mux
		     #(.num_message_classes(num_message_classes),
		       .num_resource_classes(num_resource_classes),
		       .num_vcs_per_class(num_vcs_per_class),
		       .num_ports(num_ports))
		   almost_full_ocvc_fmux
		     (.sel_mc(sel_mc),
		      .route_op(route_fast_in_op),
		      .route_orc(route_fast_in_orc),
		      .flags_op_ovc(ovs_almost_full_op_ovc),
		      .flags_ocvc(almost_full_ocvc));
		   
		   wire [0:num_vcs_per_class-1] full_ocvc;
		   rtr_vc_flags_mux
		     #(.num_message_classes(num_message_classes),
		       .num_resource_classes(num_resource_classes),
		       .num_vcs_per_class(num_vcs_per_class),
		       .num_ports(num_ports))
		   full_ocvc_fmux
		     (.sel_mc(sel_mc),
		      .route_op(route_fast_in_op),
		      .route_orc(route_fast_in_orc),
		      .flags_op_ovc(ovs_full_op_ovc),
		      .flags_ocvc(full_ocvc));
		   
		   wire [0:num_resource_classes*
			 num_vcs_per_class-1] 	flit_sel_orc_ocvc;
		   c_mat_mult
		     #(.dim1_width(num_resource_classes),
		       .dim2_width(1),
		       .dim3_width(num_vcs_per_class),
		       .prod_op(`BINARY_OP_AND),
		       .sum_op(`BINARY_OP_OR))
		   flit_sel_orc_ocvc_mmult
		     (.input_a(route_fast_in_orc),
		      .input_b({num_vcs_per_class{1'b1}}),
		      .result(flit_sel_orc_ocvc));
		   
		   wire [0:num_vcs-1] 		flit_sel_ovc;
		   c_mat_mult
		     #(.dim1_width(num_message_classes),
		       .dim2_width(1),
		       .dim3_width(num_resource_classes*num_vcs_per_class),
		       .prod_op(`BINARY_OP_AND),
		       .sum_op(`BINARY_OP_OR))
		   flit_sel_ovc_mmult
		     (.input_a(sel_mc),
		      .input_b(flit_sel_orc_ocvc),
		      .result(flit_sel_ovc));
		   
		   wire [0:num_vcs-1] 		ivs_flit_sel_ovc;
		   
		   if(num_vcs == 1)
		     assign ivs_flit_sel_ovc = ivs_flit_sel_ivc_ovc;
		   else if(num_vcs > 1)
		     begin
			c_select_1ofn
			  #(.num_ports(num_vcs),
			    .width(num_vcs))
			ivs_flit_sel_ovc_sel
			  (.select(flit_sel_fast_in_ivc),
			   .data_in(ivs_flit_sel_ivc_ovc),
			   .data_out(ivs_flit_sel_ovc));
		     end
		   
		   wire [0:num_vcs-1] flit_sel_ivc;
		   assign flit_sel_ivc = flit_sel_fast_in_ivc & ivs_cred_ivc;
		   
		   wire [0:num_ports-1] rf_route_op;
		   c_select_mofn
		     #(.num_ports(num_vcs),
		       .width(num_ports))
		   rf_route_op_sel
		     (.select(flit_sel_ivc),
		      .data_in(rf_route_ivc_op),
		      .data_out(rf_route_op));
		   
		   assign ifl_next_elig_ocvc = next_elig_ocvc;
		   assign ifl_almost_full_ocvc = almost_full_ocvc;
		   assign ifl_full_ocvc = full_ocvc;
		   assign ifl_flit_valid_op
		     = (flit_head_fast_in ? route_fast_in_op : rf_route_op) & 
		       {num_ports{flit_valid_fast_in}};
		   assign ifl_flit_sel_ovc
		     = flit_head_fast_in ? flit_sel_ovc : ivs_flit_sel_ovc;
		   assign ifl_flit_kill = flit_head_fast_in & ~|next_elig_ocvc;
		   
		end
	      else
		begin
		   assign ifl_next_elig_ocvc = {num_vcs_per_class{1'b0}};
		   assign ifl_almost_full_ocvc = {num_vcs_per_class{1'b0}};
		   assign ifl_full_ocvc = {num_vcs_per_class{1'b0}};
		   assign ifl_flit_valid_op = {num_ports{1'b0}};
		   assign ifl_flit_sel_ovc = {num_vcs{1'b0}};
		   assign ifl_flit_kill = 1'b0;
		end
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // input VCs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] ial_flit_sel_ivc;
	   
	   wire [0:num_vcs*num_resource_classes-1] rf_route_ivc_orc;
	   
	   wire [0:num_vcs-1] 			   ivs_allocated_ivc;
	   wire [0:num_vcs-1] 			   ivs_flit_kill_ivc;
	   
	   genvar 				   ivc;
	   
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------
		
		wire route_valid_in;
		assign route_valid_in = route_valid_in_ip_ivc[ip*num_vcs+ivc];
		
		wire [0:num_ports-1] route_in_op;
		assign route_in_op
		  = route_in_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				       (ip*num_vcs+ivc+1)*num_ports-1];
		
		wire [0:num_resource_classes-1] route_in_orc;
		assign route_in_orc
		  = route_in_ip_ivc_orc[(ip*num_vcs+ivc)*
					num_resource_classes:
					(ip*num_vcs+ivc+1)*
					num_resource_classes-1];
		
		wire 				flit_valid_in;
		assign flit_valid_in = flit_valid_in_ivc[ivc];
		
		wire 				flit_tail_in;
		assign flit_tail_in = flit_tail_in_ivc[ivc];
		
		wire 				flit_valid_fast_in;
		assign flit_valid_fast_in = flit_valid_fast_in_ivc[ivc];
		
		wire 				ial_flit_sel;
		assign ial_flit_sel = ial_flit_sel_ivc[ivc];
		
		
		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 		rf_route_op;
		assign rf_route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		  = rf_route_op;
		
		wire [0:num_resource_classes-1] rf_route_orc;
		assign rf_route_ivc_orc[ivc*num_resource_classes:
					(ivc+1)*num_resource_classes-1]
		  = rf_route_orc;
		
		wire 				ivs_allocated;
		assign ivs_allocated_ivc[ivc] = ivs_allocated;
		
		wire 				ivs_cred;
		assign ivs_cred_ivc[ivc] = ivs_cred;
		
		wire [0:num_vcs-1] 		ivs_flit_sel_ovc;
		assign ivs_flit_sel_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]
		  = ivs_flit_sel_ovc;
		
		wire 				ivs_flit_kill;
		assign ivs_flit_kill_ivc[ivc] = ivs_flit_kill;
		
		
		//--------------------------------------------------------------
		// filter out illegal requests
		//--------------------------------------------------------------
		
		wire [0:1] 			rf_errors;
		rtr_route_filter
		  #(.num_message_classes(num_message_classes),
		    .num_resource_classes(num_resource_classes),
		    .num_vcs_per_class(num_vcs_per_class),
		    .num_ports(num_ports),
		    .num_neighbors_per_dim(num_neighbors_per_dim),
		    .num_nodes_per_router(num_nodes_per_router),
		    .restrict_turns(restrict_turns),
		    .connectivity(connectivity),
		    .routing_type(routing_type),
		    .dim_order(dim_order),
		    .port_id(ip),
		    .vc_id(ivc))
		rf
		  (.route_valid(flit_valid_in),
		   .route_in_op(route_in_op),
		   .route_in_orc(route_in_orc),
		   .route_out_op(rf_route_op),
		   .route_out_orc(rf_route_orc),
		   .errors(rf_errors));
		
		wire 				error_invalid_port;
		assign error_invalid_port =  rf_errors[0];
		
		wire 				error_invalid_class;
		assign error_invalid_class = rf_errors[1];
		
		
		//--------------------------------------------------------------
		// input VC state tracking
		//--------------------------------------------------------------
		
		begin:ivs
		   
		   wire flit_valid;
		   
		   if(dual_path_alloc)
		     assign flit_valid = flit_valid_in | flit_valid_fast_in;
		   else
		     assign flit_valid = flit_valid_in;
		   
		   wire active;
		   assign active = flit_valid;
		   
		   wire [0:num_vcs-1] sel_ivc;
		   assign sel_ivc = (1 << (num_vcs - 1 - ivc));
		   
		   wire [0:num_message_classes-1] sel_mc;
		   c_mat_mult
		     #(.dim1_width(num_message_classes),
		       .dim2_width(num_resource_classes*num_vcs_per_class),
		       .dim3_width(1),
		       .prod_op(`BINARY_OP_AND),
		       .sum_op(`BINARY_OP_OR))
		   sel_mc_mmult
		     (.input_a(sel_ivc),
		      .input_b({(num_resource_classes*
				 num_vcs_per_class){1'b1}}),
		      .result(sel_mc));
		   
		   
		   //-----------------------------------------------------------
		   // keep track of which output VC this input VC has allocated
		   //-----------------------------------------------------------
		   
		   wire 			  flit_sent;
		   assign flit_sent = oal_flit_sent & ial_flit_sel;
		   
		   wire 			  flit_tail;
		   
		   if(dual_path_alloc)
		     assign flit_tail
		       = flit_valid_in ? flit_tail_in : flit_tail_fast_in;
		   else
		     assign flit_tail = flit_tail_in;
		   
		   wire 			  flit_kill;
		   
		   // NOTE: For the reset condition, we don't have to worry 
		   // about 'flit_kill', as it only affects flits that are sent 
		   // before a VC has been allocated -- in which case 
		   // 'allocated_q' is zero, and the reset condition has no 
		   // effect anyway.
		   
		   wire 			  allocated_s, allocated_q;
		   assign allocated_s
		     = (allocated_q | (flit_sent & ~flit_kill)) & 
		       ~(flit_sent & flit_tail);
		   c_dff
		     #(.width(1),
		       .reset_type(reset_type))
		   allocatedq
		     (.clk(clk),
		      .reset(reset),
		      .active(active),
		      .d(allocated_s),
		      .q(allocated_q));
		   
		   wire [0:num_vcs_per_class-1]   nvs_next_elig_ocvc;
		   rtr_vc_flags_mux
		     #(.num_message_classes(num_message_classes),
		       .num_resource_classes(num_resource_classes),
		       .num_vcs_per_class(num_vcs_per_class),
		       .num_ports(num_ports))
		   nvs_next_elig_ocvc_fmux
		     (.sel_mc(sel_mc),
		      .route_op(rf_route_op),
		      .route_orc(rf_route_orc),
		      .flags_op_ovc(nvs_next_elig_op_ovc),
		      .flags_ocvc(nvs_next_elig_ocvc));
		   
		   wire [0:num_vcs_per_class-1]   next_elig_ocvc;
		   
		   if(dual_path_alloc)
		     assign next_elig_ocvc = route_valid_in ? 
					     nvs_next_elig_ocvc : 
					     ifl_next_elig_ocvc;
		   else
		     assign next_elig_ocvc = nvs_next_elig_ocvc;
		
		   assign flit_kill = ~allocated_q & ~|next_elig_ocvc;
		   
		   wire [0:num_vcs_per_class-1]   allocated_next_ocvc;
		   wire [0:num_vcs_per_class-1]   allocated_ocvc;
		   
		   if(num_vcs_per_class == 1)
		     begin
			assign allocated_next_ocvc = 1'b1;
			assign allocated_ocvc = 1'b1;
		     end
		   else if(num_vcs_per_class > 1)
		     begin
			
			assign allocated_next_ocvc
			  = allocated_q ? allocated_ocvc : next_elig_ocvc;
			
			wire [0:num_vcs_per_class-1] allocated_ocvc_s,
						     allocated_ocvc_q;
			assign allocated_ocvc_s = allocated_next_ocvc;
			c_dff
			  #(.width(num_vcs_per_class),
			    .reset_type(reset_type))
			allocated_ocvcq
			  (.clk(clk),
			   .reset(1'b0),
			   .active(active),
			   .d(allocated_ocvc_s),
			   .q(allocated_ocvc_q));
			
			assign allocated_ocvc = allocated_ocvc_q;
			
		     end
		   
		   wire [0:num_vcs_per_class-1]      flit_sel_ocvc;
		   assign flit_sel_ocvc
		     = allocated_ocvc | {num_vcs_per_class{~allocated_q}};
		   
		   wire [0:num_resource_classes*
			 num_vcs_per_class-1] 	     flit_sel_orc_ocvc;
		   c_mat_mult
		     #(.dim1_width(num_resource_classes),
		       .dim2_width(1),
		       .dim3_width(num_vcs_per_class),
		       .prod_op(`BINARY_OP_AND),
		       .sum_op(`BINARY_OP_OR))
		   flit_sel_orc_ocvc_mmult
		     (.input_a(rf_route_orc),
		      .input_b(flit_sel_ocvc),
		      .result(flit_sel_orc_ocvc));
		   
		   wire [0:num_vcs-1] 		     flit_sel_ovc;
		   c_mat_mult
		     #(.dim1_width(num_message_classes),
		       .dim2_width(1),
		       .dim3_width(num_resource_classes*num_vcs_per_class),
		       .prod_op(`BINARY_OP_AND),
		       .sum_op(`BINARY_OP_OR))
		   flit_sel_ovc_mmult
		     (.input_a(sel_mc),
		      .input_b(flit_sel_orc_ocvc),
		      .result(flit_sel_ovc));
		   
		   
		   //-----------------------------------------------------------
		   // credit tracking for a priori check (allocated VCs)
		   //-----------------------------------------------------------
		   
		   wire [0:num_vcs_per_class-1]      ovs_almost_full_ocvc;
		   rtr_vc_flags_mux
		     #(.num_message_classes(num_message_classes),
		       .num_resource_classes(num_resource_classes),
		       .num_vcs_per_class(num_vcs_per_class),
		       .num_ports(num_ports))
		   ovs_almost_full_ocvc_fmux
		     (.sel_mc(sel_mc),
		      .route_op(rf_route_op),
		      .route_orc(rf_route_orc),
		      .flags_op_ovc(ovs_almost_full_op_ovc),
		      .flags_ocvc(ovs_almost_full_ocvc));
		   
		   wire [0:num_vcs_per_class-1]      almost_full_ocvc;
		   
		   if(dual_path_alloc)
		     assign almost_full_ocvc = route_valid_in ?
					       ovs_almost_full_ocvc :
					       ifl_almost_full_ocvc;
		   else
		     assign almost_full_ocvc = ovs_almost_full_ocvc;
		   
		   wire 			     almost_full;
		   assign almost_full
		     = |(allocated_next_ocvc & almost_full_ocvc);
		   
		   wire [0:num_vcs_per_class-1]      ovs_full_ocvc;
		   rtr_vc_flags_mux
		     #(.num_message_classes(num_message_classes),
		       .num_resource_classes(num_resource_classes),
		       .num_vcs_per_class(num_vcs_per_class),
		       .num_ports(num_ports))
		   ovs_full_ocvc_fmux
		     (.sel_mc(sel_mc),
		      .route_op(rf_route_op),
		      .route_orc(rf_route_orc),
		      .flags_op_ovc(ovs_full_op_ovc),
		      .flags_ocvc(ovs_full_ocvc));
		   
		   wire [0:num_vcs_per_class-1]      full_ocvc;
		   
		   if(dual_path_alloc)
		     assign full_ocvc = route_valid_in ?
					ovs_full_ocvc :
					ifl_full_ocvc;
		   else
		     assign full_ocvc = ovs_full_ocvc;
		   
		   wire 			     full;
		   assign full = |(allocated_next_ocvc & full_ocvc);
		   
		   // we need to track credits even when we temporarily run out 
		   // of flits; otherwise, there can be a dead cycle when a new 
		   // flit arrives after the last flit before we ran out 
		   // filled up the downstream buffer
		   //
		   // NOTE: As it is, synthesis will probably turn this into a 
		   // free-running register!
		   
		   wire 			     cred_active;
		   assign cred_active = flit_valid | allocated_q;
		   
		   // NOTE: Since we only use 'cred_q' once the VC is
		   // allocated, we can ignore 'flit_kill' here -- if the flit
		   // is killed, we failed allocation, and thus the value of
		   // 'cred_q' will be ignored in the next cycle anyway.
		   
		   wire 			     cred_s, cred_q;
		   assign cred_s = ~full & ~(almost_full & flit_sent);
		   c_dff
		     #(.width(1),
		       .reset_type(reset_type))
		   credq
		     (.clk(clk),
		      .reset(1'b0),
		      .active(cred_active),
		      .d(cred_s),
		      .q(cred_q));
		   
		   
		   //-----------------------------------------------------------
		   // connect outputs
		   //-----------------------------------------------------------
		   
		   assign ivs_allocated = allocated_q;
		   assign ivs_cred = cred_q;
		   assign ivs_flit_kill = flit_kill;
		   assign ivs_flit_sel_ovc = flit_sel_ovc;
		   
		end
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // switch allocation
	   //-------------------------------------------------------------------
	   
	   begin:ial
	      
	      wire active;
	      assign active = |flit_valid_in_ivc;
	      	      
	      // We only allow speculative requests and those that already have 
	      // an output VC allocated to them and at least one credit 
	      // available.
	      
	      wire [0:num_vcs-1] req_hi_ivc;
	      assign req_hi_ivc
		= flit_valid_in_ivc & ivs_allocated_ivc & ivs_cred_ivc;
	      
	      wire [0:num_vcs-1] req_lo_ivc;
	      assign req_lo_ivc = flit_valid_in_ivc & ~ivs_allocated_ivc;
	      
	      wire [0:num_vcs-1] req_ivc;
	      assign req_ivc = req_hi_ivc | req_lo_ivc;
	      
	      wire kill_fast;
	      
	      if(dual_path_alloc)
		assign kill_fast = |req_ivc;
	      else
		assign kill_fast = 1'b1;
	      
	      wire [0:num_vcs-1] gnt_ivc;
	      
	      if(precomp_ivc_sel)
		begin
		   
		   if(num_vcs == 1)
		     assign gnt_ivc = req_ivc;
		   else if(num_vcs > 1)
		     begin
			
			wire update;
			
			wire [0:num_vcs-1] req_all_ivc;
			assign req_all_ivc = flit_valid_in_ivc;
			
			wire [0:num_vcs-1] mgnt_ivc;
			c_arbiter
			  #(.num_ports(num_vcs),
			    .num_priorities(3),
			    .arbiter_type(sw_alloc_arbiter_type),
			    .reset_type(reset_type))
			marb
			  (.clk(clk),
			   .reset(reset),
			   .active(active),
			   .req({req_hi_ivc, req_lo_ivc, req_all_ivc}),
			   .gnt(mgnt_ivc),
			   .update(update));
			
			wire [0:num_vcs-1] flit_sent_ivc;
			assign flit_sent_ivc = {num_vcs{oal_flit_sent}} & 
					       gnt_ivc & ~ivs_flit_kill_ivc;
			
			wire [0:num_vcs-1] rem_ivc;
			assign rem_ivc = flit_valid_in_ivc & 
					 ~(flit_sent_ivc & flit_last_in_ivc);
			
			wire [0:num_vcs-1] mask_ivc_s, mask_ivc_q;
			assign mask_ivc_s = update ? 
					    (mgnt_ivc | {num_vcs{~|rem_ivc}}) : 
					    mask_ivc_q;
			c_dff
			  #(.width(num_vcs),
			    .reset_value({num_vcs{1'b1}}),
			    .reset_type(reset_type))
			mask_ivcq
			  (.clk(clk),
			   .reset(reset),
			   .active(active),
			   .d(mask_ivc_s),
			   .q(mask_ivc_q));
			
			assign update
			  = (oal_flit_sent & kill_fast) | 
			    (|req_hi_ivc & ~|(req_hi_ivc & mask_ivc_q)) | 
			    (|req_ivc & ~|(req_ivc & mask_ivc_q)) | 
			    (|req_all_ivc & (&mask_ivc_q));
			
			assign gnt_ivc = req_ivc & mask_ivc_q;
			
		     end
		   
		end
	      else
		begin
		   
		   wire update;
		   assign update = oal_flit_sent & kill_fast;
		   
		   c_arbiter
		     #(.num_ports(num_vcs),
		       .num_priorities(2),
		       .arbiter_type(sw_alloc_arbiter_type),
		       .reset_type(reset_type))
		   arb
		     (.clk(clk),
		      .reset(reset),
		      .active(active),
		      .req({req_hi_ivc, req_lo_ivc}),
		      .gnt(gnt_ivc),
		      .update(update));
		   
		end
	      
	      wire [0:num_ports-1] flit_valid_op;
	      c_select_mofn
		#(.num_ports(num_vcs),
		  .width(num_ports))
	      flit_valid_op_sel
		(.select(gnt_ivc),
		 .data_in(rf_route_ivc_op),
		 .data_out(flit_valid_op));
	      
	      wire 		   flit_head;
	      wire 		   flit_tail;
	      wire [0:num_vcs-1]   flit_sel_ovc;
	      wire flit_kill;
	      
	      if(num_vcs == 1)
		begin
		   assign flit_head = ~ivs_allocated_ivc;
		   assign flit_tail = flit_tail_in_ivc;
		   assign flit_sel_ovc = ivs_flit_sel_ivc_ovc;
		   assign flit_kill = ivs_flit_kill_ivc;
		end
	      else if(num_vcs > 1)
		begin
		   
		   if(precomp_ivc_sel)
		     assign flit_head = ~|(gnt_ivc & ivs_allocated_ivc);
		   else
		     assign flit_head = ~|req_hi_ivc;
		   
		   assign flit_tail = |(gnt_ivc & flit_tail_in_ivc);
		   
		   c_select_1ofn
		     #(.num_ports(num_vcs),
		       .width(num_vcs))
		   flit_sel_ovc_sel
		     (.select(gnt_ivc),
		      .data_in(ivs_flit_sel_ivc_ovc),
		      .data_out(flit_sel_ovc));
		   
		   assign flit_kill = |(gnt_ivc & ivs_flit_kill_ivc);
		   
		end
	      
	      wire flit_sel_fast;
	      assign flit_sel_fast = ~kill_fast;
	      
	      assign ial_flit_valid_op
		= flit_sel_fast ? ifl_flit_valid_op : flit_valid_op;
	      assign ial_flit_sel_ivc
		= flit_sel_fast ? flit_sel_fast_in_ivc : gnt_ivc;
	      assign ial_flit_head
		= flit_sel_fast ? flit_head_fast_in : flit_head;
	      assign ial_flit_tail
		= flit_sel_fast ? flit_tail_fast_in : flit_tail;
	      assign ial_flit_sel_ovc
		= flit_sel_fast ? ifl_flit_sel_ovc : flit_sel_ovc;
	      
	      assign flit_sel_out_ivc = gnt_ivc;	
	      assign flit_sel_fast_out = flit_sel_fast;
	      assign flit_sent_out
		= oal_flit_sent & ~(flit_sel_fast ? ifl_flit_kill : flit_kill);
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // generate activity signals for output side
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] active_ivc;
	   
	   wire [0:num_ports-1] route_op;
	   c_select_mofn
	     #(.num_ports(num_vcs),
	       .width(num_ports))
	   route_op_sel
	     (.select(active_ivc),
	      .data_in(rf_route_ivc_op),
	      .data_out(route_op));
	   
	   if(dual_path_alloc)
	     begin
		
		assign active_ivc
		  = flit_valid_in_ivc | 
		    (flit_valid_fast_in_ivc & {num_vcs{~flit_head_fast_in}});
		
		wire [0:num_ports-1] route_fast_op;
		assign route_fast_op
		  = {num_ports{flit_valid_fast_in & flit_head_fast_in}} &
		    route_fast_in_op;
		
		assign active_op = route_op | route_fast_op;
		
	     end
	   else
	     begin
		
		assign active_ivc = flit_valid_in_ivc;
		
		assign active_op = route_op;
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // combine activity signals for output side
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] active_op;
   c_binary_op
     #(.num_ports(num_ports),
       .width(num_ports),
       .op(`BINARY_OP_OR))
   active_op_or
     (.data_in(active_ip_op),
      .data_out(active_op));
   
   
   //---------------------------------------------------------------------------
   // connect input and output side
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] ial_flit_valid_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   ial_flit_valid_op_ip_intl
     (.data_in(ial_flit_valid_ip_op),
      .data_out(ial_flit_valid_op_ip));
   
   wire [0:num_ports*num_ports-1] oal_flit_sent_op_ip;
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   oal_flit_sent_ip_op_intl
     (.data_in(oal_flit_sent_op_ip),
      .data_out(oal_flit_sent_ip_op));
   
   
   //---------------------------------------------------------------------------
   // output side
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs*2-1] ovs_errors_op_ovc;
   
   generate
      
      //------------------------------------------------------------------------
      // output ports
      //------------------------------------------------------------------------
      
      genvar 					  op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------
	   
	   wire active;
	   assign active = active_op[op];
	   
	   wire [0:num_ports-1] ial_flit_valid_ip;
	   assign ial_flit_valid_ip
	     = ial_flit_valid_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire fc_event_valid_in;
	   assign fc_event_valid_in = fc_event_valid_in_op[op];
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------
	   
	   wire empty_out;
	   assign empty_out_op[op] = empty_out;
	   
	   wire [0:num_vcs-1] ovs_full_ovc;
	   assign ovs_full_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = ovs_full_ovc;
	   
	   wire [0:num_vcs-1] nvs_next_elig_ovc;
	   assign nvs_next_elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1]
		    = nvs_next_elig_ovc;
	   
	   wire [0:num_ports-1] oal_flit_sent_ip;
	   assign oal_flit_sent_op_ip[op*num_ports:(op+1)*num_ports-1]
	     = oal_flit_sent_ip;
	   
	   wire 		flit_valid_out;
	   assign flit_valid_out_op[op] = flit_valid_out;
	   
	   wire 		flit_head_out;
	   assign flit_head_out_op[op] = flit_head_out;
	   
	   wire 		flit_tail_out;
	   assign flit_tail_out_op[op] = flit_tail_out;
	   
	   wire [0:num_vcs-1] 	flit_sel_out_ovc;
	   assign flit_sel_out_op_ovc[op*num_vcs:(op+1)*num_vcs-1]
	     = flit_sel_out_ovc;
	   
	   wire [0:num_ports-1] flit_sel_out_ip;
	   assign flit_sel_out_op_ip[op*num_ports:(op+1)*num_ports-1]
	     = flit_sel_out_ip;
	   
	   
	   //-------------------------------------------------------------------
	   // arbitration
	   //-------------------------------------------------------------------
	   
	   wire 		oal_flit_sent;
	   wire 		oal_flit_head;
	   wire 		oal_flit_tail;
	   wire [0:num_vcs-1] 	oal_flit_sel_ovc;
	   
	   begin:oal
	      
	      wire [0:num_ports-1] req_hi_ip;
	      assign req_hi_ip = ial_flit_valid_ip & ~ial_flit_head_ip;
	      
	      wire [0:num_ports-1] req_lo_ip;
	      assign req_lo_ip = ial_flit_valid_ip;
	      
	      // NOTE: If a head flit wins output arbitration, but the 
	      // subsequent check for an eligible output VC to go to fails, we 
	      // still update the arbiter. This is so  we don't get stuck on a 
	      // single VC that is unable to acquire an output VC trying over 
	      // and over again to the exclusion of all others.
	      
	      wire 		   flit_sent;
	      assign flit_sent = |ial_flit_valid_ip;
	      
	      wire 		   update;
	      assign update = flit_sent;
	      
	      wire [0:num_ports-1] gnt_ip;
	      c_arbiter
		#(.num_ports(num_ports),
		  .num_priorities(2),
		  .arbiter_type(sw_alloc_arbiter_type),
		  .reset_type(reset_type))
	      oarb
		(.clk(clk),
		 .reset(reset),
		 .active(active),
		 .req({req_hi_ip, req_lo_ip}),
		 .gnt(gnt_ip),
		 .update(update));
	      
	      assign oal_flit_sent_ip = gnt_ip;
	      assign oal_flit_sent = flit_sent;
	      assign oal_flit_head = |(gnt_ip & ial_flit_head_ip);
	      assign oal_flit_tail = |(gnt_ip & ial_flit_tail_ip);
	      
	      wire [0:num_ports*num_vcs-1] flit_sel_ip_ovc;
	      
	      genvar 			   ip;
	      
	      for(ip = 0; ip < num_ports; ip = ip + 1)
		begin:ips
		   
		   wire [0:num_vcs-1] ial_flit_sel_ovc;
		   assign ial_flit_sel_ovc
		     = ial_flit_sel_ip_ovc[ip*num_vcs:(ip+1)*num_vcs-1];
		   
		   wire 	      ial_flit_head;
		   assign ial_flit_head = ial_flit_head_ip[ip];
		   
		   wire [0:num_vcs-1] flit_sel_ovc;
		   assign flit_sel_ovc
		     = ial_flit_sel_ovc & 
		       ({num_vcs{~ial_flit_head}} | nvs_next_elig_ovc);
		   
		   assign flit_sel_ip_ovc[ip*num_vcs:(ip+1)*num_vcs-1]
		     = flit_sel_ovc;
		   
		end
	      
	      wire [0:num_vcs-1]      flit_sel_ovc;
	      c_select_1ofn
		#(.num_ports(num_ports),
		  .width(num_vcs))
	      flit_sel_ovc_sel
		(.select(gnt_ip),
		 .data_in(flit_sel_ip_ovc),
		 .data_out(flit_sel_ovc));
	      
	      assign oal_flit_sel_ovc = flit_sel_ovc;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // generate crossbar control signals
	   //-------------------------------------------------------------------
	   
	   wire 		      valid_active;
	   assign valid_active = active | flit_valid_out;
	   
	   begin:xcl
	      
	      wire [0:num_ports-1] flit_sel_ip_s, flit_sel_ip_q;
	      assign flit_sel_ip_s = oal_flit_sent_ip;
	      c_dff
		#(.width(num_ports),
		  .reset_type(reset_type))
	      flit_sel_ipq
		(.clk(clk),
		 .reset(reset),
		 .active(valid_active),
		 .d(flit_sel_ip_s),
		 .q(flit_sel_ip_q));
	      
	      assign flit_sel_out_ip = flit_sel_ip_q;
	      
	   end
	   
	   
	   //-------------------------------------------------------------------
	   // stage controls signals for output controllers
	   //-------------------------------------------------------------------
	   
	   // NOTE: 'flit_valid_out' will be one even when a head flit fails to 
	   // acquire a VC; however, in this case, 'flit_sel_out_ovc' will be 
	   // all-zeroes, so we must check for this case in the output 
	   // controller.
	   
	   wire 		   flit_valid_s, flit_valid_q;
	   assign flit_valid_s = oal_flit_sent;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_validq
	     (.clk(clk),
	      .reset(reset),
	      .active(valid_active),
	      .d(flit_valid_s),
	      .q(flit_valid_q));
	   
	   assign flit_valid_out = flit_valid_q;
	   
	   wire 		   flit_head_s, flit_head_q;
	   assign flit_head_s = oal_flit_head;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_headq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(active),
	      .d(flit_head_s),
	      .q(flit_head_q));
	   
	   assign flit_head_out = flit_head_q;
	   
	   wire 		   flit_tail_s, flit_tail_q;
	   assign flit_tail_s = oal_flit_tail;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_tailq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(active),
	      .d(flit_tail_s),
	      .q(flit_tail_q));
	   
	   assign flit_tail_out = flit_tail_q;
	   
	   wire [0:num_vcs-1] 	   flit_sel_ovc_s, flit_sel_ovc_q;
	   assign flit_sel_ovc_s = oal_flit_sel_ovc;
	   c_dff
	     #(.width(num_vcs),
	       .reset_type(reset_type))
	   flit_sel_ovcq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(active),
	      .d(flit_sel_ovc_s),
	      .q(flit_sel_ovc_q));
	   
	   assign flit_sel_out_ovc = flit_sel_ovc_q;
	   
	   
	   //-------------------------------------------------------------------
	   // output VCs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	   ovs_elig_ovc;
	   
	   wire [0:num_vcs-1] 	   ovs_empty_ovc;
	   assign empty_out = &ovs_empty_ovc;
	   
	   genvar 		   ovc;
	   
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------
		
		wire oal_flit_sel;
		assign oal_flit_sel = oal_flit_sel_ovc[ovc];
		
		wire fc_event_sel_in;
		assign fc_event_sel_in = fc_event_sel_in_op_ovc[op*num_vcs+ovc];
		
		
		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------
		
		wire ovs_elig;
		assign ovs_elig_ovc[ovc] = ovs_elig;
		
		wire ovs_empty;
		assign ovs_empty_ovc[ovc] = ovs_empty;
		
		wire ovs_almost_full;
		assign ovs_almost_full_op_ovc[op*num_vcs+ovc] = ovs_almost_full;
		
		wire ovs_full;
		assign ovs_full_ovc[ovc] = ovs_full;
		
		wire [0:1] ovs_errors;
		assign ovs_errors_op_ovc[(op*num_vcs+ovc)*2:
					 (op*num_vcs+ovc+1)*2-1] = ovs_errors;
		
		
		//--------------------------------------------------------------
		// VC state tracking
		//--------------------------------------------------------------
		
		wire 	   ovs_active;
		assign ovs_active = active | fc_event_valid_in;
		
		wire 	   flit_sent;
		assign flit_sent = oal_flit_sent & oal_flit_sel;
		
		wire 	   fc_event_valid;
		assign fc_event_valid = fc_event_valid_in & fc_event_sel_in;
		
		rtr_vc_state
		  #(.num_flits_per_vc(num_flits_per_vc),
		    .flow_ctrl_type(flow_ctrl_type),
		    .reset_type(reset_type))
		ovs
		  (.clk(clk),
		   .reset(reset),
		   .active(ovs_active),
		   .flit_sent(flit_sent),
		   .flit_tail(oal_flit_tail),
		   .fc_event_valid(fc_event_valid),
		   .elig(ovs_elig),
		   .empty(ovs_empty),
		   .almost_full(ovs_almost_full),
		   .full(ovs_full),
		   .errors(ovs_errors));
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // determine next free VC for each class
	   //-------------------------------------------------------------------
	   
	   begin:nvs
	      
	      if(num_vcs_per_class == 1)
		assign nvs_next_elig_ovc = ovs_elig_ovc;
	      else if(num_vcs_per_class > 1)
		begin
		   
		   genvar opc;
		   
		   for(opc = 0; opc < num_packet_classes; opc = opc + 1)
		     begin:opcs
			
			wire [0:num_vcs_per_class-1] oal_flit_sel_ocvc;
			assign oal_flit_sel_ocvc
			  = oal_flit_sel_ovc[opc*num_vcs_per_class:
					     (opc+1)*num_vcs_per_class-1];
			
			wire 			     update;
			assign update = oal_flit_sent & oal_flit_head & 
					(|oal_flit_sel_ocvc);
			
			wire [0:num_vcs_per_class-1] ovs_elig_ocvc;
			assign ovs_elig_ocvc
			  = ovs_elig_ovc[opc*num_vcs_per_class:
					 (opc+1)*num_vcs_per_class-1];
			
			wire [0:num_vcs_per_class-1] ovs_empty_ocvc;
			assign ovs_empty_ocvc
			  = ovs_empty_ovc[opc*num_vcs_per_class:
					  (opc+1)*num_vcs_per_class-1];
			
			wire [0:num_vcs_per_class-1] req_hi_ocvc;
			assign req_hi_ocvc = ovs_elig_ocvc & ovs_empty_ocvc;
			
			wire [0:num_vcs_per_class-1] req_lo_ocvc;
			assign req_lo_ocvc = ovs_elig_ocvc;
			
			wire [0:num_vcs_per_class-1] gnt_ocvc;
			c_arbiter
			  #(.num_ports(num_vcs_per_class),
			    .num_priorities(2),
			    .arbiter_type(vc_alloc_arbiter_type),
			    .reset_type(reset_type))
			arb
			  (.clk(clk),
			   .reset(reset),
			   .active(active),
			   .req({req_hi_ocvc, req_lo_ocvc}),
			   .gnt(gnt_ocvc),
			   .update(update));
			
			assign nvs_next_elig_ovc[opc*num_vcs_per_class:
						 (opc+1)*num_vcs_per_class-1]
			  = gnt_ocvc;
			
		     end
		   
		end
	      
	   end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checker logic
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_ports*num_vcs*2-1] errors_s, errors_q;
	   assign errors_s = ovs_errors_op_ovc;
	   c_err_rpt
	     #(.num_errors(num_ports*num_vcs*2),
	       .capture_mode(error_capture_mode),
	       .reset_type(reset_type))
	   chk
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .errors_in(errors_s),
	      .errors_out(errors_q));
	   
	   assign error = |errors_q;
	   
	end
      else
	assign error = 1'b0;
      
   endgenerate
   
endmodule
