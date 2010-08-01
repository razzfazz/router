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
   channel_out, elig, cred, error);
   
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
   
   // output can accept a new flit
   output 		       cred;
   wire 		       cred;
   
   // internal error condition detected
   output 		       error;
   wire 		       error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire 		       ft_empty;
   
   wire 		       flow_ctrl_active;
   assign flow_ctrl_active = ~ft_empty;
   
   wire 		       cred_valid;
   wire 		       cred_sel_ovc;
   rtr_flow_ctrl_input
     #(.num_vcs(1),
       .flow_ctrl_type(flow_ctrl_type),
       .reset_type(reset_type))
   fci
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .flow_ctrl_in(flow_ctrl_in),
      .fc_event_valid_out(cred_valid),
      .fc_event_sel_out_ovc(cred_sel_ovc));
   
   
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
   // track VC allocation state
   //---------------------------------------------------------------------------
   
   wire 		       head_granted;
   assign head_granted = gnt & gnt_head;
   
   wire 		       tail_granted;
   assign tail_granted = gnt & gnt_tail;
   
   wire 		       allocated_s, allocated_q;
   assign allocated_s = (allocated_q | head_granted) & ~tail_granted;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(arb_active),
      .d(allocated_s),
      .q(allocated_q));
   
   wire 		       head_full;
   
   assign elig = ~allocated_q & ~head_full;
   
   
   //---------------------------------------------------------------------------
   // track number of packets that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 		       cred_active;
   assign cred_active = cred_valid;
   
   wire 		       track_active;
   assign track_active = arb_active | cred_active;
   
   wire 		       credit;
   assign credit = cred_valid;
   
   wire 		       ft_almost_empty;
   wire 		       error_hft_underflow;
   wire 		       error_hft_overflow;
   
   generate
      
      if(num_packets_per_vc == num_flits_per_vc)
	begin
	   
	   // if every flit buffer entry can be a head flit, we don't need 
	   // dedicated credit tracking for headers, and can instead just rely 
	   // on the normal credit tracking mechanism
	   assign head_full = 1'b0;
	   
	   assign error_hft_underflow = 1'b0;
	   assign error_hft_overflow = 1'b0;
	   
	end
      else if(num_packets_per_vc < num_flits_per_vc)
	begin
	   
	   // if only a subset of the flit buffer entries can be headers, we 
	   // need to keep track of how many such slots are left
	   
	   wire head_credit;
	   
	   if(num_packets_per_vc == 1)
	     begin
		
		wire flags_active;
		assign flags_active = flit_valid_in;
		
		// if we can only have one packet per buffer, we can accept the 
		// next one once the buffer has been completely drained after 
		// the tail has been sent
		
		wire last_credit_received;
		assign last_credit_received = ft_almost_empty & credit;
		
		wire tail_sent_s, tail_sent_q;
		assign tail_sent_s
		  = (tail_sent_q & ~(flit_valid_in & flit_head_in)) | 
		    (flit_valid_in & flit_tail_in);
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		tail_sentq
		  (.clk(clk),
		   .reset(reset),
		   .active(flags_active),
		   .d(tail_sent_s),
		   .q(tail_sent_q));
		
		assign head_credit =  tail_sent_q & last_credit_received;
		
	     end
	   else if(num_packets_per_vc > 1)
	     begin
		
		wire 			  tff_push_data;
		assign tff_push_data = flit_tail_in;
		
		wire 			  tff_pop_data;
		wire 			  tff_almost_full;
		wire 			  tff_full;
		wire 			  tff_almost_empty;
		wire 			  tff_empty;
		wire [0:1] 		  tff_errors;
		c_fifo
		  #(.depth(num_flits_per_vc),
		    .width(1),
		    .regfile_type(tff_regfile_type),
		    .reset_type(reset_type))
		tff
		  (.clk(clk),
		   .reset(reset),
		   .push_active(flit_valid_in),
		   .pop_active(cred_active),
		   .push(flit_valid_in),
		   .pop(credit),
		   .push_data(tff_push_data),
		   .pop_data(tff_pop_data),
		   .almost_empty(tff_almost_empty),
		   .empty(tff_empty),
		   .almost_full(tff_almost_full),
		   .full(tff_full),
		   .errors(tff_errors));
		
		assign head_credit = credit & tff_pop_data;
		
	     end
	   
	   wire 				 head_debit;
	   assign head_debit = head_granted;
	   
	   // track header credits using stock FIFO tracker module
	   wire 				 hft_almost_empty;
	   wire 				 hft_empty;
	   wire 				 hft_almost_full;
	   wire 				 hft_full;
	   wire [0:packet_count_width-1] 	 hft_free;
	   wire [0:1] 				 hft_errors;
	   c_fifo_tracker
	     #(.depth(num_packets_per_vc),
	       .reset_type(reset_type))
	   hft
	     (.clk(clk),
	      .reset(reset),
	      .active(track_active),
	      .push(head_debit),
	      .pop(head_credit),
	      .almost_empty(hft_almost_empty),
	      .empty(hft_empty),
	      .almost_full(hft_almost_full),
	      .full(hft_full),
	      .free(hft_free),
	      .errors(hft_errors));
	   
	   assign head_full = hft_full & ~head_credit;
	   
	   assign error_hft_underflow = hft_errors[0];
	   assign error_hft_overflow = hft_errors[1];
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 					 debit;
   assign debit = gnt;
   
   wire 					 ft_almost_full;
   wire 					 ft_full;
   wire [0:flit_count_width-1] 			 ft_free;
   wire [0:1] 					 ft_errors;
   c_fifo_tracker
     #(.depth(num_flits_per_vc),
       .reset_type(reset_type))
   ft
     (.clk(clk),
      .reset(reset),
      .active(track_active),
      .push(debit),
      .pop(credit),
      .almost_empty(ft_almost_empty),
      .empty(ft_empty),
      .almost_full(ft_almost_full),
      .full(ft_full),
      .free(ft_free),
      .errors(ft_errors));
   
   wire 					 error_ft_underflow;
   assign error_ft_underflow = ft_errors[0];
   
   wire 					 error_ft_overflow;
   assign error_ft_overflow = ft_errors[1];
   
   wire 					 full;
   assign full = ft_full & ~credit;
   
   assign cred = ~full;
   
   
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
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	
	if(error_ft_underflow)
	  $display("ERROR: Credit tracker underflow in module %m.");
	
	if(error_ft_overflow)
	  $display("ERROR: Credit tracker overflow in module %m.");
	
	if(error_hft_underflow)
	  $display("ERROR: Head credit tracker underflow in module %m.");
	
	if(error_hft_overflow)
	  $display("ERROR: Head credit tracker overflow in module %m.");
	
     end
   
   // synopsys translate_on
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:3] errors_s, errors_q;
	   assign errors_s = {error_ft_underflow,
			      error_ft_overflow,
			      error_hft_underflow,
			      error_hft_overflow};
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
