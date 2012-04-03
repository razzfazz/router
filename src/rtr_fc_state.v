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
// VC flow control state tracking module
//==============================================================================

module rtr_fc_state
  (clk, reset, active, flit_valid, flit_sel_ovc, fc_event_valid, 
   fc_event_sel_ovc, fc_active, empty_ovc, almost_full_ovc, full_ovc, 
   full_prev_ovc, errors_ovc);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of VCs
   parameter num_vcs = 4;
   
   // total buffer size per port in flits
   parameter buffer_size = 16;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // make incoming flow control signals bypass the output VC state tracking 
   // logic
   parameter flow_ctrl_bypass = 1;
   
   // select buffer management scheme
   parameter mgmt_type = `FB_MGMT_TYPE_STATIC;
   
   // generate the almost_empty output early in the clock cycle
   parameter fast_almost_empty = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // number of buffer entries per VC
   localparam buffer_size_per_vc = buffer_size / num_vcs;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // clock enable signal
   input active;
   
   // a flit is begin sent
   input flit_valid;
   
   // VC to which the flit is sent
   input [0:num_vcs-1] flit_sel_ovc;
   
   // flow control event occurred
   input 	       fc_event_valid;

   // VC for which the flow control event occurred
   input [0:num_vcs-1] fc_event_sel_ovc;
   
   // activate flow control input logic
   output fc_active;
   wire   fc_active;
   
   // VC is empty
   output [0:num_vcs-1] empty_ovc;
   wire [0:num_vcs-1] 	empty_ovc;

   // VC has one slot left
   output [0:num_vcs-1] almost_full_ovc;
   wire [0:num_vcs-1] 	almost_full_ovc;
   
   // VC is full
   output [0:num_vcs-1] full_ovc;
   wire [0:num_vcs-1] 	full_ovc;
   
   // VC was full in previous cycle
   output [0:num_vcs-1] full_prev_ovc;
   wire [0:num_vcs-1] 	full_prev_ovc;
   
   // internal error condition detected
   output [0:num_vcs*2-1] errors_ovc;
   wire [0:num_vcs*2-1]   errors_ovc;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   generate
      
      case(flow_ctrl_type)
	
	`FLOW_CTRL_TYPE_CREDIT:
	  begin
	     
	     wire [0:num_vcs-1] ft_almost_empty_ovc;
	     wire [0:num_vcs-1] ft_empty_ovc;
	     wire [0:num_vcs-1] ft_almost_full_ovc;
	     wire [0:num_vcs-1] ft_full_ovc;
	     wire [0:num_vcs-1] ft_two_free_ovc;
	     wire [0:num_vcs*2-1] ft_errors_ovc;
	     
	     case(mgmt_type)
	       
	       `FB_MGMT_TYPE_STATIC:
		 begin
		    
		    c_samq_tracker
		      #(.num_queues(num_vcs),
			.num_slots_per_queue(buffer_size_per_vc),
			.fast_almost_empty(fast_almost_empty),
			.fast_two_free(1),
			.enable_bypass(0),
			.reset_type(reset_type))
		    samqt
		      (.clk(clk),
		       .reset(reset),
		       .active(active),
		       .push_valid(flit_valid),
		       .push_sel_qu(flit_sel_ovc),
		       .pop_valid(fc_event_valid),
		       .pop_sel_qu(fc_event_sel_ovc),
		       .almost_empty_qu(ft_almost_empty_ovc),
		       .empty_qu(ft_empty_ovc),
		       .almost_full_qu(ft_almost_full_ovc),
		       .full_qu(ft_full_ovc),
		       .two_free_qu(ft_two_free_ovc),
		       .errors_qu(ft_errors_ovc));
		    
		    assign fc_active = ~&ft_empty_ovc;
		    
		 end
	       
	     endcase
	     
	     wire [0:num_vcs-1] flit_valid_sel_ovc;
	     assign flit_valid_sel_ovc
	       = {num_vcs{flit_valid}} & flit_sel_ovc;
	     
	     wire [0:num_vcs-1] fc_event_valid_sel_ovc;
	     assign fc_event_valid_sel_ovc
	       = {num_vcs{fc_event_valid}} & fc_event_sel_ovc;
	     
	     if(flow_ctrl_bypass)
	       begin
		  assign empty_ovc
		    = (ft_empty_ovc | 
		       (ft_almost_empty_ovc & fc_event_valid_sel_ovc)) &
		      ~flit_valid_sel_ovc;
		  assign almost_full_ovc
		    = (ft_full_ovc & fc_event_valid_sel_ovc) | 
		      (ft_almost_full_ovc & 
		       (flit_valid_sel_ovc ~^ fc_event_valid_sel_ovc)) |
		      (ft_two_free_ovc & 
		       (flit_valid_sel_ovc & ~fc_event_valid_sel_ovc));
		  assign full_ovc
		    = (ft_full_ovc | 
		       (ft_almost_full_ovc & flit_valid_sel_ovc)) &
		      ~fc_event_valid_sel_ovc;
		  assign full_prev_ovc = ft_full_ovc & ~fc_event_valid_sel_ovc;
	       end
	     else
	       begin
		  assign empty_ovc = ft_empty_ovc & ~flit_valid_sel_ovc;
		  assign almost_full_ovc
		    = (flit_valid_sel_ovc & ft_two_free_ovc) |
		      (~flit_valid_sel_ovc & ft_almost_full_ovc);
		  assign full_ovc
		    = ft_full_ovc | (ft_almost_full_ovc & flit_valid_sel_ovc);
		  assign full_prev_ovc = ft_full_ovc;
	       end
	     
	     assign errors_ovc = ft_errors_ovc;
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
