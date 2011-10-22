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
// multi-queue buffer controller
//==============================================================================

module rtr_flit_buffer
  (clk, reset, push_valid, push_ivc, pop_valid, pop_ivc, push_data, pop_data, 
   peek_data, almost_empty_ivc, empty_ivc, full, errors);
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of VCs
   parameter num_vcs = 4;
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of buffers
   localparam num_buffers = num_vcs * num_flits_per_vc;
   
   // required address size for selecting flit in a VC
   localparam vc_addr_width = clogb(num_flits_per_vc);
   
   // required address size for selecting buffer entry
   localparam addr_width = clogb(num_buffers);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;

   // insert data
   input push_valid;
   input [0:num_vcs-1] push_ivc;
   
   // retrieve data
   input 		  pop_valid;
   input [0:num_vcs-1] pop_ivc;
   
   // buffer fill state flags
   output [0:num_vcs-1] almost_empty_ivc;
   wire [0:num_vcs-1]   almost_empty_ivc;
   output [0:num_vcs-1] empty_ivc;
   wire [0:num_vcs-1]   empty_ivc;
   output 		   full;
   wire 		   full;
   
   // internal error condition detected
   output [0:num_vcs*2-1] errors;
   wire [0:num_vcs*2-1]   errors;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs*addr_width-1] write_addr_ivc;
   wire [0:num_vcs*addr_width-1] read_addr_ivc;
   wire [0:num_vcs*addr_width-1] peek_addr_ivc;
   wire [0:num_vcs-1] 		 full_ivc;
   
   genvar 			 ivc;
   
   generate
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   //-------------------------------------------------------------------
	   // buffer control
	   //-------------------------------------------------------------------
	   
	   wire push;
	   assign push = push_valid & push_ivc[ivc];
	   
	   wire pop;
	   assign pop = pop_valid & pop_ivc[ivc];
	   
	   wire [0:addr_width-1] push_addr;
	   wire [0:addr_width-1] pop_addr;
	   wire 		 almost_empty;
	   wire 		 empty;
	   wire 		 almost_full;
	   wire 		 full;
	   wire [0:1] 		 errors;
	   c_fifo_ctrl
	     #(.depth(num_buffers_per_vc),
	       .reset_type(reset_type))
	   fc
	     (.clk(clk),
	      .reset(reset),
	      .push_active(push_active),
	      .pop_active(pop_active),
	      .push(push),
	      .pop(pop),
	      .push_addr(push_addr),
	      .pop_addr(pop_addr),
	      .almost_empty(almost_empty),
	      .empty(empty),
	      .almost_full(almost_full),
	      .full(full),
	      .errors(errors));
	   
	   wire 		 error_fc_underflow;
	   assign error_fc_underflow = errors[0];
	   
	   wire 		 error_fc_overflow;
	   assign error_fc_overflow = errors[1];
	   
	   assign full_ivc[ivc] = full;
	   assign almost_empty_ivc[ivc] = almost_empty;
	   assign empty_ivc[ivc] = empty;
	   
	   wire [0:addr_width-1] ;
	   
	   assign errors[ivc*2] = error_fc_underflow;
	   assign errors[ivc*2+1] = error_fc_overflow;
	   
	end
      
      
      //------------------------------------------------------------------------
      // generate output data
      //------------------------------------------------------------------------
      
      wire [0:width-1] fbf_pop_data;
      
      if(explicit_pipeline_register)
	begin
	   
	   if(num_vcs == 1)
	     assign fbf_pop_data = fbf_pop_data_ivc;
	   else if(num_vcs > 1)
	     begin
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(width))
		fbf_pop_data_sel
		  (.select(pop_ivc),
		   .data_in(fbf_pop_data_ivc),
		   .data_out(fbf_pop_data));
		
	     end
	   
	   wire bypass;
	   assign bypass = |(empty_ivc & pop_ivc);
	   
	   wire pipe_reg_active;
	   assign pipe_reg_active = push_valid | ~&empty_ivc;
	   
	   wire [0:width-1] pipe_reg_s, pipe_reg_q;
	   assign pipe_reg_s = bypass ? push_data : fbf_pop_data;
	   c_dff
	     #(.width(width),
	       .reset_type(reset_type))
	   pipe_regq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(pipe_reg_active),
	      .d(pipe_reg_s),
	      .q(pipe_reg_q));
	   
	   assign pop_data = pipe_reg_q;
	   
	end
      else
	begin

	   if(num_vcs == 1)
	     assign pop_data = fb_pop_data_ivc;
	   else if(num_vcs > 1)
	     begin
		
		wire active;
		assign active = pop_valid;

		wire [0:num_vcs-1] sel_ivc_s, sel_ivc_q;
		assign sel_ivc_s = pop_ivc;
		c_dff
		  #(.width(num_vcs),
		    .reset_type(reset_type))
		sel_ivcq
		  (.clk(clk),
		   .reset(reset),
		   .active(active),
		   .d(sel_ivc_s),
		   .q(sel_ivc_q));
		
		c_select_1ofn
		  #(.num_ports(num_vcs),
		    .width(width))
		pop_data_sel
		  (.select(sel_ivc_q),
		   .data_in(fbf_pop_data_ivc),
		   .data_out(pop_data));
		
	     end
	   
	end
      
   endgenerate
   
endmodule
