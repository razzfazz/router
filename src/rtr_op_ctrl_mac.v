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
// output port controller
//==============================================================================

module rtr_op_ctrl_mac
  (clk, reset, flow_ctrl_in, flit_valid_in, flit_head_in, flit_tail_in, 
   flit_sel_in_ovc, flit_data_in, channel_out, elig_out_ovc, empty_out_ovc, 
   almost_full_out_ovc, full_out_ovc, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // make incoming flow control signals bypass the output VC state tracking 
   // logic
   parameter flow_ctrl_bypass = 1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // incoming flit is valid
   input 		       flit_valid_in;
   
   // incoming flit is a head flit
   input 		       flit_head_in;
   
   // incoming flit is a tail flit
   input 		       flit_tail_in;
   
   // indicate which VC the incoming flit belongs to
   input [0:num_vcs-1] 	       flit_sel_in_ovc;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing flit control signals
   output [0:channel_width-1]  channel_out;
   wire [0:channel_width-1]    channel_out;
   
   // which output VCs are eligible for VC allocation?
   output [0:num_vcs-1]        elig_out_ovc;
   wire [0:num_vcs-1] 	       elig_out_ovc;
   
   // with output VCs contain no flits?
   output [0:num_vcs-1]        empty_out_ovc;
   wire [0:num_vcs-1] 	       empty_out_ovc;
   
   // which output VC have only a single credit left?
   output [0:num_vcs-1]        almost_full_out_ovc;
   wire [0:num_vcs-1] 	       almost_full_out_ovc;
   
   // which output VCs have no credits left?
   output [0:num_vcs-1]        full_out_ovc;
   wire [0:num_vcs-1] 	       full_out_ovc;
   
   // internal error condition detected
   output 		       error;
   wire 		       error;
   
   
   //---------------------------------------------------------------------------
   // flow control input staging
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	       ovs_empty_ovc;
   
   wire 		       flow_ctrl_active;
   assign flow_ctrl_active = ~&ovs_empty_ovc;
   
   wire 		       fc_event_valid;
   wire [0:num_vcs-1] 	       fc_event_sel_ovc;
   rtr_flow_ctrl_input
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fci
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .flow_ctrl_in(flow_ctrl_in),
      .fc_event_valid_out(fc_event_valid),
      .fc_event_sel_out_ovc(fc_event_sel_ovc));
   
   wire [0:num_vcs-1] 	       fc_event_valid_ovc;
   assign fc_event_valid_ovc = {num_vcs{fc_event_valid}} & fc_event_sel_ovc;
   
   
   //---------------------------------------------------------------------------
   // output staging
   //---------------------------------------------------------------------------
   
   wire 		       channel_active;
   assign channel_active = flit_valid_in;
   
   // NOTE: For head flits that fail to acquire a VC, 'flit_valid_in' will be
   // one, but 'flit_sel_in_ovc' will be all-zeroes. As no flit should be sent
   // out in this case, we must qualify accordingly.
   
   wire 		       flit_valid;
   assign flit_valid = flit_valid_in & (|flit_sel_in_ovc);
   
   rtr_channel_output
     #(.num_vcs(num_vcs),
       .packet_format(packet_format),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   cho
     (.clk(clk),
      .reset(reset),
      .active(channel_active),
      .flit_valid_in(flit_valid),
      .flit_head_in(flit_head_in),
      .flit_tail_in(flit_tail_in),
      .flit_data_in(flit_data_in),
      .flit_sel_in_ovc(flit_sel_in_ovc),
      .channel_out(channel_out));
   
   
   //---------------------------------------------------------------------------
   // VC state tracking
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	       flit_valid_in_ovc;
   assign flit_valid_in_ovc = {num_vcs{flit_valid_in}} & flit_sel_in_ovc;
   
   wire 		       ovs_active;
   assign ovs_active = flit_valid_in | fc_event_valid;
   
   wire [0:num_vcs*2-1]        ovs_errors_ovc;
   
   genvar 		       ovc;
   
   generate
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire flit_valid_in;
	   assign flit_valid_in = flit_valid_in_ovc[ovc];
	   
	   wire fc_event_valid;
	   assign fc_event_valid = fc_event_valid_ovc[ovc];
	   
	   wire ovs_elig;
	   wire ovs_almost_empty;
	   wire ovs_empty;
	   wire ovs_almost_full;
	   wire ovs_full;
	   wire [0:flit_count_width-1] ovs_free;
	   wire [0:1] 		       ovs_errors;
	   rtr_vc_state
	     #(.num_flits_per_vc(num_flits_per_vc),
	       .flow_ctrl_type(flow_ctrl_type),
	       .reset_type(reset_type))
	   ovs
	     (.clk(clk),
	      .reset(reset),
	      .active(ovs_active),
	      .flit_sent(flit_valid_in),
	      .flit_tail(flit_tail_in),
	      .fc_event_valid(fc_event_valid),
	      .elig(ovs_elig),
	      .almost_empty(ovs_almost_empty),
	      .empty(ovs_empty),
	      .almost_full(ovs_almost_full),
	      .full(ovs_full),
	      .free(ovs_free),
	      .errors(ovs_errors));
	   
	   wire 		       elig_out;
	   assign elig_out = flit_valid_in ? flit_tail_in : ovs_elig;
	   
	   wire 		       empty_out;
	   
	   if(flow_ctrl_bypass)
	     assign empty_out
	       = (ovs_empty | (ovs_almost_empty & fc_event_valid)) &
		 ~flit_valid_in;
	   else
	     assign empty_out = ovs_empty & ~flit_valid_in;
	   
	   wire 		       two_credits_left_s, two_credits_left_q;
	   
	   if(num_flits_per_vc == 2)
	     assign two_credits_left_s
	       = (ovs_almost_full & ~flit_valid_in & fc_event_valid) | 
		 (two_credits_left_q & (flit_valid_in ~^ fc_event_valid));
	   else if(num_flits_per_vc == 3)
	     assign two_credits_left_s
	       = (ovs_almost_full & ~flit_valid_in & fc_event_valid) | 
		 (two_credits_left_q & (flit_valid_in ~^ fc_event_valid)) |
		 (ovs_empty & flit_valid_in);
	   else if(num_flits_per_vc == 4)
	     assign two_credits_left_s
	       = (ovs_almost_full & ~flit_valid_in & fc_event_valid) | 
		 (two_credits_left_q & (flit_valid_in ~^ fc_event_valid)) |
		 (ovs_almost_empty & flit_valid_in & ~fc_event_valid);
	   else if(num_flits_per_vc > 4)
	     assign two_credits_left_s
	       = (ovs_almost_full & ~flit_valid_in & fc_event_valid) | 
		 (two_credits_left_q & (flit_valid_in ~^ fc_event_valid)) |
		 (~|ovs_free[0:flit_count_width-3] &
		  &ovs_free[flit_count_width-2:flit_count_width-1] &
		  flit_valid_in & ~fc_event_valid);
	   
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .reset_value((num_flits_per_vc == 2) ? 1'b1 : 1'b0))
	   two_credits_leftq
	     (.clk(clk),
	      .reset(reset),
	      .active(ovs_active),
	      .d(two_credits_left_s),
	      .q(two_credits_left_q));
	   
	   wire 		       almost_full_out;

	   if(flow_ctrl_bypass)
	     assign almost_full_out
	       = (ovs_full & fc_event_valid) | 
		 (ovs_almost_full & (flit_valid_in ~^ fc_event_valid)) |
		 (two_credits_left_q & flit_valid_in & ~fc_event_valid);
	   else
	     assign almost_full_out
	       = flit_valid_in ? two_credits_left_q : ovs_almost_full;
	   
	   wire 		       full_out;
	   
	   if(flow_ctrl_bypass)
	     assign full_out = (ovs_full | (ovs_almost_full & flit_valid_in)) &
			       ~fc_event_valid;
	   else
	     assign full_out = ovs_full | (ovs_almost_full & flit_valid_in);
	   
	   assign elig_out_ovc[ovc] = elig_out;
	   assign empty_out_ovc[ovc] = empty_out;
	   assign almost_full_out_ovc[ovc] = almost_full_out;
	   assign full_out_ovc[ovc] = full_out;	   
	   assign ovs_empty_ovc[ovc] = ovs_empty;
	   assign ovs_errors_ovc[ovc*2:(ovc+1)*2-1] = ovs_errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:num_vcs*2-1] errors_s, errors_q;
	   assign errors_s = ovs_errors_ovc;
	   c_err_rpt
	     #(.num_errors(num_vcs*2),
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
