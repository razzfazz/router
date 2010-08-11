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
// output port controller
//==============================================================================

module whr_op_ctrl_mac
  (clk, reset, arb_active, flow_ctrl_in, gnt, gnt_head, gnt_tail, flit_data_in, 
   channel_out, elig, full, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "whr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
   // width required to express number of packets in a VC
   localparam packet_count_width = clogb(num_packets_per_vc + 1);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = ((connectivity == `CONNECTIVITY_LINE) ||
	(connectivity == `CONNECTIVITY_RING)) ?
       2 :
       (connectivity == `CONNECTIVITY_FULL) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? 1 :
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

   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // channel width
   localparam channel_width = flit_ctrl_width + flit_data_width;
   
   // required address width for tail FIFO
   localparam tff_addr_width = clogb(num_flits_per_vc);
   
   // select implementation variant for tail FIFO register file
   parameter tff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // ID of current input port
   parameter port_id = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // clock enable for arbitration results
   input arb_active;
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // grant from allocator module
   input 		       gnt;
   
   // grant is for head flit
   input 		       gnt_head;
   
   // grant is for tail flit
   input 		       gnt_tail;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing channel
   output [0:channel_width-1]  channel_out;
   wire [0:channel_width-1]    channel_out;
   
   // output can accept a new packet
   output 		       elig;
   wire 		       elig;
   
   // output is full
   output 		       full;
   wire 		       full;
   
   // internal error condition detected
   output 		       error;
   wire 		       error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire 		       empty;
   
   wire 		       flow_ctrl_active;
   assign flow_ctrl_active = ~empty;
   
   wire 		       fc_event_valid;
   wire 		       fc_event_sel_ovc;
   rtr_flow_ctrl_input
     #(.num_vcs(1),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fci
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .flow_ctrl_in(flow_ctrl_in),
      .fc_event_valid_out(fc_event_valid),
      .fc_event_sel_out_ovc(fc_event_sel_ovc));
   
   
   //---------------------------------------------------------------------------
   // staging for flit control signals
   //---------------------------------------------------------------------------
   
   // NOTE: Because we need to clear it in the cycle after a flit has been 
   // received, this register currently cannot be included in any of the 
   // other clock gating domains. If we could change this to transmit flits 
   // using edge-based signaling (i.e., transitions), it could be included in 
   // the clock gating domain controlled by arb_active.
   // Alternatively, we could include the flit_valid_in term in arb_active; 
   // this would allow us to include flit_valid_inq in the gating domain at the 
   // cost of some unnecessary activity. As synthesis will probably not create 
   // a clock gating domain for just this register, it currently will most 
   // likely end up being free-running, so this may be a good tradeoff.
   
   wire 		       flit_valid_in;
   
   wire 		       flit_valid_in_active;
   assign flit_valid_in_active = arb_active | flit_valid_in;
   
   wire 		       flit_valid_in_s, flit_valid_in_q;
   assign flit_valid_in_s = gnt;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_valid_inq
     (.clk(clk),
      .reset(reset),
      .active(flit_valid_in_active),
      .d(flit_valid_in_s),
      .q(flit_valid_in_q));
   
   assign flit_valid_in = flit_valid_in_q;
   
   wire 		       flit_head_s, flit_head_q;
   assign flit_head_s = gnt_head;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_headq
     (.clk(clk),
      .reset(1'b0),
      .active(arb_active),
      .d(flit_head_s),
      .q(flit_head_q));
   
   wire 		       flit_head_in;
   assign flit_head_in = flit_head_q;
   
   wire 		       flit_tail_s, flit_tail_q;
   assign flit_tail_s = gnt_tail;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_tailq
     (.clk(clk),
      .reset(1'b0),
      .active(arb_active),
      .d(flit_tail_s),
      .q(flit_tail_q));
   
   wire 		       flit_tail_in;
   assign flit_tail_in = flit_tail_q;
   
   
   //---------------------------------------------------------------------------
   // track state of downstream buffer
   //---------------------------------------------------------------------------
   
   wire 		       vc_gnt;
   assign vc_gnt = gnt & gnt_head;
   
   wire 		       almost_full;
   wire [0:3] 		       vs_errors;
   rtr_vc_state
     #(.num_flits_per_vc(num_flits_per_vc),
       .num_packets_per_vc(num_packets_per_vc),
       .flow_ctrl_type(flow_ctrl_type),
       .tff_regfile_type(tff_regfile_type),
       .reset_type(reset_type))
   vs
     (.clk(clk),
      .reset(reset),
      .active(arb_active),
      .vc_gnt(vc_gnt),
      .flit_sent(gnt),
      .flit_head(gnt_head),
      .flit_tail(gnt_tail),
      .fc_event_valid(fc_event_valid),
      .elig(elig),
      .empty(empty),
      .almost_full(almost_full),
      .full(full),
      .errors(vs_errors));
   
   
   //---------------------------------------------------------------------------
   // output staging
   //---------------------------------------------------------------------------
   
   wire 					 flit_out_active;
   assign flit_out_active = flit_valid_in;
   
   rtr_channel_output
     #(.num_vcs(1),
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
      .flit_sel_in_ovc(1'b1),
      .channel_out(channel_out));
   
   
   //---------------------------------------------------------------------------
   // error checker logic
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:3] errors_s, errors_q;
	   assign errors_s = vs_errors;
	   c_err_rpt
	     #(.num_errors(4),
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
