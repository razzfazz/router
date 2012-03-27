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
// multi-lane fifo buffer controller
//==============================================================================

module c_multi_lane_fifo
  (/*autoarg*/
   // Outputs
   push_addr_ln, pop_data, pop_addr_ln, peek_data, almost_empty_ln,
   empty_ln, full_ln, errors_ln,
   // Inputs
   clk, reset, clear, push_active, push_valid, push_sel_ln, push_data,
   pop_active, pop_valid, pop_sel_ln
   );
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of lanes
   parameter num_lanes = 4;
   
   // buffer entries per lane
   parameter num_buffers_per_lane = 8;
   
   // width of payload data
   parameter data_width = 64;
   
    // implementation variant for register file
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   // if enabled, read data comes from a register; otherwise, it comes straight
   // out of the register file
   // NOTE: In either case, pop_data is valid in the cycle after pop_valid!
   parameter registered_read = 1;
   
   // gate buffer write port if bypassing
   // (requires registered read; may increase cycle time)
   parameter gate_buffer_write = 0;
   
   // enable peek-ahead ports
   parameter enable_peek = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of buffers
   localparam num_buffers = num_lanes * num_buffers_per_lane;
   
   // address width required for selecting an individual entry
   localparam addr_width = clogb(num_buffers);
   
   // address width required for selecting an individual entry in a lane
   localparam lane_addr_width = clogb(num_buffers_per_lane);
   
   // difference between the two
   localparam pad_addr_width = addr_width - lane_addr_width;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;

   input [0:num_lanes-1] clear;
   
   
   // activity indicator for insertion
   input push_active;

   // insert data
   input push_valid;
   
   // lane to insert into
   input [0:num_lanes-1] push_sel_ln;
   
   // data to be inserted
   input [0:data_width-1] push_data;

   // location of next insertion
   output [0:num_lanes*addr_width-1] push_addr_ln;
   wire [0:num_lanes*addr_width-1]   push_addr_ln;
   
   // activity indicator for read / removal
   input 			     pop_active;
   
   // read and remove data
   input 			     pop_valid;
   
   // lane to remove from
   input [0:num_lanes-1] 	     pop_sel_ln;
   
   // read data
   // NOTE: This is valid in the cycle after pop_valid!
   output [0:data_width-1] 	     pop_data;
   wire [0:data_width-1] 	     pop_data;
   
   // location of next element to be read
   output [0:num_lanes*addr_width-1] pop_addr_ln;
   wire [0:num_lanes*addr_width-1]   pop_addr_ln;
   
   // peek-ahead at the element in each lane after the one to be read next
   output [0:data_width-1] 	     peek_data;
   wire [0:data_width-1] 	     peek_data;
   
   // lane state flags
   output [0:num_lanes-1] 	     almost_empty_ln;
   wire [0:num_lanes-1] 	     almost_empty_ln;
   output [0:num_lanes-1] 	     empty_ln;
   wire [0:num_lanes-1] 	     empty_ln;
   output [0:num_lanes-1]	     full_ln;
   wire [0:num_lanes-1] 	     full_ln;
   
   // internal error conditions detected
   output [0:num_lanes*2-1] 	     errors_ln;
   wire [0:num_lanes*2-1] 	     errors_ln;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire [0:num_lanes*addr_width-1]   peek_addr_ln;
   

   
   genvar 			     lane;
   
   generate
      
      for(lane = 0; lane < num_lanes; lane = lane + 1)
	begin:lanes

	   //-------------------------------------------------------------------
	   // buffer control
	   //-------------------------------------------------------------------
	   
	   wire push_sel;
	   assign push_sel = push_sel_ln[lane];
	   
	   wire push_valid_sel;
	   assign push_valid_sel = push_valid & push_sel;
	   
	   wire push;
	   assign push = push_valid_sel;
	   
	   wire pop_sel;
	   assign pop_sel = pop_sel_ln[lane];
	   
	   wire pop;
	   assign pop = pop_valid & pop_sel;
	   
	   wire [0:addr_width-1] push_addr;
	   wire [0:addr_width-1] pop_addr;
	   wire 		 almost_empty;
	   wire 		 empty;
	   wire 		 almost_full;
	   wire 		 full;
	   wire [0:1] 		 errors;
	   c_fifo_ctrl
	     #(.depth(num_buffers_per_lane),
	       .extra_addr_width(pad_addr_width),
	       .offset(lane * num_buffers_per_lane),
	       .reset_type(reset_type))
	   fc
	     (.clk(clk),
	      .reset(reset|clear[lane]),
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
	   
	   wire [0:addr_width-1] peek_addr;
	   if(enable_peek)
	     begin
		
		c_incr
		  #(.width(addr_width),
		    .min_value(lane * num_buffers_per_lane),
		    .max_value((lane + 1) * num_buffers_per_lane - 1))
		peek_addr_incr
		  (.data_in(pop_addr),
		   .data_out(peek_addr));
		
	     end
	   else
	     assign peek_addr = {addr_width{1'bx}};
	   
	   assign push_addr_ln[lane*addr_width:(lane+1)*addr_width-1]
	     = push_addr;
	   assign pop_addr_ln[lane*addr_width:(lane+1)*addr_width-1]
	     = pop_addr;
	   assign peek_addr_ln[lane*addr_width:(lane+1)*addr_width-1]
	     = peek_addr;
	   assign full_ln[lane] = full;
	   assign almost_empty_ln[lane] = almost_empty;
	   assign empty_ln[lane] = empty;
	   assign errors_ln[lane*2:lane*2+1] = errors;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // storage
   //---------------------------------------------------------------------------
   
   wire 		 write_active;
   assign write_active = push_active;
   
   wire [0:addr_width-1] push_addr;
   c_select_1ofn
     #(.num_ports(num_lanes),
       .width(addr_width))
   push_addr_sel
     (.select(push_sel_ln),
      .data_in(push_addr_ln),
      .data_out(push_addr));
   
   wire [0:addr_width-1] write_addr;
   assign write_addr = push_addr;
   
   wire [0:data_width-1] write_data;
   assign write_data = push_data;
   
   wire [0:addr_width-1] pop_addr;
   c_select_1ofn
     #(.num_ports(num_lanes),
       .width(addr_width))
   pop_addr_sel
     (.select(pop_sel_ln),
      .data_in(pop_addr_ln),
      .data_out(pop_addr));
   
   wire [0:data_width-1] read_data;
   
   wire 		 write_enable;
   wire [0:addr_width-1] read_addr;
   
   generate
      
      if(registered_read)
	begin
	   
	   wire empty;
	   c_select_1ofn
	     #(.num_ports(num_lanes),
	       .width(1))
	   empty_sel
	     (.select(pop_sel_ln),
	      .data_in(empty_ln),
	      .data_out(empty));
	   
	   if(gate_buffer_write)
	     assign write_enable = push_valid & ~(pop_valid & empty);
	   else
	     assign write_enable = push_valid;
	   
	   assign read_addr = pop_addr;
	   /*
	   wire [0:data_width-1] pop_data_s, pop_data_q;
	   assign pop_data_s
	     = pop_valid ? (empty ? write_data : read_data) : pop_data_q;
	   c_dff
	     #(.width(data_width),
	       .reset_type(reset_type))
	   pop_dataq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(pop_active),
	      .d(pop_data_s),
	      .q(pop_data_q));
	   */
	   assign pop_data 	= (empty ? write_data : read_data);
	   
	   
	end
      else
	begin
	   
	   assign write_enable 	= push_valid;
	   
	   wire [0:addr_width-1] read_addr_s, read_addr_q;
	   assign read_addr_s = pop_valid ? pop_addr : read_addr_q;
	   c_dff
	     #(.width(addr_width),
	       .reset_type(reset_type))
	   read_addrq
	     (.clk(clk),
	      .reset(1'b0),
	      .active(pop_active),
	      .d(read_addr_s),
	      .q(read_addr_q));
	   
	   assign read_addr = read_addr_q;
	   
	   assign pop_data = read_data;
	   
	end
      
      if(enable_peek)
	begin
	   
	   wire [0:addr_width-1] peek_addr;
	   c_select_1ofn
	     #(.num_ports(num_lanes),
	       .width(addr_width))
	   peek_addr_sel
	     (.select(pop_sel_ln),
	      .data_in(peek_addr_ln),
	      .data_out(peek_addr));
	   
	   c_regfile
	     #(.depth(num_buffers),
	       .width(data_width),
	       .num_read_ports(2),
	       .regfile_type(regfile_type))
	   bf
	     (.clk(clk),
	      .write_active(write_active),
	      .write_enable(write_enable),
	      .write_address(write_addr),
	      .write_data(write_data),
	      .read_address({read_addr, peek_addr}),
	      .read_data({read_data, peek_data}));
	   
	end
      else
	begin
	   
	   c_regfile
	     #(.depth(num_buffers),
	       .width(data_width),
	       .regfile_type(regfile_type))
	   bf
	     (.clk(clk),
	      .write_active(write_active),
	      .write_enable(write_enable),
	      .write_address(write_addr),
	      .write_data(write_data),
	      .read_address(read_addr),
	      .read_data(read_data));
	   
	   assign peek_data = {data_width{1'bx}};
	   
	end
      
   endgenerate
   
endmodule
