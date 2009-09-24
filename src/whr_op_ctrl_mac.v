// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
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
   xbr_ctrl_ip, flit_data_in, flit_ctrl_out, flit_data_out, error);
   
`include "c_functions.v"
`include "c_constants.v"
`include "whr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width required to select a buffer
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // configure error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
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
   wire [0:num_ports-1] gnt_ip;
   
   // crossbar control signals
   output [0:num_ports-1] xbr_ctrl_ip;
   wire [0:num_ports-1] xbr_ctrl_ip;
   
   // incoming flit data
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   // outgoing flit data
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
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
   
   wire 		      cred_valid;
   assign cred_valid = flow_ctrl_q[0];
   
   
   //---------------------------------------------------------------------------
   // arbitration
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] req_int_ip;
   assign req_int_ip = req_ip;
   
   wire                 gnt_int;
   assign gnt_int = |req_int_ip;
   
   wire                 update;
   wire [0:num_ports-1] gnt_int_ip;
   c_arbiter
     #(.num_ports(num_ports),
       .arbiter_type(arbiter_type),
       .reset_type(reset_type))
   gnt_int_ip_arb
     (.clk(clk),
      .reset(reset),
      .update(update),
      .req(req_int_ip),
      .gnt(gnt_int_ip));
   
   wire                 head_free;
   
   wire [0:num_ports-1] new_gnt_ip;
   assign new_gnt_ip = gnt_int_ip & {num_ports{head_free}};
   
   wire 		new_gnt;
   assign new_gnt = gnt_int & head_free;
   
   wire [0:num_ports-1] allocated_ip_s, allocated_ip_q;
   assign allocated_ip_s = update ? gnt_int_ip : allocated_ip_q;
   c_dff
     #(.width(num_ports),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   allocated_ipq
     (.clk(clk),
      .reset(reset),
      .d(allocated_ip_s),
      .q(allocated_ip_q));
   
   wire [0:num_ports-1] held_gnt_ip;
   assign held_gnt_ip = req_ip & allocated_ip_q;
   
   wire                 held_gnt;
   assign held_gnt = |held_gnt_ip;
   
   wire                 free;
   
   wire                 allocated_s, allocated_q;
   assign allocated_s = allocated_q ?
			(~|(held_gnt_ip & req_tail_ip) | ~free) :
			(|(gnt_int_ip & ~req_tail_ip) & head_free & free);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .d(allocated_s),
      .q(allocated_q));
   
   assign update = ~allocated_q & new_gnt;
   
   wire [0:num_ports-1] gnt_unqual_ip;
   assign gnt_unqual_ip = allocated_q ? held_gnt_ip : gnt_int_ip;
   
   assign xbr_ctrl_ip = gnt_unqual_ip;

   wire 		gnt_unqual;
   assign gnt_unqual = allocated_q ? held_gnt : new_gnt;
   
   assign gnt_ip = (allocated_q ? held_gnt_ip : new_gnt_ip) & {num_ports{free}};
   
   wire                 gnt;
   assign gnt = gnt_unqual & free;
   
   
   //---------------------------------------------------------------------------
   // staging for flit control signals
   //---------------------------------------------------------------------------
   
   wire                 flit_valid_in_s, flit_valid_in_q;
   assign flit_valid_in_s = gnt;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_valid_inq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_in_s),
      .q(flit_valid_in_q));
   
   wire                 flit_valid_in;
   assign flit_valid_in = flit_valid_in_q;
   
   // when the output port is not allocated, the next flit must be a head flits;
   // the second term is required to account for cases where the output port 
   // gets allocated, but no credit is available
   wire                 flit_head_s, flit_head_q;
   assign flit_head_s = ~allocated_q | |(held_gnt_ip & req_head_ip);
   c_dff
     #(.width(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_headq
     (.clk(clk),
      .reset(reset),
      .d(flit_head_s),
      .q(flit_head_q));
   
   wire                 flit_head_in;
   assign flit_head_in = flit_head_q;
   
   wire                 flit_tail_s, flit_tail_q;
   assign flit_tail_s = |(gnt_unqual_ip & req_tail_ip);
   c_dff
     #(.width(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_tailq
     (.clk(clk),
      .reset(reset),
      .d(flit_tail_s),
      .q(flit_tail_q));
   
   wire                 flit_tail_in;
   assign flit_tail_in = flit_tail_q;
   
   
   //---------------------------------------------------------------------------
   // track number of packets that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 		update_credits;
   assign update_credits = flit_valid_in | cred_valid;
   
   wire 		credit;
   assign credit = cred_valid;
   
   wire [0:cred_count_width-1] cred_count_q;
   wire 		       error_hct_underflow;
   wire 		       error_hct_overflow;
   
   generate
      
      if(num_header_buffers == num_flit_buffers)
	begin
	   
	   // if every flit buffer entry can be a head flit, we don't need 
	   // dedicated credit tracking for headers, and can instead just rely 
	   // on the normal credit tracking mechanism
	   assign head_free = 1'b1;
	   
	   assign error_hct_underflow = 1'b0;
	   assign error_hct_overflow = 1'b0;
	   
	end
      else
	begin
	   
	   // if only a subset of the flit buffer entries can be headers, we 
	   // need to keep track of how many such slots are left
	   
	   wire head_credit;
	   wire head_debit;
	   
	   if(num_header_buffers == 1)
	     begin
		
		// if we can only have one packet per buffer, we can accept the 
		// next one once the buffer has been completely drained after 
		// the tail has been sent
		
		wire last_credit_received;
		assign last_credit_received
		  = (cred_count_q == (num_flit_buffers - 1)) && credit;
		
		wire tail_sent_q;
		wire head_free_q;
		
		assign head_credit =  tail_sent_q & last_credit_received;
		assign head_debit = head_free_q & gnt;
		
		wire tail_sent_s;
		assign tail_sent_s
		  = update_credits ? 
		    ((tail_sent_q | (flit_valid_in & flit_tail_in)) &
		     ~last_credit_received) : 
		    tail_sent_q;
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		tail_sentq
		  (.clk(clk),
		   .reset(reset),
		   .d(tail_sent_s),
		   .q(tail_sent_q));
		
		wire head_free_s;
		assign head_free_s = (head_free_q & ~head_debit) | head_credit;
		c_dff
		  #(.width(1),
		    .reset_type(reset_type),
		    .reset_value(1'b1))
		head_freeq
		  (.clk(clk),
		   .reset(reset),
		   .d(head_free_s),
		   .q(head_free_q));
		
		assign head_free = head_free_q;
		
		assign error_hct_underflow = head_debit & ~head_free_q;
		assign error_hct_overflow = head_credit & head_free_q;
		
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
		assign push_ptr_s
		  = update_credits ? 
		    (flit_valid_in ? push_ptr_next : push_ptr_q) : 
		    push_ptr_q;
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
		assign pop_ptr_s
		  = update_credits ? 
		    (cred_valid ? pop_ptr_next : pop_ptr_q) : 
		    pop_ptr_q;
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
		  if(update_credits)
		    if(flit_valid_in)
		      tail_queue[push_ptr_q] <= flit_tail_in;
		
		wire 				 tail;
		assign tail = tail_queue[pop_ptr_q];
		
		assign head_credit = credit & tail;
		assign head_debit = ~allocated_q & new_gnt & free;
		
		// track header credits using stock credit tracker module
		wire 				 head_free_early;
		wire [0:1] 			 hct_errors;
		c_credit_tracker
		  #(.num_credits(num_header_buffers),
		    .reset_type(reset_type))
		hct
		  (.clk(clk),
		   .reset(reset),
		   .credit(head_credit),
		   .debit(head_debit),
		   .free(head_free),
		   .free_early(head_free_early),
		   .errors(hct_errors));
		
		assign error_hct_underflow = hct_errors[0];
		assign error_hct_overflow = hct_errors[1];
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // track number of flits that downstream buffer can still accept
   //---------------------------------------------------------------------------
   
   wire 					 credit_b;
   assign credit_b = ~credit;
   
   wire [0:cred_count_width-1] 			 cred_count_debit;
   assign cred_count_debit = cred_count_q - credit_b;
   
   wire [0:cred_count_width-1] 			 cred_count_nodebit;
   assign cred_count_nodebit = cred_count_q + credit;
   
   wire 					 debit;
   assign debit = gnt;
   
   wire [0:cred_count_width-1] 			 cred_count_s;   
   assign cred_count_s = debit ? cred_count_debit : cred_count_nodebit;
   c_dff
     #(.width(cred_count_width),
       .reset_type(reset_type),
       .reset_value(num_flit_buffers))
   cred_countq
     (.clk(clk),
      .reset(reset),
      .d(cred_count_s),
      .q(cred_count_q));
   
   wire 					 error_ct_underflow;
   assign error_ct_underflow = (cred_count_q == 0) && debit;
   
   wire 					 error_ct_overflow;
   assign error_ct_overflow = (cred_count_q == num_flit_buffers) && credit;
   
   // Instead of just computing this as the reduction of of the updated credit
   // count sum, we can optimize a bit. In particular, we have one or more 
   // credits available iff...
   //  a) ... we just received a credit. In this case, we either had credits 
   //     available to begin with, or there cannot be a debit at the same time.
   //  b) ... we currently have at least two credits available. In this case,
   //     even if there is a debit and no credit, we will still have at least
   //     one credit left.
   //  c) ... we currently have an off number of credits available, and did not
   //     just receive a debit. For odd numbers greater than one, we will always
   //     have credit left, and in case we have one credit left, we will still
   //     have at least one left if no debit occurs.
   // This only leaves out the case where we are not receiving a credit, do not
   // currently have two or more credits and either have no credits left or have
   // a single credit left and receive a debit.
   wire 					 cred_s, cred_q;
   assign cred_s = credit | 
		   |cred_count_q[0:cred_count_width-2] | 
		   (cred_count_q[cred_count_width-1] & ~debit);
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
   // output staging
   //---------------------------------------------------------------------------
   
   wire [0:flit_ctrl_width-1] 		         flit_ctrl_s, flit_ctrl_q;
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     assign flit_ctrl_s[0] = flit_valid_in;
	     
	     wire flit_valid_s, flit_valid_q;
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
	     
   	     assign flit_ctrl_s[1]
		      = flit_valid_in ? flit_head_in : flit_ctrl_q[1];
	     
	     c_dff
	       #(.width(flit_ctrl_width-1),
		 .reset_type(/*reset_type*/ `RESET_TYPE_NONE),
		 .offset(1))
	     flit_ctrlq
	       (.clk(clk),
		.reset(reset),
		.d(flit_ctrl_s[1:flit_ctrl_width-1]),
		.q(flit_ctrl_q[1:flit_ctrl_width-1]));
	     
	  end
	
      endcase
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     
	     assign flit_ctrl_s[2]
		      = flit_valid_in ? flit_tail_in : flit_ctrl_q[2];
	     
	  end
	
      endcase
      
   endgenerate
   
   assign flit_ctrl_out = flit_ctrl_q;
   
   wire [0:flit_data_width-1] 		         flit_data_s, flit_data_q;
   assign flit_data_s = flit_valid_in ? flit_data_in : flit_data_q;
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
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   wire [0:3] errors_s, errors_q;
	   assign errors_s = {error_ct_underflow,
			      error_ct_overflow,
			      error_hct_underflow,
			      error_hct_overflow};
	   c_err_rpt
	     #(.num_errors(4),
	       .capture_mode(error_capture_mode),
	       .reset_type(reset_type))
	   chk
	     (.clk(clk),
	      .reset(reset),
	      .errors_in(errors_s),
	      .errors_out(errors_q));
	   
	   assign error = |errors_q;
	   
	end
      else
	assign error = 1'b0;
      
   endgenerate
   
endmodule
