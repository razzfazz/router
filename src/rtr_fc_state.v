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
      
      case(mgmt_type)
	
	`FB_MGMT_TYPE_STATIC:
	  begin
	     
	     wire [0:num_vcs-1] fc_active_ovc;
	     assign fc_active = |fc_active_ovc;
	     
	     genvar 		ovc;
	     
	     for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	       begin:ovcs
		  
		  wire fc_active;
		  wire empty;
		  wire almost_full;
		  wire full;
		  wire full_prev;
		  
		  wire error_ft_underflow;
		  wire error_ft_overflow;
		  
		  case(flow_ctrl_type)
		    
		    `FLOW_CTRL_TYPE_CREDIT:
		      begin
			 
			 //-----------------------------------------------------
			 // track number of flits the VC can still accept
			 //-----------------------------------------------------
			 
			 wire flit_sel;
			 assign flit_sel = flit_sel_ovc[ovc];
			 
			 wire flit_valid_sel;
			 assign flit_valid_sel = flit_valid & flit_sel;
			 
			 wire fc_event_sel;
			 assign fc_event_sel = fc_event_sel_ovc[ovc];
			 
			 wire fc_event_valid_sel;
			 assign fc_event_valid_sel
			   = fc_event_valid & fc_event_sel;
			 
			 wire ft_almost_empty;
			 wire ft_empty;
			 wire ft_almost_full;
			 wire ft_full;
			 wire ft_two_free;
			 wire [0:1] 		     ft_errors;
			 c_fifo_tracker
			   #(.depth(buffer_size_per_vc),
			     .fast_almost_empty(fast_almost_empty),
			     .fast_two_free(1),
			     .enable_bypass(0),
			     .reset_type(reset_type))
			 ft
			   (.clk(clk),
			    .reset(reset),
			    .active(active),
			    .push(flit_valid_sel),
			    .pop(fc_event_valid_sel),
			    .almost_empty(ft_almost_empty),
			    .empty(ft_empty),
			    .almost_full(ft_almost_full),
			    .full(ft_full),
			    .two_free(ft_two_free),
			    .errors(ft_errors));
			 
			 assign fc_active = ~ft_empty;
			 
			 if(flow_ctrl_bypass)
			   begin
			      assign empty
				= (ft_empty | 
				   (ft_almost_empty & fc_event_valid_sel)) &
				  ~flit_valid_sel;
			      assign almost_full
				= (ft_full & fc_event_valid_sel) | 
				  (ft_almost_full & 
				   (flit_valid_sel ~^ fc_event_valid_sel)) |
				  (ft_two_free & 
				   (flit_valid_sel & ~fc_event_valid_sel));
			      assign full
				= (ft_full | 
				   (ft_almost_full & flit_valid_sel)) &
				  ~fc_event_valid_sel;
			      assign full_prev = ft_full & ~fc_event_valid_sel;
			   end
			 else
			   begin
			      assign empty = ft_empty & ~flit_valid_sel;
			      assign almost_full = flit_valid_sel ? 
						   ft_two_free : 
						   ft_almost_full;
			      assign full = ft_full | 
					    (ft_almost_full & flit_valid_sel);
			      assign full_prev = ft_full;
			   end
			 
			 assign error_ft_underflow = ft_errors[0];
			 assign error_ft_overflow = ft_errors[1];
	     		 
		      end
		    
		  endcase
		  
		  assign fc_active_ovc[ovc] = fc_active;
		  assign empty_ovc[ovc] = empty;
		  assign almost_full_ovc[ovc] = almost_full;
		  assign full_ovc[ovc] = full;
		  assign full_prev_ovc[ovc] = full_prev;
		  
		  
		  //------------------------------------------------------------
		  // error checking
		  //------------------------------------------------------------
		  
		  // synopsys translate_off
		  
		  always @(posedge clk)
		    begin
		       
		       if(error_ft_underflow)
			 $display({"ERROR: Flow control state tracker ", 
				   "underflow in module %m, VC %d."}, ovc);
		       
		       if(error_ft_overflow)
			 $display({"ERROR: Flow control state tracker ",
				   "overflow in module %m, VC %d."}, ovc);
		       
		    end
		  
		  // synopsys translate_on
		  
		  wire [0:1] errors;
		  assign errors[0] = error_ft_underflow;
		  assign errors[1] = error_ft_overflow;
		  
		  assign errors_ovc[ovc*2:(ovc+1)*2-1] = errors;
		  
	       end
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
