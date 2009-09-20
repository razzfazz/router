// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
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



// output port controller (tracks state of buffers in downstream router)
module vcr_op_ctrl_mac
  (clk, reset, flow_ctrl_in, vc_gnt_ovc, vc_gnt_ovc_ip, vc_gnt_ovc_ivc, 
   sw_oreq_nonspec_ip, sw_oreq_spec_ip, sw_ognt_nonspec_ip, sw_ognt_spec_ip, 
   sw_gnt_nonspec_ip, sw_gnt_spec_ip, int_flit_ctrl_in, flit_data_in, 
   flit_ctrl_out, flit_data_out, elig_ovc, int_flow_ctrl_ovc, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width required to select a buffer
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   // width of counter for credits waiting to be sent to input controller
   localparam cred_hold_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs available for each class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
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
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // number of bits to be used for credit level reporting
   // (note: must be less than or equal to cred_count_width as given below)
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_LEVEL)
   parameter cred_level_width = 2;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width
     = 1 + vc_idx_width + 1 + 1;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (credit_handling_type == `CREDIT_HANDLING_TYPE_LEVEL) ?
       cred_level_width :
       (credit_handling_type == `CREDIT_HANDLING_TYPE_PUSH) ?
       1 :
       -1;
   
   // maximum value for credit level
   localparam [0:cred_level_width-1] max_cred_level = {cred_level_width{1'b1}};
   
   // capped reset value for credit level
   localparam [0:cred_level_width-1] free_reset_value
     = (num_flit_buffers > max_cred_level) ? max_cred_level : num_flit_buffers;
   
   // select implementation variant for switch allocator
   parameter sw_alloc_type = `SW_ALLOC_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_alloc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type for switch allocator
   parameter sw_alloc_spec_type = `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // output VC was granted to an input VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // input port that each output VC was granted to
   input [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
   
   // input VC that each output VC was granted to
   input [0:num_vcs*num_vcs-1] vc_gnt_ovc_ivc;
   
   // non-speculative switch allocation requests from input stage
   input [0:num_ports-1] sw_oreq_nonspec_ip;
   
   // speculative switch allocation requests from input stage
   input [0:num_ports-1] sw_oreq_spec_ip;
   
   // non-speculative switch allocation grants to input stage
   output [0:num_ports-1] sw_ognt_nonspec_ip;
   wire [0:num_ports-1] sw_ognt_nonspec_ip;
   
   // speculative switch allocation grants to input stage
   output [0:num_ports-1] sw_ognt_spec_ip;
   wire [0:num_ports-1] sw_ognt_spec_ip;
   
   // non-speculative global switch allocation grants
   input [0:num_ports-1] sw_gnt_nonspec_ip;
   
   // speculative global switch allocation grants
   input [0:num_ports-1] sw_gnt_spec_ip;
   
   // incoming flit control signals
   input [0:int_flit_ctrl_width-1] int_flit_ctrl_in;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs-1] elig_ovc;
   
   // internal flow control signalling from output controller to input 
   // controllers
   output [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
   wire [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
   
   // internal error condition detected
   output error;
   wire 				  error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire [0:flow_ctrl_width-1] 		  flow_ctrl_s, flow_ctrl_q;
   assign flow_ctrl_s = flow_ctrl_in;
   
   wire 				  cred_valid_s, cred_valid_q;
   assign cred_valid_s = flow_ctrl_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign flow_ctrl_q[0] = cred_valid_q;

   generate
      
      if(flow_ctrl_width > 1)
	begin
	   
	   c_dff
	     #(.width(flow_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flow_ctrlq
	     (.clk(clk),
	      .reset(reset),
	      .d(flow_ctrl_s[1:flow_ctrl_width-1]),
	      .q(flow_ctrl_q[1:flow_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // switch allocation
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] sw_gnt_ip;
   
   generate
      
      if((sw_alloc_type == `SW_ALLOC_TYPE_SEP_IF) ||
	 (sw_alloc_type == `SW_ALLOC_TYPE_SEP_OF))
	begin
	   
	   // any non-speculative requests for this port?
	   wire sw_oreq_nonspec;
	   assign sw_oreq_nonspec = |sw_oreq_nonspec_ip;
	   
	   //any non-speculative grants for this port?
	   wire sw_gnt_nonspec;
	   assign sw_gnt_nonspec = |sw_gnt_nonspec_ip;
	   
	   // update arbiter priorities
	   wire update_arb_nonspec;
	   
	   case(sw_alloc_type)
	     
	     `SW_ALLOC_TYPE_SEP_IF:
	       begin
		  
		  //------------------------------------------------------------
		  // For the input-first separable allocator, if any requests 
		  // reach the output stage, they must already have won input-
		  // side arbitration; consequently, one of them will result in 
		  // an global grant, and we can thus update arbiter priorities
		  // whenever we see a request.
		  //------------------------------------------------------------
		  
		  assign update_arb_nonspec = sw_oreq_nonspec;
		  
	       end
	     
	     `SW_ALLOC_TYPE_SEP_OF:
	       begin
		  
		  //------------------------------------------------------------
		  // For separable output-first allocation, any grants generated
		  // by the output stage may subsequently be dropped at the 
		  // input stage; consequently, we must only update priorities 
		  // once we know that our grant also won input-side 
		  // arbitration.
		  //------------------------------------------------------------
		  
		  assign update_arb_nonspec = sw_gnt_nonspec;
		  
	       end
	     
	   endcase
	   
	   
	   //-------------------------------------------------------------------
	   // The actual arbitration is identical for the input- and output-
	   // first cases.
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_nonspec_ip;
	   assign req_nonspec_ip = sw_oreq_nonspec_ip;
	   
	   wire [0:num_ports-1] gnt_nonspec_ip;
	   c_arbiter
	     #(.num_ports(num_ports),
	       .arbiter_type(sw_alloc_arbiter_type),
	       .reset_type(reset_type))
	   gnt_nonspec_ip_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb_nonspec),
	      .req(req_nonspec_ip),
	      .gnt(gnt_nonspec_ip));
	   
	   assign sw_ognt_nonspec_ip = gnt_nonspec_ip;
	   
	   
	   //-------------------------------------------------------------------
	   // speculative switch allocation support
	   //-------------------------------------------------------------------
	   
	   if(sw_alloc_spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	     begin
		
		// arbitrate between speculative requests
		wire [0:num_ports-1] req_spec_ip;
		wire [0:num_ports-1] gnt_spec_ip;
		wire 		     update_arb_spec;

		case(sw_alloc_type)
		  
		  `SW_ALLOC_TYPE_SEP_IF:
		    begin
		       
		       //-------------------------------------------------------
		       // For input-first allocation, any non-speculative 
		       // requests arriving at the output stage must already 
		       // have won input-side arbitration, and thus one of them 
		       // will always be granted; therefore, we can suppress 
		       // speculative grants and the arbiter state update in 
		       // this case whenever any non-speculative requests are 
		       // present. 
		       // Likewise, the global grants can be formed by 
		       // combining the non-speculative and speculative output-
		       // side grants.
		       //-------------------------------------------------------
		       
		       assign update_arb_spec
			 = ~sw_oreq_nonspec & |sw_oreq_spec_ip;
		       
		       assign sw_ognt_spec_ip
			 = {num_ports{~sw_oreq_nonspec}} & gnt_spec_ip;
		       
		       assign sw_gnt_ip = sw_ognt_nonspec_ip | sw_ognt_spec_ip;
		       
		    end
		  
		  `SW_ALLOC_TYPE_SEP_OF:
		    begin
		       case(sw_alloc_spec_type)
			 
			 `SW_ALLOC_SPEC_TYPE_REQS_MASK_GNTS,
			 `SW_ALLOC_SPEC_TYPE_REQS_MASK_REQS:
			   begin
			      
			      //------------------------------------------------
			      // For output-first allocation, on the other hand,
			      // any given output-side non-speculative grant may
			      // still fail to win input-side arbitration; 
			      // however, if we suppress speculative requests 
			      // based on non-speculative grants, we can still 
			      // use the same approach as in the input-first 
			      // case. 
			      //------------------------------------------------
			      
			      assign update_arb_spec
				= ~sw_oreq_nonspec & |sw_oreq_spec_ip;
			      
			      assign sw_ognt_spec_ip
				= {num_ports{~sw_oreq_nonspec}} & gnt_spec_ip;
			      
			   end
			 
			 `SW_ALLOC_SPEC_TYPE_GNTS_MASK_GNTS,
			 `SW_ALLOC_SPEC_TYPE_GNTS_MASK_REQS:
			   begin
			      
			      //------------------------------------------------
			      // For output-first allocation with conflict 
			      // detection based on non-speculative grants, 
			      // however, we must check if non-speculative 
			      // grants also won input-side arbitration before 
			      // suppressing speculative grants and inhibiting 
			      // arbiter state updates.
			      //------------------------------------------------
			      
			      assign update_arb_spec
				= ~sw_gnt_nonspec & |sw_gnt_spec_ip;
			      
			      assign sw_ognt_spec_ip
				= {num_ports{~sw_gnt_nonspec}} & gnt_spec_ip;
			      
			   end
			 
		       endcase
		       
		       //-------------------------------------------------------
		       // The global grants in this case come from the input-
		       // side arbitration stage; speculation-related masking is
		       // performed at the input side.
		       //-------------------------------------------------------
		       
		       assign sw_gnt_ip = sw_gnt_nonspec_ip | sw_gnt_spec_ip;
		       
		    end
		  
		endcase
		
		assign req_spec_ip = sw_oreq_spec_ip;
		       
		c_arbiter
		  #(.num_ports(num_ports),
		    .arbiter_type(sw_alloc_arbiter_type),
		    .reset_type(reset_type))
		gnt_spec_ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb_spec),
		   .req(req_spec_ip),
		   .gnt(gnt_spec_ip));
		
	     end
	   else
	     begin
		
		//--------------------------------------------------------------
		// If speculation is disabled, all speculation-related control
		// signals are just tied to zero.
		//--------------------------------------------------------------
		
		assign sw_ognt_spec_ip = {num_ports{1'b0}};
		
		case(sw_alloc_type)
		  
		  `SW_ALLOC_TYPE_SEP_IF:
		    begin
		       
		       //-------------------------------------------------------
		       // In the separable input-first case, every output-side
		       // request already succeeded in input-side arbitration, 
		       // and thus the global grants are just the output-side 
		       // grants; i.e., we do not need to consider the incoming 
		       // sw_gnt_*_ip signals.
		       //-------------------------------------------------------
		       
		       assign sw_gnt_ip = sw_ognt_nonspec_ip;
		       
		    end
		  
		  `SW_ALLOC_TYPE_SEP_OF:
		    begin
		       
		       //-------------------------------------------------------
		       // In the output-first case, on the other hand, the 
		       // global grants are generated by the input-side
		       // arbitration stage.
		       //-------------------------------------------------------
		       
		       assign sw_gnt_ip = sw_gnt_nonspec_ip;
		       
		    end
		  
		endcase
		
	     end
	   
	end
      else if((sw_alloc_type >= `SW_ALLOC_TYPE_WF_BASE) && 
	      (sw_alloc_type <= `SW_ALLOC_TYPE_WF_LIMIT))
	begin
	   
	   //-------------------------------------------------------------------
	   // The wavefront allocator does not require any output-side logic. 
	   // Global grants are generated externally in the wavefront block.
	   //-------------------------------------------------------------------
	   
	   assign sw_ognt_nonspec_ip = {num_ports{1'b0}};
	   assign sw_ognt_spec_ip = {num_ports{1'b0}};
	   
	   if(sw_alloc_spec_type == `SW_ALLOC_SPEC_TYPE_NONE)
	     assign sw_gnt_ip = sw_gnt_nonspec_ip;
	   else
	     assign sw_gnt_ip = sw_gnt_nonspec_ip | sw_gnt_spec_ip;
	   
	end
      
   endgenerate
   
   wire sw_gnt_s;
   assign sw_gnt_s = |sw_gnt_ip;
   
   wire sw_gnt_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   sw_gntq
     (.clk(clk),
      .reset(reset),
      .d(sw_gnt_s),
      .q(sw_gnt_q));
   
   wire [0:num_ports-1] 		  sw_gnt_ip_s;
   assign sw_gnt_ip_s = sw_gnt_ip;
   
   wire [0:num_ports-1] 		  sw_gnt_ip_q;
   c_dff
     #(.width(num_ports),
       .reset_type(reset_type))
   sw_gnt_ipq
     (.clk(clk),
      .reset(reset),
      .d(sw_gnt_ip_s),
      .q(sw_gnt_ip_q));
   
   
   //---------------------------------------------------------------------------
   // output VC control logic
   //---------------------------------------------------------------------------

   wire 				  flit_valid_in;
   assign flit_valid_in = int_flit_ctrl_in[0] & sw_gnt_q;
   
   wire 				  flit_tail_in;
   assign flit_tail_in = int_flit_ctrl_in[1+vc_idx_width+1];
   
   wire 				  cred_valid;
   assign cred_valid = flow_ctrl_q[0];
   
   wire [0:num_vcs-1] 			  match_ovc;
   
   wire 				  error_unmatched;
   assign error_unmatched = flit_valid_in & ~|match_ovc;
   
   wire [0:num_vcs-1] 			  next_cred_ovc;
   wire [0:num_vcs-1] 			  error_hct_ovc;
   wire [0:num_vcs*2-1] 		  error_cred_ovc;
   
   generate
      
      genvar 				  ovc;
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   
	   if(num_vcs > 1)
	     begin
		
		wire [0:vc_idx_width-1] cred_vc;
		assign cred_vc = flow_ctrl_q[1:1+vc_idx_width-1];
		
		assign credit = cred_valid && (cred_vc == ovc);
		
	     end
	   else
	     assign credit = cred_valid;
	   
	   wire 			flit_valid_in_qual;
	   assign flit_valid_in_qual = flit_valid_in & match_ovc[ovc];
	   
	   wire 			debit;
	   assign debit = flit_valid_in_qual;
	   
	   wire 			vc_gnt;
	   assign vc_gnt = vc_gnt_ovc[ovc];
	   
	   
	   //-------------------------------------------------------------------
	   // track whether this output VC is currently assigend to an input VC
	   //-------------------------------------------------------------------
	   
	   wire set_allocated;
	   assign set_allocated = vc_gnt;
	   
	   wire reset_allocated;   
	   assign reset_allocated = flit_valid_in_qual & flit_tail_in;
	   
	   wire allocated_s, allocated_q;
	   assign allocated_s
	     = (set_allocated | allocated_q) & ~reset_allocated;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   allocatedq
	     (.clk(clk),
	      .reset(reset),
	      .d(allocated_s),
	      .q(allocated_q));
	   
	   if(num_vcs > 1)
	     begin
		
		wire [0:vc_idx_width-1] flit_vc_in;
		assign flit_vc_in = int_flit_ctrl_in[1:1+vc_idx_width-1];
		
		// if VC assignment is tracked at the output, each output VC 
		// needs to check if it is currently assigned to the incoming VC
		// ID at the selected input port
		if(track_vcs_at_output)
		  begin
		     
		     wire [0:num_ports-1] vc_gnt_ip;
		     assign vc_gnt_ip
		       = vc_gnt_ovc_ip[ovc*num_ports:(ovc+1)*num_ports-1];
		     
		     wire [0:num_ports-1] allocated_ip_s, allocated_ip_q;
		     assign allocated_ip_s
		       = vc_gnt ? vc_gnt_ip : allocated_ip_q;
		     c_dff
		       #(.width(num_ports),
			 .reset_type(reset_type))
		     allocated_ipq
		       (.clk(clk),
			.reset(reset),
			.d(allocated_ip_s),
			.q(allocated_ip_q));
		     
		     wire [0:num_vcs-1]   vc_gnt_ivc;
		     assign vc_gnt_ivc
		       = vc_gnt_ovc_ivc[ovc*num_vcs:(ovc+1)*num_vcs-1];
		     
		     wire [0:num_vcs-1]   allocated_ivc_s, allocated_ivc_q;
		     assign allocated_ivc_s
		       = vc_gnt ? vc_gnt_ivc : allocated_ivc_q;
		     c_dff
		       #(.width(num_vcs),
			 .reset_type(reset_type))
		     allocated_ivcq
		       (.clk(clk),
			.reset(reset),
			.d(allocated_ivc_s),
			.q(allocated_ivc_q));
		     
		     assign match_ovc[ovc] = allocated_q &
					     |(allocated_ip_q & sw_gnt_ip_q) &
					     allocated_ivc_q[flit_vc_in];
		     
		  end
		
		// if VC assignments are tracked at the input side, we can just 
		// check for our own VC ID
		else
		  assign match_ovc[ovc] = (flit_vc_in == ovc);
		
	     end
	   
	   // if we only have a single VC to begin with, it is always selected
	   else
	     assign match_ovc[ovc] = 1'b1;
	   
	   
	   //-------------------------------------------------------------------
	   // track number of packets that downstream buffer can still accept
	   //-------------------------------------------------------------------
	   
	   wire [0:cred_count_width-1] cred_count_s;
	   wire 		       head_free_early;
	   
	   if(num_header_buffers == num_flit_buffers)
	     begin
		
		// if every flit buffer entry can be a head flit, we don't need 
		// dedicated credit tracking for headers, and can instead just
		// rely on the normal credit tracking mechanism
		assign head_free_early = 1'b1;
		
		assign error_hct_ovc[ovc] = 1'b0;
		
	     end
	   else
	     begin

		// if only a subset of the flit buffer entries can be headers, 
		// we need to keep track of how many such slots are left
		
		if(num_header_buffers == 1)
		  begin
		     
		     // if we can only have one packet per buffer, we can accept
		     // the next one once the buffer has been completely drained
		     // after the tail has been sent
		     
		     wire buffer_drained;
		     assign buffer_drained = (cred_count_s == num_flit_buffers);
		     
		     wire tail_sent_s, tail_sent_q;
		     assign tail_sent_s
		       = (tail_sent_q | (flit_valid_in_qual & flit_tail_in)) &
			 ~buffer_drained;
		     c_dff
		       #(.width(1),
			 .reset_type(reset_type))
		     tail_sentq
		       (.clk(clk),
			.reset(reset),
			.d(tail_sent_s),
			.q(tail_sent_q));
		     
		     wire head_free_s, head_free_q;
		     assign head_free_s
		       = (head_free_q & ~vc_gnt) |
			 (credit & tail_sent_q & buffer_drained);
		     c_dff
		       #(.width(1),
			 .reset_type(reset_type),
			 .reset_value(1'b1))
		     head_freeq
		       (.clk(clk),
			.reset(reset),
			.d(head_free_s),
			.q(head_free_q));
		     
		     assign head_free_early = head_free_s;
		     
		     assign error_hct_ovc[ovc] = 1'b0;
		     
		  end
		else
		  begin
		     
		     wire [0:flit_buffer_idx_width-1] push_ptr_next, push_ptr_q;
		     c_incr
		       #(.width(flit_buffer_idx_width),
			 .min_value(0),
			 .max_value(num_flit_buffers-1))
		     push_ptr_incr
		       (.data_in(push_ptr_q),
			.data_out(push_ptr_next));
		     
		     wire [0:flit_buffer_idx_width-1] push_ptr_s;
		     assign push_ptr_s
		       = flit_valid_in_qual ? push_ptr_next : push_ptr_q;
		     c_dff
		       #(.width(flit_buffer_idx_width),
			 .reset_type(reset_type))
		     push_ptrq
		       (.clk(clk),
			.reset(reset),
			.d(push_ptr_s),
			.q(push_ptr_q));
		     
		     wire [0:flit_buffer_idx_width-1] pop_ptr_next, pop_ptr_q;
		     c_incr
		       #(.width(flit_buffer_idx_width),
			 .min_value(0),
			 .max_value(num_flit_buffers-1))
		     pop_ptr_incr
		       (.data_in(pop_ptr_q),
			.data_out(pop_ptr_next));
		     
		     wire [0:flit_buffer_idx_width-1] pop_ptr_s;
		     assign pop_ptr_s = credit ? pop_ptr_next : pop_ptr_q;
		     c_dff
		       #(.width(flit_buffer_idx_width),
			 .reset_type(reset_type))
		     pop_ptrq
		       (.clk(clk),
			.reset(reset),
			.d(pop_ptr_s),
			.q(pop_ptr_q));
		     
		     reg [0:num_flit_buffers-1]       tail_queue;
		     
		     always @(posedge clk)
		       if(flit_valid_in_qual)
			 tail_queue[push_ptr_q] <= flit_tail_in;
		     
		     wire 			      tail;
		     assign tail = tail_queue[pop_ptr_q];
		     
		     wire 			      head_credit;
		     assign head_credit = credit & tail;
		     
		     wire 			      head_debit;
		     assign head_debit = vc_gnt;
		     
		     // track header credits using stock credit tracker module
		     wire 			      head_free;
		     wire 			      error_hct;
		     c_credit_tracker
		       #(.num_credits(num_header_buffers),
			 .checker_enable(checker_enable),
			 .checker_capture_mode(checker_capture_mode),
			 .reset_type(reset_type))
		     hct
		       (.clk(clk),
			.reset(reset),
			.credit(head_credit),
			.debit(head_debit),
			.free(head_free),
			.free_early(head_free_early),
			.error(error_hct));
		     
		     assign error_hct_ovc[ovc] = error_hct;
		     
		  end
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // track number of flits that downstream buffer can still accept
	   //-------------------------------------------------------------------
	   
	   wire [0:cred_count_width-1] cred_count_q;
	   assign cred_count_s = (cred_count_q + credit - debit);
	   c_dff
	     #(.width(cred_count_width),
	       .reset_type(reset_type),
	       .reset_value(num_flit_buffers))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   assign next_cred_ovc[ovc] = |cred_count_s;
	   
	   wire [0:1] 		       error_cred;
	   assign error_cred = {(cred_count_q == num_flit_buffers) && credit,
				(cred_count_q == 0) && debit};
	   
	   assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
	   
	   
	   //-------------------------------------------------------------------
	   // generate flow control signals to input controller
	   //-------------------------------------------------------------------
	   
	   case(credit_handling_type)
	     
	     `CREDIT_HANDLING_TYPE_LEVEL:
	       begin
		  
		  // Having an additional register here is likely overkill, and
		  // increases the credit round-trip delay by a cycle, so we 
		  // just send out the value directly for now.
		  
		  /*
		  wire [0:cred_level_width-1] free_s, free_q;
		  assign free_s = (cred_count_s > max_cred_level) ?
				  max_cred_level :
				  cred_count_s[cred_count_width-
					       cred_level_width:
					       cred_count_width-1];
		  c_dff
		    #(.width(cred_level_width),
		      .reset_type(reset_type),
		      .reset_value(free_reset_value))
		  freeq
		    (.clk(clk),
		     .reset(reset),
		     .d(free_s),
		     .q(free_q));
		  
		  assign int_flow_ctrl_ovc[ovc*cred_level_width:
					   (ovc+1)*cred_level_width-1]
			   = free_q;
		  */
		  
		  assign int_flow_ctrl_ovc[ovc*cred_level_width:
					   (ovc+1)*cred_level_width-1]
			   = (cred_count_s > max_cred_level) ?
			     max_cred_level :
			     cred_count_s[cred_count_width-cred_level_width:
					  cred_count_width-1];
		  
	       end
	     
	     `CREDIT_HANDLING_TYPE_PUSH:
	       begin
		  
		  wire [0:cred_hold_width-1]  cred_hold_copy;
		  assign cred_hold_copy
		    = cred_count_s[(cred_count_width-cred_hold_width):
				   cred_count_width-1] - |cred_count_s/*1'b1*/;
		  
		  wire [0:cred_hold_width-1]  cred_hold_s, cred_hold_q;
		  assign cred_hold_s
		    = allocated_s ?
		      (cred_hold_q - (|cred_hold_q & ~credit)) :
		      cred_hold_copy;
		  c_dff
		    #(.width(cred_hold_width),
		      .reset_type(reset_type),
		      .reset_value(num_flit_buffers-1))
		  cred_holdq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_hold_s),
		     .q(cred_hold_q));
		  
		  // Having an additional register here is likely overkill, and
		  // increases the credit round-trip delay by a cycle, so we 
		  // just send out the value directly for now.
		  
		  /*
		  wire 			      cred_s, cred_q;
		  assign cred_s = |cred_hold_s | (credit & allocated_s);
		  c_dff
		    #(.width(1),
		      .reset_type(reset_type),
		      .reset_value(1))
		  credq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_s),
		     .q(cred_q));
		  
		  assign int_flow_ctrl_ovc[ovc] = cred_q;
		  */
		  
		  assign int_flow_ctrl_ovc[ovc]
			   = |cred_hold_s | (credit & allocated_s);
		  
	       end
	     
	   endcase
	   
	   
	   //-------------------------------------------------------------------
	   // keep track of whether current VC is available for allocation
	   //-------------------------------------------------------------------
	   
	   wire 			      elig_s, elig_q;
	   assign elig_s = ~allocated_s & head_free_early & next_cred_ovc[ovc];
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .reset_value(1'b1))
	   eligq
	     (.clk(clk),
	      .reset(reset),
	      .d(elig_s),
	      .q(elig_q));
	   
	   assign elig_ovc[ovc] = elig_q;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output staging
   //---------------------------------------------------------------------------
   
   wire [0:flit_ctrl_width-1] flit_ctrl_s, flit_ctrl_q;
   
   assign flit_ctrl_s[0] = flit_valid_in;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   if(track_vcs_at_output)
	     begin
		
		wire [0:vc_idx_width-1] match_ovc_enc;
		c_encoder
		  #(.num_ports(num_vcs))
		match_ovc_enc_enc
		  (.data_in(match_ovc),
		   .data_out(match_ovc_enc));
		
		assign flit_ctrl_s[1:1+vc_idx_width-1]
			 = sw_gnt_q ? 
			   match_ovc_enc : 
			   flit_ctrl_q[1:1+vc_idx_width-1];
		
	     end
	   else
	     assign flit_ctrl_s[1:1+vc_idx_width-1]
		      = sw_gnt_q ? 
			int_flit_ctrl_in[1:1+vc_idx_width-1] :
			flit_ctrl_q[1:1+vc_idx_width-1];
	   
	end
      
      assign flit_ctrl_s[1+vc_idx_width:flit_ctrl_width-1]
	       = sw_gnt_q ?
		 int_flit_ctrl_in[1+vc_idx_width:flit_ctrl_width-1] :
		 flit_ctrl_q[1+vc_idx_width:flit_ctrl_width-1];
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     wire flit_valid_s, flit_valid_q;
	     assign flit_valid_s = flit_ctrl_s[0];
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_validq
	       (.clk(clk),
		.reset(reset),
		.d(flit_valid_s),
		.q(flit_valid_q));
	     
	     assign flit_ctrl_q[0] = flit_valid_q;
	     
	     c_dff
	       #(.width(flit_ctrl_width-1),
		 .reset_type(/*reset_type*/ `RESET_TYPE_NONE),
		 .offset(1))
	     flit_ctrlq
	       (.clk(clk),
		.reset(reset),
		.d(flit_ctrl_s[1:flit_ctrl_width-1]),
		.q(flit_ctrl_q[1:flit_ctrl_width-1]));
	     
	  end
	
      endcase
      
   endgenerate
   
   assign flit_ctrl_out = flit_ctrl_q;
   
   wire [0:flit_data_width-1] 		  flit_data_s, flit_data_q;
   assign flit_data_s = sw_gnt_q ? flit_data_in : flit_data_q;
   c_dff
     #(.width(flit_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_dataq
     (.clk(clk),
      .reset(reset),
      .d(flit_data_s),
      .q(flit_data_q));
   
   assign flit_data_out = flit_data_q;
   
   
   //---------------------------------------------------------------------------
   // error checker logic
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*2-1] 		  errors_out_ovc;
   c_checker
     #(.num_errors(num_vcs*2),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(error_cred_ovc),
      .errors_out(errors_out_ovc));
   
   assign error = error_unmatched | (|error_hct_ovc) | (|errors_out_ovc);
   
endmodule
