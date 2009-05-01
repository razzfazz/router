// $Id$

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
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
  (clk, reset, flow_ctrl_in, sw_gnt, xbr_ctrl_ip, int_flit_ctrl_in, 
   flit_data_in, flit_ctrl_out, flit_data_out, elig, free, error);
   
`include "c_constants.v"
`include "whr_constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width required to select a buffer
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   localparam num_nodes_per_router
     = num_ports - num_dimensions * num_neighbors_per_dim;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // total number of bits required for storing routing information
   localparam route_info_width = addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width = 1 + 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;

   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // switch slot was allocated for this output port
   input sw_gnt;
   
   // port to which this output is currently connected
   input [0:num_ports-1] xbr_ctrl_ip;
   
   // incoming flit control signals
   input [0:int_flit_ctrl_width-1] int_flit_ctrl_in;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   output elig;
   wire 		      elig;
   
   // output VC has buffer space (i.e., credits) available
   output free;
   wire 		      free;
   
   // internal error condition detected
   output error;
   wire 		      error;
   
   
   //---------------------------------------------------------------------------
   // input staging
   //---------------------------------------------------------------------------
   
   wire [0:flow_ctrl_width-1] flow_ctrl_s, flow_ctrl_q;
   assign flow_ctrl_s = flow_ctrl_in;
   
   wire 		      cred_valid_s, cred_valid_q;
   assign cred_valid_s = flow_ctrl_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign flow_ctrl_q[0] = cred_valid_q;
   
   generate
      
      if(flow_ctrl_width > 1)
	begin
	   
	   c_dff
	     #(.width(flow_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flow_ctrlq
	     (.clk(clk),
	      .reset(reset),
	      .d(flow_ctrl_s[1:flow_ctrl_width-1]),
	      .q(flow_ctrl_q[1:flow_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output VC control logic
   //---------------------------------------------------------------------------
   
   wire xbr_ctrl;
   assign xbr_ctrl = |xbr_ctrl_ip;
   
   wire 				  flit_valid_in;
   assign flit_valid_in = xbr_ctrl;
   
   wire 				  flit_head_in;
   assign flit_head_in = int_flit_ctrl_in[0];
   
   wire 				  flit_tail_in;
   assign flit_tail_in = int_flit_ctrl_in[1];
   
   wire 				  cred_valid;
   assign cred_valid = flow_ctrl_q[0];
   
   wire 				  credit;
   assign credit = cred_valid;
   
   wire 				  debit;
   assign debit = flit_valid_in;
   
   
   //---------------------------------------------------------------------------
   // track whether this output port is currently assigend to an input port
   //---------------------------------------------------------------------------
	   
   wire 				  set_allocated;
   assign set_allocated = sw_gnt;
   
   wire 				  reset_allocated;   
   assign reset_allocated = flit_valid_in & flit_tail_in;
   
   wire 				  allocated_s, allocated_q;
   assign allocated_s
     = (set_allocated | allocated_q) & ~reset_allocated;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .d(allocated_s),
      .q(allocated_q));
   
   
   //---------------------------------------------------------------------------
   // track number of packets that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire [0:cred_count_width-1] 		  cred_count_s;
   wire 				  head_free_early;
   wire 				  error_hct;
   
   generate
      
      if(num_header_buffers == num_flit_buffers)
	begin
	   
	   // if every flit buffer entry can be a head flit, we don't need 
	   // dedicated credit tracking for headers, and can instead just rely 
	   // on the normal credit tracking mechanism
	   assign head_free_early = 1'b1;
	   
	   assign error_hct = 1'b0;
	   
	end
      else
	begin
	   
	   // if only a subset of the flit buffer entries can be headers, we 
	   // need to keep track of how many such slots are left
	   
	   if(num_header_buffers == 1)
	     begin
		
		// if we can only have one packet per buffer, we can accept the 
		// next one once the buffer has been completely drained after 
		// the tail has been sent
		
		wire buffer_drained;
		assign buffer_drained = (cred_count_s == num_flit_buffers);
		
		wire tail_sent_s, tail_sent_q;
		assign tail_sent_s
		  = (tail_sent_q | (flit_valid_in & flit_tail_in)) &
		    ~buffer_drained;
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		tail_sentq
		  (.clk(clk),
		   .reset(reset),
		   .d(tail_sent_s),
		   .q(tail_sent_q));
		
		wire head_free_s, head_free_q;
		assign head_free_s
		  = (head_free_q & ~sw_gnt) |
		    (credit & tail_sent_q & buffer_drained);
		c_dff
		  #(.width(1),
		    .reset_type(reset_type),
		    .reset_value(1'b1))
		head_freeq
		  (.clk(clk),
		   .reset(reset),
		   .d(head_free_s),
		   .q(head_free_q));
		
		assign head_free_early = head_free_s;
		
		assign error_hct = 1'b0;
		
	     end
	   else
	     begin
		
		wire [0:flit_buffer_idx_width-1] push_ptr_next, push_ptr_q;
		c_incr
		  #(.width(flit_buffer_idx_width),
		    .min_value(0),
		    .max_value(num_flit_buffers-1))
		push_ptr_incr
		  (.data_in(push_ptr_q),
		   .data_out(push_ptr_next));
		
		wire [0:flit_buffer_idx_width-1] push_ptr_s;
		assign push_ptr_s = debit ? push_ptr_next : push_ptr_q;
		c_dff
		  #(.width(flit_buffer_idx_width),
		    .reset_type(reset_type))
		push_ptrq
		  (.clk(clk),
		   .reset(reset),
		   .d(push_ptr_s),
		   .q(push_ptr_q));
		
		wire [0:flit_buffer_idx_width-1] pop_ptr_next, pop_ptr_q;
		c_incr
		  #(.width(flit_buffer_idx_width),
		    .min_value(0),
		    .max_value(num_flit_buffers-1))
		pop_ptr_incr
		  (.data_in(pop_ptr_q),
		   .data_out(pop_ptr_next));
		
		wire [0:flit_buffer_idx_width-1] pop_ptr_s;
		assign pop_ptr_s = credit ? pop_ptr_next : pop_ptr_q;
		c_dff
		  #(.width(flit_buffer_idx_width),
		    .reset_type(reset_type))
		pop_ptrq
		  (.clk(clk),
		   .reset(reset),
		   .d(pop_ptr_s),
		   .q(pop_ptr_q));
		
		reg [0:num_flit_buffers-1] 	 tail_queue;
		
		always @(posedge clk)
		  if(debit)
		    tail_queue[push_ptr_q] <= flit_tail_in;
		
		wire 				 tail;
		assign tail = tail_queue[pop_ptr_q];
		
		wire 				 head_credit;
		assign head_credit = tail & credit;
		
		wire 				 head_debit;
		assign head_debit = sw_gnt & ~allocated_q;
		
		// track header credits using stock credit tracker module
		wire 				 head_free;
		c_credit_tracker
		  #(.num_credits(num_header_buffers),
		    .checker_enable(checker_enable),
		    .checker_capture_mode(checker_capture_mode),
		    .reset_type(reset_type))
		hct
		  (.clk(clk),
		   .reset(reset),
		   .credit(head_credit),
		   .debit(head_debit),
		   .free(head_free),
		   .free_early(head_free_early),
		   .error(error_hct));
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire [0:cred_count_width-1] 			 cred_count_q;
   assign cred_count_s = (cred_count_q + credit - debit);
   c_dff
     #(.width(cred_count_width),
       .reset_type(reset_type),
       .reset_value(num_flit_buffers))
   cred_countq
     (.clk(clk),
      .reset(reset),
      .d(cred_count_s),
      .q(cred_count_q));
   
   wire [0:1] 					 error_cred;
   assign error_cred = {(cred_count_q == num_flit_buffers) && credit,
			(cred_count_q == 0) && debit};
   
   wire 					 cred_s, cred_q;
   assign cred_s = |cred_count_s;
   c_dff
     #(.width(1),
       .reset_value(1'b1),
       .reset_type(reset_type))
   credq
     (.clk(clk),
      .reset(reset),
      .d(cred_s),
      .q(cred_q));
   
   assign free = cred_q;
   
   
   //---------------------------------------------------------------------------
   // keep track of whether current VC is available for allocation
   //---------------------------------------------------------------------------
   
   wire 					 elig_s, elig_q;
   assign elig_s = ~allocated_s & head_free_early;
   c_dff
     #(.width(1),
       .reset_type(reset_type),
       .reset_value(1'b1))
   eligq
     (.clk(clk),
      .reset(reset),
      .d(elig_s),
      .q(elig_q));
   
   assign elig = elig_q;
   
   
   //---------------------------------------------------------------------------
   // output staging
   //---------------------------------------------------------------------------
   
   wire [0:flit_ctrl_width-1] 		      flit_ctrl_s, flit_ctrl_q;
   assign flit_ctrl_s[0] = flit_valid_in;
   assign flit_ctrl_s[1:flit_ctrl_width-1]
	    = xbr_ctrl ? 
	      int_flit_ctrl_in[0:flit_ctrl_width-2] : 
	      flit_ctrl_q[1:flit_ctrl_width-1];
   
   wire 				flit_valid_s, flit_valid_q;
   assign flit_valid_s = flit_ctrl_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   assign flit_ctrl_q[0] = flit_valid_q;
   
   c_dff
     #(.width(flit_ctrl_width-1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE),
       .offset(1))
   flit_ctrlq
     (.clk(clk),
      .reset(reset),
      .d(flit_ctrl_s[1:flit_ctrl_width-1]),
      .q(flit_ctrl_q[1:flit_ctrl_width-1]));
   
   assign flit_ctrl_out = flit_ctrl_q;
   
   wire [0:flit_data_width-1] 		  flit_data_s, flit_data_q;
   assign flit_data_s = xbr_ctrl ? flit_data_in : flit_data_q;
   c_dff
     #(.width(flit_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_dataq
     (.clk(clk),
      .reset(reset),
      .d(flit_data_s),
      .q(flit_data_q));
   
   assign flit_data_out = flit_data_q;
   
   
   //---------------------------------------------------------------------------
   // error checker logic
   //---------------------------------------------------------------------------
   
   wire [0:1] 				  errors_out;
   c_checker
     #(.num_errors(2),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(error_cred),
      .errors_out(errors_out));
   
   assign error = error_hct | errors_out;
   
endmodule
