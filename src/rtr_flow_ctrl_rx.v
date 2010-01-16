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



// flow control receiver
module rtr_flow_ctrl_rx
  (clk, reset, active, flow_ctrl, valid, sel_ivc);
   
   
`include "c_functions.v"
`include "c_constants.v"
   
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of VCs available for each class
   parameter num_vcs_per_class = 1;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? 
       (1 + vc_idx_width) : 
       -1;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   input active;
   
   
   // downstream flow control
   input [0:flow_ctrl_width-1] flow_ctrl;
   
   // a flit or credit was received
   output valid;
   wire valid;
   
   // indicate which VC the flit or credit belongs to
   output [0:num_vcs-1] sel_ivc;
   wire [0:num_vcs-1] sel_ivc;
   
   
   //---------------------------------------------------------------------------
   // downstream flow control implementations
   //---------------------------------------------------------------------------
   
   generate
      
      case(flow_ctrl_type)
	
	//----------------------------------------------------------------------
	// credit-based flow control
	//----------------------------------------------------------------------
	
	`FLOW_CTRL_TYPE_CREDIT:
	  begin
	     
	     //-----------------------------------------------------------------
	     // decode incoming downstream flow control signals
	     //-----------------------------------------------------------------
	     
	     wire valid_s, valid_q;
	     assign valid_s = flow_ctrl[0];
	     c_dff
	       #(.width(1),
		 .reset_type(reset_type))
	     validq
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.d(valid_s),
		.q(valid_q));
	     
	     assign valid = valid_q;
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] vc_s, vc_q;
		  assign vc_s = flow_ctrl[1:1+vc_idx_width-1];
		  c_dff
		    #(.width(vc_idx_width),
		      .reset_type(`RESET_TYPE_NONE))
		  vcq
		    (.clk(clk),
		     .reset(1'b0),
		     .active(active),
		     .d(vc_s),
		     .q(vc_q));
		  
		  c_decoder
		    #(.num_ports(num_vcs))
		  sel_ivc_dec
		    (.data_in(vc_q),
		     .data_out(sel_ivc));
		  
	       end
	     else
	       assign sel_ivc = 1'b1;
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
