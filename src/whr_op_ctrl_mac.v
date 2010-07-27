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



// output port controller (tracks state of buffers in downstream router)
module whr_op_ctrl_mac
  (clk, reset, flow_ctrl_in, req_ip, req_head_ip, req_tail_ip, gnt_ip,
   xbr_ctrl_ip, flit_data_in, channel_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "whr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
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
   
   // width of flow control signals
   localparam flow_ctrl_width = 1;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
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
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // requests from input ports
   input [0:num_ports-1] req_ip;
   
   // requests are for head flits
   input [0:num_ports-1] req_head_ip;
   
   // requests are for tail flits
   input [0:num_ports-1] req_tail_ip;
   
   // grants to input ports
   output [0:num_ports-1] gnt_ip;
   wire [0:num_ports-1]   gnt_ip;
   
   // crossbar control signals
   output [0:num_ports-1] xbr_ctrl_ip;
   wire [0:num_ports-1]   xbr_ctrl_ip;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing channel
   output [0:channel_width-1]  channel_out;
   wire [0:channel_width-1]    channel_out;
   
   // internal error condition detected
   output 		       error;
   wire 		       error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   // FIXME: The following should be in a separate module!
   
   wire [0:flow_ctrl_width-1]  flow_ctrl_s, flow_ctrl_q;
   assign flow_ctrl_s = flow_ctrl_in;
   
   wire 		       ft_empty;
   
   wire 		       flow_ctrl_active;
   assign flow_ctrl_active = ~ft_empty;
   
   wire 		       cred_valid_s, cred_valid_q;
   assign cred_valid_s = flow_ctrl_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .active(flow_ctrl_active),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign flow_ctrl_q[0] = cred_valid_q;
   
   wire 		       cred_valid;
   assign cred_valid = flow_ctrl_q[0];
   
   
   //---------------------------------------------------------------------------
   // arbitration
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1]        req_int_ip;
   assign req_int_ip = req_ip;
   
   wire 		       gnt_int;
   assign gnt_int = |req_int_ip;
   
   // NOTE: For the wormhole router, credit and eligibility checking happens at
   // the output controller, so request generation is simple and fast; however,
   // if clock gating based on requests proves to be timing-critical, we could
   // just enable all output controllers whenever any input controller has data
   // available.
   wire 		       arb_active;
   assign arb_active = |req_ip;
   
   wire 		       update;
   wire [0:num_ports-1]        gnt_int_ip;
   c_arbiter
     #(.num_ports(num_ports),
       .arbiter_type(arbiter_type),
       .reset_type(reset_type))
   gnt_int_ip_arb
     (.clk(clk),
      .reset(reset),
      .active(arb_active),
      .update(update),
      .req(req_int_ip),
      .gnt(gnt_int_ip));
   
   wire 		       hft_free;
   
   wire [0:num_ports-1]        new_gnt_ip;
   assign new_gnt_ip = gnt_int_ip & {num_ports{hft_free}};
   
   wire 		       new_gnt;
   assign new_gnt = gnt_int & hft_free;
   
   wire 		       allocated_q;
   
   wire 		       allocated_ip_active;
   assign allocated_ip_active = arb_active & ~allocated_q;
   
   wire [0:num_ports-1]        allocated_ip_s, allocated_ip_q;
   assign allocated_ip_s = update ? gnt_int_ip : allocated_ip_q;
   c_dff
     #(.width(num_ports),
       .reset_type(reset_type))
   allocated_ipq
     (.clk(clk),
      .reset(1'b0),
      .active(allocated_ip_active),
      .d(allocated_ip_s),
      .q(allocated_ip_q));
   
   wire [0:num_ports-1]        held_gnt_ip;
   assign held_gnt_ip = req_ip & allocated_ip_q;
   
   wire 		       held_gnt;
   assign held_gnt = |held_gnt_ip;
   
   wire 		       ft_free;
   
   wire 		       allocated_s;
   assign allocated_s = allocated_q ?
			(~|(held_gnt_ip & req_tail_ip) | ~ft_free) :
			(|(gnt_int_ip & ~req_tail_ip) & hft_free & ft_free);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(arb_active),
      .d(allocated_s),
      .q(allocated_q));
   
   assign update = ~allocated_q & new_gnt;
   
   wire [0:num_ports-1]        gnt_unqual_ip;
   assign gnt_unqual_ip = allocated_q ? held_gnt_ip : gnt_int_ip;
   
   assign xbr_ctrl_ip = gnt_unqual_ip;
   
   wire 		       gnt_unqual;
   assign gnt_unqual = allocated_q ? held_gnt : new_gnt;
   
   assign gnt_ip
     = (allocated_q ? held_gnt_ip : new_gnt_ip) & {num_ports{ft_free}};
   
   wire 		       gnt;
   assign gnt = gnt_unqual & ft_free;
   
   
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
   
   // when the output port is not allocated, the next flit must be a head flits;
   // the second term is required to account for cases where the output port 
   // gets allocated, but no credit is available
   wire 		       flit_head_s, flit_head_q;
   assign flit_head_s = ~allocated_q | |(held_gnt_ip & req_head_ip);
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
   assign flit_tail_s = |(gnt_unqual_ip & req_tail_ip);
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
	   assign hft_free = 1'b1;
	   
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
		assign tff_push_data = |(gnt_unqual_ip & req_tail_ip);
		
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
		   .push_active(arb_active),
		   .pop_active(cred_active),
		   .push(gnt),
		   .pop(cred_valid),
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
	   assign head_debit = ~allocated_q & new_gnt & ft_free;
	   
	   // track header credits using stock FIFO tracker module
	   wire 				 hft_almost_empty;
	   wire 				 hft_empty;
	   wire 				 hft_almost_full;
	   wire 				 hft_full;
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
	      .errors(hft_errors));
	   
	   assign hft_free = ~hft_full | head_credit;
	   
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
      .errors(ft_errors));
   
   wire 					 error_ft_underflow;
   assign error_ft_underflow = ft_errors[0];
   
   wire 					 error_ft_overflow;
   assign error_ft_overflow = ft_errors[1];
   
   // NOTE: For the wormhole router, the credit check can be performed at the 
   // allocator (here, arbiter) output; thus, the following computation can be
   // performed in parallel with arbitration, so we don't need an additional
   // register stage as in the general VC case.
   
   assign ft_free = ~ft_full | credit;
   
   
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
	   
	   // synopsys translate_off
	   always @(posedge clk)
	     begin
		
		if(error_ft_underflow)
		  $display("ERROR: Credit tracker underflow in module %m.");
		
		if(error_ft_overflow)
		  $display("ERROR: Credit tracker overflow in module %m.");
		
		if(error_hft_underflow)
		  $display({"ERROR: Head credit tracker underflow in module ",
			    "%."});
		
		if(error_hft_overflow)
		  $display("ERROR: Head credit tracker overflow in module %m.");
		
	     end
	   // synopsys translate_on
	   
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
