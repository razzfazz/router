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
// flit buffer
//==============================================================================

module rtr_flit_buffer
  (clk, reset, push_active, push_valid, push_sel_ivc, push_data, push_addr_ivc, 
   pop_active, pop_valid, pop_sel_ivc, pop_data, pop_addr_ivc, peek_data, 
   almost_empty_ivc, empty_ivc, full, errors_ivc);
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of VCs
   parameter num_vcs = 4;
   
   // buffer entries per VC
   parameter num_buffers_per_vc = 8;
   
   // width of payload data
   parameter flit_data_width = 64;
   
    // implementation variant for register file
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register = 1;
   
   // gate buffer write port if bypassing
   // (requires explicit pipeline register; may increase cycle time)
   parameter gate_buffer_write = 0;
   
   // use atomic VC allocation
   parameter atomic_vc_allocation = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of buffers
   localparam num_buffers = num_vcs * num_buffers_per_vc;
   
   // address width required for selecting an individual entry
   localparam addr_width = clogb(num_buffers);
   
   // address width required for selecting an individual entry in a VC
   localparam vc_addr_width = clogb(num_buffers_per_vc);
   
   // difference between the two
   localparam pad_addr_width = addr_width - vc_addr_width;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;

   // activity indicator for insertion
   input push_active;

   // insert data
   input push_valid;
   
   // lane to insert into
   input [0:num_vcs-1] push_sel_ivc;
   
   // data to be inserted
   input [0:flit_data_width-1] push_data;

   // location of next insertion
   output [0:num_vcs*addr_width-1] push_addr_ivc;
   wire [0:num_vcs*addr_width-1]   push_addr_ivc;
   
   // activity indicator for read / removal
   input 			   pop_active;
   
   // read and remove data
   input 			   pop_valid;
   
   // lane to remove from
   input [0:num_vcs-1] 		   pop_sel_ivc;
   
   // read data
   // NOTE: This is valid in the cycle after pop_valid!
   output [0:flit_data_width-1]    pop_data;
   wire [0:flit_data_width-1] 	   pop_data;
   
   // location of next element to be read
   output [0:num_vcs*addr_width-1] pop_addr_ivc;
   wire [0:num_vcs*addr_width-1]   pop_addr_ivc;
   
   // peek-ahead at the element in each lane after the one to be read next
   output [0:flit_data_width-1]    peek_data;
   wire [0:flit_data_width-1] 	   peek_data;
   
   // lane state flags
   output [0:num_vcs-1] 	   almost_empty_ivc;
   wire [0:num_vcs-1] 		   almost_empty_ivc;
   output [0:num_vcs-1] 	   empty_ivc;
   wire [0:num_vcs-1] 		   empty_ivc;
   output 			   full;
   wire 			   full;
   
   // internal error conditions detected
   output [0:num_vcs*2-1] 	   errors_ivc;
   wire [0:num_vcs*2-1] 	   errors_ivc;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   c_samq
     #(.num_queues(num_vcs),
       .num_buffers_per_queue(num_buffers_per_vc),
       .data_width(flit_data_width),
       .regfile_type(regfile_type),
       .registered_read(explicit_pipeline_register),
       .gate_buffer_write(gate_buffer_write),
       .enable_peek(!atomic_vc_allocation),
       .reset_type(reset_type))
   mlf
     (.clk(clk),
      .reset(reset),
      .push_active(push_active),
      .push_valid(push_valid),
      .push_sel_qu(push_sel_ivc),
      .push_data(push_data),
      .push_addr_qu(push_addr_ivc),
      .pop_active(pop_active),
      .pop_valid(pop_valid),
      .pop_sel_qu(pop_sel_ivc),
      .pop_data(pop_data),
      .pop_addr_qu(pop_addr_ivc),
      .peek_data(peek_data),
      .almost_empty_qu(almost_empty_ivc),
      .empty_qu(empty_ivc),
      .full(full),
      .errors_qu(errors_ivc));
   
endmodule
