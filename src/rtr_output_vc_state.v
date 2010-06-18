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



// output-side VC state tracking module
module rtr_output_vc_state
  (clk, reset, active, allocate, deallocate, allocated, allocated_vc);
   
`include "c_functions.v"
`include "c_constants.v"
   
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
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_CREDIT;
   
   // width of flit control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == FLOW_CTRL_TYPE_CREDIT) ? 
       (1 + vc_idx_width) : 
       -1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // upstream flow control
   output [0:flow_ctrl_width-1] ds_flow_ctrl_out;
   wire [0:flow_ctrl_width-1] ds_flow_ctrl_out;
   
   // downstream flow control
   input [0:flow_ctrl_width-1] us_flow_ctrl_in;
   
   // a flit is ready to be sent
   input flit_valid_in;
   
   // indicate which VC the outgoing flit belongs to
   input [0:num_vcs-1] flit_sel_in_ivc;
   
   // a flit was sent
   output flit_sent_out;
   wire 		      flit_sent_out;
   
   // indicate which VC the sent flit belonged to
   output [0:num_vcs-1] flit_sel_out_ivc;
   wire [0:num_vcs-1] 	      flit_sel_out_ivc;
   
   
   generate
      
      case(flow_ctrl_type)
	
	//----------------------------------------------------------------------
	// credit-based flow control
	//----------------------------------------------------------------------
	
	`FLOW_CTRL_TYPE_CREDIT:
	  begin
	     
	     //-----------------------------------------------------------------
	     // generate outgoing downstream flow control signals
	     //-----------------------------------------------------------------
	     
	     assign ds_flow_ctrl_out[0] = flit_valid_in;
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] flit_vc;
		  c_encode
		    #(.num_ports(num_vcs))
		  flit_vc_enc
		    (.data_in(flit_sel_in_ivc),
		     .data_out(flit_vc));
		  
		  assign ds_flow_ctrl_out[1:1+vc_idx_width-1] = flit_vc;
		  
	       end
	     
	     //-----------------------------------------------------------------
	     // decode incoming upstream flow control signals
	     //-----------------------------------------------------------------
	     
	     assign flit_sent_out = us_flow_ctrl_in[0];
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] cred_vc;
		  assign cred_vc = us_flow_ctrl_in[1:1+vc_idx_width-1];
		  
		  c_decode
		    #(.num_ports(num_vcs))
		  flit_sel_out_ivc_dec
		    (.data_in(cred_vc),
		     .data_out(flit_sel_out_ivc));
		  
	       end
	     else
	       assign flit_sel_out_ivc = 1'b1;
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
