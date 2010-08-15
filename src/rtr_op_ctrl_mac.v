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
  (clk, reset, empty_in, flow_ctrl_in, flit_valid_in, flit_head_in, 
   flit_tail_in, flit_sel_in_ovc, flit_data_in, channel_out, 
   fc_event_valid_out, fc_event_sel_out_ovc);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
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
   
   // all VCs empty?
   input empty_in;
   
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
   
   // flow control event occured
   output 		       fc_event_valid_out;
   wire 		       fc_event_valid_out;
   
   // VC to which flow control event belongs
   output [0:num_vcs-1]        fc_event_sel_out_ovc;
   wire [0:num_vcs-1] 	       fc_event_sel_out_ovc;
   
   
   //---------------------------------------------------------------------------
   // flow control input staging
   //---------------------------------------------------------------------------
   
   wire 		       flow_ctrl_active;
   assign flow_ctrl_active = ~empty_in;
   
   rtr_flow_ctrl_input
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fci
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .flow_ctrl_in(flow_ctrl_in),
      .fc_event_valid_out(fc_event_valid_out),
      .fc_event_sel_out_ovc(fc_event_sel_out_ovc));
   
   
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
   
endmodule
