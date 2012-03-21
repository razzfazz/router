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
// output port controller (tracks state of buffers in downstream router)
//==============================================================================

module vcr_ovc_ctrl
  (clk, reset, fc_event_valid, vc_active, vc_gnt, vc_sel_ip, vc_sel_ivc, 
   flit_active, flit_valid, flit_tail, flit_sel_ip, flit_sel_ivc, flit_sel, 
   elig, fc_active, almost_full, full, errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // number of message classes (e.g. request, reply)
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
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // make incoming flow control signals bypass the output VC state tracking 
   // logic
   parameter flow_ctrl_bypass = 1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   // message class to which the current VC belongs
   localparam message_class
     = (vc_id / num_vcs_per_class) / num_resource_classes;
   
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask = `ELIG_MASK_NONE;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // incoming flow control event
   input fc_event_valid;
   
   // VC allocation activity indicator
   input vc_active;
   
   // output VC was granted to an input VC
   input vc_gnt;
   
   // input port that the output VC was granted to
   input [0:num_ports-1] vc_sel_ip;
   
   // input VC that the output VC was granted to
   input [0:num_vcs-1] 	 vc_sel_ivc;
   
   // flit activity indicator
   input 		 flit_active;
   
   // incoming flit is valid
   input 		 flit_valid;
   
   // incoming flit is a tail flit
   input 		 flit_tail;
   
   //
   input [0:num_ports-1] flit_sel_ip;
   
   // which input VC does the incoming flit belong to?
   input [0:num_vcs-1] 	 flit_sel_ivc;
   
   // output VC is the owner of the incoming flit
   output 		 flit_sel;
   wire 		 flit_sel;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output 		 elig;
   wire 		 elig;
   
   // activity indicator for flow control receive logic
   output 		 fc_active;
   wire 		 fc_active;
   
   // VC has a single credit left
   output 		 almost_full;
   wire 		 almost_full;
   
   // VC has no credits left
   output 		 full;
   wire 		 full;
   
   // internal error condition detected
   output [0:2] 	 errors;
   wire [0:2] 		 errors;
   
   
   //---------------------------------------------------------------------------
   // decode control signals
   //---------------------------------------------------------------------------
   
   wire 		 flit_sent;
   assign flit_sent = flit_valid & flit_sel;
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently assigend to an input VC
   //---------------------------------------------------------------------------
   
   wire 		 alloc_active;
   assign alloc_active = vc_active | flit_active;
   
   wire 		 allocated;
   
   wire 		 allocated_s, allocated_q;
   assign allocated_s = vc_gnt | allocated;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .d(allocated_s),
      .q(allocated_q));
   
   assign allocated = allocated_q & ~(flit_sent & flit_tail);
   
   wire 		 error_stray_flit;
   assign error_stray_flit = flit_sent & ~allocated_q;
   
   wire [0:num_ports-1]  flit_sel_ip_s, flit_sel_ip_q;
   assign flit_sel_ip_s = vc_gnt ? vc_sel_ip : flit_sel_ip_q;
   c_dff
     #(.width(num_ports),
       .reset_type(reset_type))
   flit_sel_ipq
     (.clk(clk),
      .reset(1'b0),
      .active(vc_active),
      .d(flit_sel_ip_s),
      .q(flit_sel_ip_q));
   
   wire 		 port_match;
   assign port_match = (flit_sel_ip == flit_sel_ip_q);
   
   wire 		 vc_match;
   
   generate
      
      if(num_vcs == 1)
	assign vc_match = 1'b1;
      else if(num_vcs > 1)
	begin
	   
	   wire [0:num_vcs-1] flit_sel_ivc_s, flit_sel_ivc_q;
	   assign flit_sel_ivc_s = vc_gnt ? vc_sel_ivc : flit_sel_ivc_q;
	   c_dff
	     #(.width(num_vcs),
	       .reset_type(reset_type))
	   flit_sel_ivcq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(vc_active),
	      .d(flit_sel_ivc_s),
	      .q(flit_sel_ivc_q));
	   
	   assign vc_match = (flit_sel_ivc == flit_sel_ivc_q);
	   
	end
      
   endgenerate

   wire 		      cred_mask;
   
   assign flit_sel = allocated_q & port_match & vc_match & cred_mask;
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 		      flags_active;
   assign flags_active = flit_active | fc_event_valid;
   
   wire 		      fc_active;
   wire 		      fc_empty;
   wire 		      fc_full_prev;
   wire [0:1] 		      fc_errors;
   rtr_fc_state
     (.clk(clk),
      .reset(reset),
      .active(flags_active),
      .flit_sent(flit_sent),
      .fc_event_valid(fc_event_valid),
      .fc_active(fc_active),
      .empty(fc_empty),
      .almost_full(almost_full),
      .full(full),
      .full_prev(fc_full_prev),
      .errors(fc_errors));
   
   generate
      
      if(elig_mask != `ELIG_MASK_NONE)
	assign cred_mask = 1'b1;
      else
	assign cred_mask = ~fc_full_prev;
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // keep track of whether current VC is available for allocation
   //---------------------------------------------------------------------------
   
   generate
      
      case(elig_mask)

	`ELIG_MASK_NONE:
	  begin
	     assign elig = ~allocated;
	  end

	`ELIG_MASK_FULL:
	  begin
	     assign elig = ~allocated & ~full;
	  end

	`ELIG_MASK_USED:
	  begin
	     assign elig = ~allocated & fc_empty;
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // pragma translate_off
   
   always @(posedge clk)
     begin
	
	if(error_stray_flit)
	  $display("ERROR: Stray flit in module %m.");
	
     end
   
   // pragma translate_on
   
   assign errors[0] = error_stray_flit;
   assign errors[1:2] = fc_errors;
   
endmodule
