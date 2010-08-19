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
// output port controller (tracks state of buffers in downstream router)
//==============================================================================

module vcr_op_ctrl_mac
  (clk, reset, flow_ctrl_in, vc_req_ovc, vc_gnt_ovc, vc_gnt_ovc_ip, 
   vc_gnt_ovc_ivc, xbr_ctrl_ip, int_flit_ctrl_in, flit_data_in, channel_out, 
   int_flow_ctrl_ovc, elig_ovc, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
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
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // select whether VCs must have credits available in order to be considered 
   // for VC allocation
   parameter vc_alloc_requires_credit = 0;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select implementation variant for tail sent tracker register file
   parameter tst_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width = 1 + vc_idx_width + 1 + 1;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_LEVEL) ? 2 :
       (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_PUSH) ? 1 :
       -1;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // output VC was requested by an input VC
   input [0:num_vcs-1] 	       vc_req_ovc;
   
   // output VC was granted to an input VC
   input [0:num_vcs-1] 	       vc_gnt_ovc;
   
   // input port that each output VC was granted to
   input [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
   
   // input VC that each output VC was granted to
   input [0:num_vcs*num_vcs-1] 	 vc_gnt_ovc_ivc;
   
   // was this output granted to an input port?
   input [0:num_ports-1] 	 xbr_ctrl_ip;
   
   // incoming flit control signals
   input [0:int_flit_ctrl_width-1] int_flit_ctrl_in;
   
   // incoming flit data
   input [0:flit_data_width-1] 	   flit_data_in;
   
   // outgoing flit control signals
   output [0:channel_width-1] 	   channel_out;
   wire [0:channel_width-1] 	   channel_out;
   
   // internal flow control signals to input controllers
   output [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
   wire [0:num_vcs*int_flow_ctrl_width-1]   int_flow_ctrl_ovc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output [0:num_vcs-1] 		    elig_ovc;
   wire [0:num_vcs-1] 			    elig_ovc;
   
   // internal error condition detected
   output 				    error;
   wire 				    error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 			    empty_ovc;
   
   wire 				    flow_ctrl_active;
   assign flow_ctrl_active = ~&empty_ovc;
   
   wire 				    cred_valid;
   wire [0:num_vcs-1] 			    cred_sel_ovc;
   rtr_flow_ctrl_input
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fci
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .flow_ctrl_in(flow_ctrl_in),
      .fc_event_valid_out(cred_valid),
      .fc_event_sel_out_ovc(cred_sel_ovc));
   
   wire [0:num_vcs-1] 			    cred_valid_ovc;
   assign cred_valid_ovc = {num_vcs{cred_valid}} & cred_sel_ovc;
   
   
   //---------------------------------------------------------------------------
   // output VC control logic
   //---------------------------------------------------------------------------
   
   wire 				    flit_valid_in;
   assign flit_valid_in = int_flit_ctrl_in[0] & |xbr_ctrl_ip;
   
   wire 				    flit_head_in;
   assign flit_head_in = int_flit_ctrl_in[1+vc_idx_width];
   
   wire 				    flit_tail_in;
   assign flit_tail_in = int_flit_ctrl_in[1+vc_idx_width+1];
   
   wire [0:num_vcs-1] 			    match_ovc;
   
   wire 				    error_unmatched;
   assign error_unmatched = flit_valid_in & ~|match_ovc;
   
   wire [0:num_vcs-1] 			    next_cred_ovc;
   wire [0:num_vcs*2-1] 		    ovcc_errors_ovc;
   
   generate
      
      genvar 				    ovc;
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire vc_req;
	   assign vc_req = vc_req_ovc[ovc];
	   
	   wire vc_gnt;
	   assign vc_gnt = vc_gnt_ovc[ovc];
	   
	   wire [0:num_ports-1] vc_gnt_ip;
	   assign vc_gnt_ip = vc_gnt_ovc_ip[ovc*num_ports:(ovc+1)*num_ports-1];
	   
	   wire [0:num_vcs-1] 	vc_gnt_ivc;
	   assign vc_gnt_ivc = vc_gnt_ovc_ivc[ovc*num_vcs:(ovc+1)*num_vcs-1];
	   
	   wire 		cred_valid;
	   assign cred_valid = cred_valid_ovc[ovc];
	   
	   wire 		match;
	   wire 		elig;
	   wire 		empty;
	   wire [0:int_flow_ctrl_width-1] int_flow_ctrl;
	   wire [0:1] 			  ovcc_errors;
	   vcr_ovc_ctrl
	     #(.num_flits_per_vc(num_flits_per_vc),
	       .num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .packet_format(packet_format),
	       .vc_id(ovc),
	       .vc_alloc_requires_credit(vc_alloc_requires_credit),
	       .track_vcs_at_output(track_vcs_at_output),
	       .int_flow_ctrl_type(int_flow_ctrl_type),
	       .tst_regfile_type(tst_regfile_type),
	       .reset_type(reset_type))
	   ovcc
	     (.clk(clk),
	      .reset(reset),
	      .fc_event_valid(cred_valid),
	      .vc_req(vc_req),
	      .vc_gnt(vc_gnt),
	      .vc_gnt_ip(vc_gnt_ip),
	      .vc_gnt_ivc(vc_gnt_ivc),
	      .xbr_ctrl_ip(xbr_ctrl_ip),
	      .int_flit_ctrl(int_flit_ctrl_in),
	      .match(match),
	      .elig(elig),
	      .empty(empty),
	      .int_flow_ctrl(int_flow_ctrl),
	      .errors(ovcc_errors));

	   assign match_ovc[ovc] = match;
	   assign empty_ovc[ovc] = empty;
	   assign elig_ovc[ovc] = elig;
	   assign int_flow_ctrl_ovc[ovc*int_flow_ctrl_width:
				    (ovc+1)*int_flow_ctrl_width-1]
		    = int_flow_ctrl;
	   assign ovcc_errors_ovc[ovc*2:(ovc+1)*2-1] = ovcc_errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output staging
   //---------------------------------------------------------------------------
   
   wire 				  flit_out_active;
   assign flit_out_active = |xbr_ctrl_ip;
   
   wire [0:num_vcs-1] 			  flit_sel_in_ovc;
   
   generate
      
      if(num_vcs > 1)
	begin
	   
	   if(track_vcs_at_output)
	     assign flit_sel_in_ovc = match_ovc;
	   else
	     begin
		
		wire [0:vc_idx_width-1] flit_vc_in;
		assign flit_vc_in = int_flit_ctrl_in[1:1+vc_idx_width-1];
		
		c_decode
		  #(.num_ports(num_vcs))
		flit_sel_in_ovc_dec
		  (.data_in(flit_vc_in),
		   .data_out(flit_sel_in_ovc));
		
	     end
	   
	end
      else
	assign flit_sel_in_ovc = 1'b1;
      
   endgenerate
   
   rtr_channel_output
     #(.num_vcs(num_vcs),
       .packet_format(packet_format),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   cho
     (.clk(clk),
      .reset(reset),
      .active(flit_out_active),
      .flit_valid_in(flit_valid_in),
      .flit_head_in(flit_head_in),
      .flit_tail_in(flit_tail_in),
      .flit_data_in(flit_data_in),
      .flit_sel_in_ovc(flit_sel_in_ovc),
      .channel_out(channel_out));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	
	if(error_unmatched)
	  $display("ERROR: Unmatched flit in module %m.");
	
     end
   
   // synopsys translate_on
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:1+num_vcs*2-1] errors_s, errors_q;
	   assign errors_s = {error_unmatched, ovcc_errors_ovc};
	   c_err_rpt
	     #(.num_errors(1+num_vcs*2),
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
