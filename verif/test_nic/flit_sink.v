// $Id: flit_sink.v 4285 2012-02-08 01:19:01Z qtedq $

/*
 Copyright (c) 2007-2012, Trustees of The Leland Stanford Junior University
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

module flit_sink
  (clk, reset, channel, flow_ctrl, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   parameter initial_seed = 0;
   
   // flit consumption rate (percentage of cycles)
   parameter consume_rate = 50;
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // number of VCs
   parameter num_vcs = 8;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length = 4;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length = 1;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // total number of bits required for routing-related information
   parameter route_info_width = 14;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   input [0:channel_width-1] channel;
   
   output [0:flow_ctrl_width-1] flow_ctrl;
   wire [0:flow_ctrl_width-1] 	flow_ctrl;
   
   output 			error;
   wire 			error;
   
   integer 			seed = initial_seed;
   
   wire 			flit_valid;
   wire 			flit_head;
   wire [0:num_vcs-1] 		flit_head_ivc;
   wire 			flit_tail;
   wire [0:num_vcs-1] 		flit_tail_ivc;
   wire [0:flit_data_width-1] 	flit_data;
   wire [0:num_vcs-1] 		flit_sel_ivc;
   rtr_channel_input
     #(.num_vcs(num_vcs),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .route_info_width(route_info_width),
       .flit_data_width(flit_data_width),
       .reset_type(reset_type))
   chi
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .channel_in(channel),
      .flit_valid_out(flit_valid),
      .flit_head_out(flit_head),
      .flit_head_out_ivc(flit_head_ivc),
      .flit_tail_out(flit_tail),
      .flit_tail_out_ivc(flit_tail_ivc),
      .flit_data_out(flit_data),
      .flit_sel_out_ivc(flit_sel_ivc));
   
   reg 				consume;
   
   always @(posedge clk, posedge reset)
     begin
	consume <= $dist_uniform(seed, 0, 99) < consume_rate;
     end
   
   wire [0:num_vcs-1] 		buffer_empty_ivc;
   
   wire 			update;
   assign update = ~&buffer_empty_ivc & consume;
   
   wire [0:num_vcs-1] 		req_ivc;
   assign req_ivc = ~buffer_empty_ivc;
   
   wire [0:num_vcs-1] 		gnt_ivc;
   c_arbiter
     #(.num_ports(num_vcs),
       .arbiter_type(`ARBITER_TYPE_MATRIX),
       .reset_type(reset_type))
   gnt_ivc_arb
     (.clk(clk),
      .reset(reset),
      .update(update),
      .active(1'b1),
      .req(req_ivc),
      .gnt(gnt_ivc));
   
   wire [0:num_vcs-1] 		buffer_push_ivc;
   assign buffer_push_ivc = {num_vcs{flit_valid}} & flit_sel_ivc;
   
   wire [0:num_vcs-1] 		buffer_pop_ivc;
   assign buffer_pop_ivc = {num_vcs{consume}} & gnt_ivc;
   
   wire [0:num_vcs-1] 		buffer_error_ivc;
   
   rtr_flow_ctrl_output
     #(.num_vcs(num_vcs),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fco
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .fc_event_valid_in(update),
      .fc_event_sel_in_ivc(gnt_ivc),
      .flow_ctrl_out(flow_ctrl));
   
   generate
      
      genvar 		    ivc;
      
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire buffer_push;
	   assign buffer_push = buffer_push_ivc[ivc];
	   
	   wire buffer_pop;
	   assign buffer_pop = buffer_pop_ivc[ivc];
	   
	   wire 			    buffer_almost_empty;
	   wire 			    buffer_empty;
	   wire 			    buffer_almost_full;
	   wire 			    buffer_full;
	   wire [0:flit_count_width-1] 	    buffer_free;
	   wire [0:1] 			    buffer_errors;
	   c_fifo_tracker
	     #(.depth(num_flits_per_vc),
	       .reset_type(reset_type))
	   ft
	     (.clk(clk),
	      .reset(reset),
	      .active(1'b1),
	      .push(buffer_push),
	      .pop(buffer_pop),
	      .almost_empty(buffer_almost_empty),
	      .empty(buffer_empty),
	      .almost_full(buffer_almost_full),
	      .full(buffer_full),
	      .free(buffer_free),
	      .errors(buffer_errors));
	   
	   assign buffer_empty_ivc[ivc] = buffer_empty;
	   assign buffer_error_ivc[ivc] = |buffer_errors;
	   
	end
      
   endgenerate
   
   assign error = |buffer_error_ivc;
   
endmodule
