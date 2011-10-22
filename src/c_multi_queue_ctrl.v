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

module c_multi_queue_ctrl
  (clk, reset, push_active, pop_active, push_valid, push_queue, pop_valid, 
   pop_queue, write_addr, read_addr, almost_empty_queue, empty_queue, full, 
   errors);
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of queues
   parameter num_queues = 4;
   
   // number of buffer
   parameter num_buffers = 32;
   
   // select implementation variant for flit buffer register file
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------

   // required address size
   localparam addr_width = clogb(num_buffers);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;

   // clock gating
   input push_active;
   input pop_active;
   
   // insert data
   input push_valid;
   input [0:num_queues-1] push_queue;
   
   // retrieve data
   input 		  pop_valid;
   input [0:num_queues-1] pop_queue;
   
   // address of buffer entry to be written to
   output [0:addr_width-1] write_addr;
   wire [0:addr_width-1]   write_addr;
   
   // address of buffer entry to be read from
   output [0:addr_width-1] pop_addr;
   wire [0:addr_width-1]   pop_addr;
   
   // buffer fill state flags
   output [0:num_queues-1] almost_empty_queue;
   wire [0:num_queues-1]   almost_empty_queue;
   output [0:num_queues-1] empty_queue;
   wire [0:num_queues-1]   empty_queue;
   output 		   full;
   wire 		   full;
   
   // internal error condition detected
   output [0:num_queues*2-1] errors;
   wire [0:num_queues*2-1]   errors;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   assign push_addr = 
   //---------------------------------------------------------------------------
   // free list
   //---------------------------------------------------------------------------
   
   wire 		     active;
   assign active = push_active | pop_active;
   
   wire [0:addr_width-1]     free_head_s, free_head_q;
   assign free_head_s = (full & pop_valid) ? 
			pop_addr : 
			(push_valid ? ptr[free_head_q] : free_head_q);
   c_dff
     #(.width(addr_width),
       .reset_type(reset_type))
   free_headq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(free_head_s),
      .q(free_head_q));
   
   wire [0:addr_width-1]     free_tail_s, free_tail_q;
   assign free_tail_s = pop ? pop_addr : free_tail_q;
   c_dff
     #(.width(addr_width),
       .reset_type(reset_type),
       .reset_value(num_buffers - 1))
   free_tailq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(free_tail_s),
      .q(free_tail_q));
   
   wire 		     full_s, full_q;
   assign full_s = full_q ?
		   ~pop_valid :
		   |(free_head_q ^ free_tail_q) & push_valid & ~pop_valid;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   fullq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(full_s),
      .q(full_q));
   
   assign full = full_q;
   
   
   //---------------------------------------------------------------------------
   // storage
   //---------------------------------------------------------------------------

   reg 
   wire [0:addr_width-1]     write_address;
   assign write_address = pop_valid ? pop_addr : free_head;
   
   wire [0:addr_width-1]     read_address;
   
   c_regfile
     #(.depth(num_buffers),
       .width(addr_width),
       .num_read_ports(1),
       .regfile_type(regfile_type))
   prf
     (.clk(clk),
      .write_active(),
      .write_enable(),
      .write_address(),
      .write_data(),
      .read_active(),
      .read_address(),
      .read_data());
   
   
   //---------------------------------------------------------------------------
   // queue state tracking
   //---------------------------------------------------------------------------
   
   wire [0:num_queues*addr_width-1] pop_addr_queue;
   c_select_1ofn
     #(.num_ports(num_queues),
       .width(addr_width))
   pop_addr_sel
     (.select(pop_queue),
      .data_in(pop_addr_queue),
      .data_out(pop_addr));
   
   genvar 			    queue;
   
   generate
      
      for(queue = 0; queue < num_queues; queue = queue + 1)
	begin:queues
	   
	   //-------------------------------------------------------------------
	   // buffer control
	   //-------------------------------------------------------------------
	   
	   wire push;
	   assign push = push_valid & push_queue[queue];
	   
	   wire pop;
	   assign pop = pop_valid & pop_queue[queue];
	   
	   wire [0:addr_width-1] push_addr;
	   assign push_addr = 
	   
	   wire [0:addr_width-1] pop_addr;
	   
	   
	   
	   
	   wire [0:addr_width-1] push_addr;
	   wire [0:addr_width-1] pop_addr;
	   wire 		 almost_empty;
	   wire 		 empty;
	   wire 		 almost_full;
	   wire 		 full;
	   wire [0:1] 		 errors;
	   c_fifo_ctrl
	     #(.depth(num_buffers_per_queue),
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
	   
	   assign full_queue[queue] = full;
	   assign almost_empty_queue[queue] = almost_empty;
	   assign empty_queue[queue] = empty;
	   
	   wire [0:addr_width-1] 
	   
	   //-------------------------------------------------------------------
	   // error checking
	   //-------------------------------------------------------------------
	   
	   // synopsys translate_off
	   
	   always @(posedge clk)
	   begin
	      
	      if(error_fc_underflow)
		$display("ERROR: Queue underflow in module %m, VC %d.", queue);
	      
	      if(error_fc_overflow)
		$display("ERROR: Queue overflow in module %m, VC %d.", queue);
	      
	   end
	   
	   // synopsys translate_on
	   
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
