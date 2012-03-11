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
   xbr_ctrl_ip, flit_valid, flit_tail, flit_sel_ivc, flit_sel, elig, empty, 
   free, errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // number of VCs
   parameter num_vcs = 4;
   
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
   input [0:num_vcs-1] vc_sel_ivc;
   
   // was this output granted to an input port?
   input [0:num_ports-1] xbr_ctrl_ip;
   
   // incoming flit is valid
   input flit_valid;
   
   // incoming flit is a tail flit
   input flit_tail;
   
   // which input VC does the incoming flit belong to?
   input [0:num_vcs-1] flit_sel_ivc;
   
   // output VC is the owner of the incoming flit
   output flit_sel;
   wire   flit_sel;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output elig;
   wire   elig;
   
   // no buffer slots in output VC are in use (i.e., all credits are present)
   output empty;
   wire   empty;
   
   // internal flow control signalling from output controller to input 
   // controllers
   output [0:1] free;
   wire [0:1] 	free;
   
   // internal error condition detected
   output [0:2] errors;
   wire [0:2] 	errors;
   
   
   //---------------------------------------------------------------------------
   // decode control signals
   //---------------------------------------------------------------------------
   
   wire 	credit;
   assign credit = fc_event_valid;
   
   wire 	flit_valid_qual;
   assign flit_valid_qual = flit_valid & flit_sel;
   
   wire 	debit;
   assign debit = flit_valid_qual;
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently assigend to an input VC
   //---------------------------------------------------------------------------
   
   wire 	alloc_active;
   assign alloc_active = vc_active | (|xbr_ctrl_ip);
   
   wire 	allocated_s, allocated_q;
   assign allocated_s = vc_gnt | (allocated_q & ~(flit_valid_qual & flit_tail));
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(alloc_active),
      .d(allocated_s),
      .q(allocated_q));
   
   wire 	error_stray_flit;
   assign error_stray_flit = flit_valid_qual & ~allocated_q;
   
   wire [0:num_ports-1] flit_sel_ip_s, flit_sel_ip_q;
   assign flit_sel_ip_s = vc_gnt ? vc_sel_ip : flit_sel_ip_q;
   c_dff
     #(.width(num_ports),
       .reset_type(reset_type))
   flit_sel_ipq
     (.clk(clk),
      .reset(1'b0),
      .active(alloc_active),
      .d(flit_sel_ip_s),
      .q(flit_sel_ip_q));

   wire 		port_match;
   assign port_match = (xbr_ctrl_ip == flit_sel_ip_q);
   
   wire 		vc_match;
   
   generate
      
      if(num_vcs == 1)
	assign vc_match = 1'b1;
      else if(num_vcs > 1)
	begin
	   
	   wire [0:num_vcs-1] 	flit_sel_ivc_s, flit_sel_ivc_q;
	   assign flit_sel_ivc_s = vc_gnt ? vc_sel_ivc : flit_sel_ivc_q;
	   c_dff
	     #(.width(num_vcs),
	       .reset_type(reset_type))
	   flit_sel_ivcq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(alloc_active),
	      .d(flit_sel_ivc_s),
	      .q(flit_sel_ivc_q));
	   
	   assign vc_match = (flit_sel_ivc == flit_sel_ivc_q);
	   
	end
      
   endgenerate
   
   assign flit_sel = allocated_q & port_match & vc_match;
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 	flags_active;
   assign flags_active = alloc_active | credit;
   
   wire 	ft_almost_empty;
   wire 	ft_empty;
   wire 	ft_almost_full;
   wire 	ft_full;
   wire [0:flit_count_width-1] ft_free;
   wire [0:1] 		       ft_errors;
   c_fifo_tracker
     #(.depth(num_flits_per_vc),
       .reset_type(reset_type))
   ft
     (.clk(clk),
      .reset(reset),
      .active(flags_active),
      .push(debit),
      .pop(credit),
      .almost_empty(ft_almost_empty),
      .empty(ft_empty),
      .almost_full(ft_almost_full),
      .full(ft_full),
      .free(ft_free),
      .errors(ft_errors));
   
   assign empty = ft_empty;
   
   wire 		       error_ct_underflow;
   assign error_ct_underflow = ft_errors[0];
   
   wire 		       error_ct_overflow;
   assign error_ct_overflow = ft_errors[1];
   
   
   //---------------------------------------------------------------------------
   // generate flow control signals to input controller
   //---------------------------------------------------------------------------
   
   // NOTE: The debit input to this module is driven by the input VC controller.
   // Consequently, the debit signal is already readily available at the input 
   // controller, and we can simply pass the current credit level, incremented 
   // by one if a credit was just received, from output to input controller, 
   // rather having the debit signal effectively go from input to output 
   // controller and back. Note that whenever an output VC is allocated to an 
   // input VC, no flit can have been sent in the current cycle, as in order 
   // for VC allocation to succeed, the output VC must be eligible for 
   // allocation in the current cycle, and thus cannot be assigned to another 
   // input VC.
   
   generate
      
      if(num_flits_per_vc == 2)
	begin
	   
	   // in this case, we can only have zero, one or two credits available,
	   // so the "3 or more" encoding cannot occur
	   
	   if(flow_ctrl_bypass)
	     begin
		assign free[0] = ~ft_full & (~ft_almost_full | credit);
		assign free[1] = ft_almost_full | (ft_full & credit);
	     end
	   else
	     begin
		assign free[0] = ~ft_full & ~ft_almost_full;
		assign free[1] = ft_almost_full;
	     end
	   
	end
      else if(num_flits_per_vc == 3)
	begin
	   
	   // here, we can have at most three credits; consequently, we can 
	   // simply add the incoming credit (if any) to the current credit 
	   // count without having to worry about overflow
	   
	   if(flow_ctrl_bypass)
	     assign free = ft_free + credit;
	   else
	     assign free = ft_free;
	   
	end
      else if(num_flits_per_vc > 3)
	begin
	   
	   // in the general case, the two-bit addition may overflow, or the 
	   // credit count may have non-zero higher-order bits; in both cases, 
	   // we must saturate the two-bit result to 2'b11
	   
	   wire [0:1] sum;
	   wire       cap;
	   
	   if(flow_ctrl_bypass)
	     begin
		assign sum
		  = ft_free[flit_count_width-2:flit_count_width-1] + credit;
		assign cap = |ft_free[0:flit_count_width-3] | 
			     &ft_free[flit_count_width-2:flit_count_width-1];
	     end
	   else
	     begin
		assign sum = ft_free[flit_count_width-2:flit_count_width-1];
		assign cap = |ft_free[0:flit_count_width-3];
	     end
	   
	   assign free = sum | {2{cap}};
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // keep track of whether current VC is available for allocation
   //---------------------------------------------------------------------------
   
   generate
      
      case(elig_mask)

	`ELIG_MASK_NONE:
	  begin
	     assign elig = ~allocated_q;
	  end

	`ELIG_MASK_FULL:
	  begin
	     if(flow_ctrl_bypass)
	       assign elig = ~allocated_q & (~ft_full | credit);
	     else
	       assign elig = ~allocated_q & ~ft_full;
	  end

	`ELIG_MASK_USED:
	  begin
	     assign elig = ~allocated_q & ft_empty;
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
	
	if(error_ct_underflow)
	  $display("ERROR: Credit tracker underflow in module %m.");
	
	if(error_ct_overflow)
	  $display("ERROR: Credit tracker overflow in module %m.");
	
     end
   
   // pragma translate_on
   
   assign errors[0] = error_stray_flit;
   assign errors[1] = error_ct_underflow;
   assign errors[2] = error_ct_overflow;
   
endmodule
