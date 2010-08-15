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
// VC state tracking module
//==============================================================================

module rtr_vc_state
  (clk, reset, active, flit_sent, flit_tail, fc_event_valid, elig, empty, 
   almost_full, full, errors);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_packets_per_vc = 4;
   
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   
   // select implementation variant for tail FIFO register file
   parameter tff_regfile_type = `REGFILE_TYPE_FF_2D;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   
   // width required to express number of packets in a VC
   localparam packet_count_width = clogb(num_packets_per_vc + 1);
   
   // required address width for tail FIFO
   localparam tff_addr_width = clogb(num_flits_per_vc);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   
   // clock enable signal
   input active;
   
   // a flit was sent
   input flit_sent;
   
   // sent flit was a tail flit
   input flit_tail;
   
   // flow control event occurred
   input fc_event_valid;
   
   // VC is eligible for allocation
   output elig;
   wire   elig;
   
   // VC is empty
   output empty;
   wire   empty;
   
   // VC has one slot left
   output almost_full;
   wire   almost_full;
   
   // VC is full
   output full;
   wire   full;
   
   // internal error condition detected
   output [0:3] errors;
   wire [0:3] 	errors;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire 	allocated;
   wire 	pt_full;
   wire 	ft_full;
   
   assign elig = ~allocated & ~pt_full & ~ft_full;
   
   wire 	error_ft_underflow;
   wire 	error_ft_overflow;
   wire 	error_pt_underflow;
   wire 	error_pt_overflow;
   
   generate
      
      case(flow_ctrl_type)
	
	`FLOW_CTRL_TYPE_CREDIT:
	  begin
	     
	     //-----------------------------------------------------------------
	     // track number of flits the VC can still accept
	     //-----------------------------------------------------------------
	     
	     wire ft_empty;
	     
	     wire track_active;
	     assign track_active = active | ~ft_empty;
	     
	     wire ft_debit;
	     assign ft_debit = flit_sent;
	     
	     wire ft_credit;
	     assign ft_credit = fc_event_valid;
	     
	     wire ft_almost_empty;
	     wire ft_almost_full;
	     wire [0:flit_count_width-1] ft_free;
	     wire [0:1] 		 ft_errors;
	     c_fifo_tracker
	       #(.depth(num_flits_per_vc),
		 .reset_type(reset_type))
	     ft
	       (.clk(clk),
		.reset(reset),
		.active(track_active),
		.push(ft_debit),
		.pop(ft_credit),
		.almost_empty(ft_almost_empty),
		.empty(ft_empty),
		.almost_full(ft_almost_full),
		.full(ft_full),
		.free(ft_free),
		.errors(ft_errors));
	     
	     assign empty = ft_empty;
	     assign almost_full = ft_almost_full;
	     assign full = ft_full;
	     
	     assign error_ft_underflow = ft_errors[0];
	     assign error_ft_overflow = ft_errors[1];
	     
	     
	     //-----------------------------------------------------------------
	     // track number of packets the VC can still accept
	     //-----------------------------------------------------------------
	     
	     if(num_packets_per_vc == num_flits_per_vc)
	       begin
		  
		  // if the VC can hold as many packets as it con hold flits, 
		  // we don't need dedicated credit tracking for packets, and 
		  // can instead just rely on the flit credit tracking 
		  // mechanism
		  assign pt_full = 1'b0;
		  
		  assign error_pt_underflow = 1'b0;
		  assign error_pt_overflow = 1'b0;
		  
	       end
	     else if(num_packets_per_vc < num_flits_per_vc)
	       begin
		  
		  // if the VC can hold fewer packets than flits, we need to 
		  // keep track of how many more packts can be accepted 
		  // explicitly
		  
		  wire pt_debit;
		  assign pt_debit = flit_sent & ~allocated;
		  
		  wire pt_credit;
		  
		  if(num_packets_per_vc == 1)
		    begin
		       
		       // if we can only have one packet per buffer, we can 
		       // accept the next one once the buffer has been 
		       // completely drained after the last packet's tail flit 
		       // has been sent
		       
		       wire last_credit_received;
		       assign last_credit_received
			 = ft_almost_empty & ft_credit;
		       
		       wire tail_sent_s, tail_sent_q;
		       assign tail_sent_s
			 = (tail_sent_q & ~pt_debit) | (ft_debit & flit_tail);
		       c_dff
			 #(.width(1),
			 .reset_type(reset_type))
		       tail_sentq
			 (.clk(clk),
			 .reset(reset),
			 .active(active),
			 .d(tail_sent_s),
			 .q(tail_sent_q));
		       
		       assign pt_credit = tail_sent_q & last_credit_received;
		       
		    end
		  else if(num_packets_per_vc > 1)
		    begin
		       
		       wire pop_active;
		       assign pop_active = ~ft_empty;
		       
		       wire tff_push_data;
		       assign tff_push_data = flit_tail;
		       
		       wire tff_pop_data;
		       wire tff_almost_full;
		       wire tff_full;
		       wire tff_almost_empty;
		       wire tff_empty;
		       wire [0:1] tff_errors;
		       c_fifo
			 #(.depth(num_flits_per_vc),
			   .width(1),
			   .regfile_type(tff_regfile_type),
			   .reset_type(reset_type))
		       tff
			 (.clk(clk),
			  .reset(reset),
			  .push_active(active),
			  .pop_active(pop_active),
			  .push(ft_debit),
			  .pop(ft_credit),
			  .push_data(tff_push_data),
			  .pop_data(tff_pop_data),
			  .almost_empty(tff_almost_empty),
			  .empty(tff_empty),
			  .almost_full(tff_almost_full),
			  .full(tff_full),
			  .errors(tff_errors));
		       
		       assign pt_credit = ft_credit & tff_pop_data;		
		       
		    end
		  
		  wire 		  pt_almost_empty;
		  wire 		  pt_empty;
		  wire 		  pt_almost_full;
		  wire [0:packet_count_width-1] pt_free;
		  wire [0:1] 			pt_errors;
		  c_fifo_tracker
		    #(.depth(num_packets_per_vc),
		      .reset_type(reset_type))
		  pt
		    (.clk(clk),
		     .reset(reset),
		     .active(track_active),
		     .push(pt_debit),
		     .pop(pt_credit),
		     .almost_empty(pt_almost_empty),
		     .empty(pt_empty),
		     .almost_full(pt_almost_full),
		    .full(pt_full),
		    .free(pt_free),
		    .errors(pt_errors));
		  
		  assign error_pt_underflow = pt_errors[0];
		  assign error_pt_overflow = pt_errors[1];
		  
	       end
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track whether this output VC is currently in use
   //---------------------------------------------------------------------------
   
   // NOTE: For the reset condition, we don't have to worry about whether or
   // not sufficient buffer space is available: If the VC is currently 
   // allocated, these checks would already have been performed at the 
   // beginning of switch allocation; on the other hand, if it is not currently 
   // allocated, 'allocated_q' is zero, and thus the reset condition does not 
   // have any effect.
   
   wire 					allocated_s, allocated_q;
   assign allocated_s = (allocated | flit_sent) & ~(flit_sent & flit_tail);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .active(active),
      .d(allocated_s),
      .q(allocated_q));
   
   assign allocated = allocated_q;
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	
	if(error_ft_underflow)
	  $display("ERROR: Flit count tracker underflow in module %m.");
	
	if(error_ft_overflow)
	  $display("ERROR: Flit count tracker overflow in module %m.");
	
	if(error_pt_underflow)
	  $display("ERROR: Packet count tracker underflow in module %m.");
	
	if(error_pt_overflow)
	  $display("ERROR: Packet count tracker overflow in module %m.");
	
     end
   
   // synopsys translate_on
   
   assign errors[0] = error_ft_underflow;
   assign errors[1] = error_ft_overflow;
   assign errors[2] = error_pt_underflow;
   assign errors[3] = error_pt_overflow;
   
endmodule
