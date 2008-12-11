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

module packet_source
  (clk, reset, flit_ctrl_out, flit_data_out, flow_ctrl_in, run, out_flits, 
   error);
   
`include "constants.v"
   
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
   
   // width required to select individual flit buffer entry
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 8;
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // width of global addresses
   parameter addr_width = 6;
   
   // address of current packet source
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   // total number of bits required for storing routing information
   localparam route_info_width = 2 * addr_width;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_HEAD_TAIL;
   
   // width of control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ?
       // (valid + head/tail + vc_id)
       (1 + 2 + vc_idx_width) :
       -1;
   
   // select flow control type
   parameter flow_control_type = `FLOW_CONTROL_TYPE_CREDIT;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_control_type == `FLOW_CONTROL_TYPE_CREDIT) ?
       // (valid + vc_id)
       (1 + vc_idx_width) :
       -1;
   
   // maximum packet length (in flits)
   parameter max_packet_length = 4;
   
   // minimum packet length (in flits)
   parameter min_packet_length = 1;
   
   // select packet length mode (0: uniform random, 1: bimodal)
   parameter packet_length_mode = 0;
   
   // total number of bits required to represent maximum packet length
   localparam packet_length_width = clogb(max_packet_length);
   
   // total number of bits required for storing header information
   localparam head_info_width = route_info_width + packet_length_width;
   
   // flit width
   parameter flit_data_width = 64;
   
   parameter initial_seed = 0;
   parameter max_packet_count = 1000;
   parameter packet_rate = 25;
   parameter adaptive_rate = 0;
   parameter packet_count_width = 32;
   
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   input clk;
   input reset;
   
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   input run;
   
   output [0:packet_count_width-1] out_flits;
   wire [0:packet_count_width-1] out_flits;
   
   output error;
   wire 			 error;
   
   integer 			 seed = initial_seed;
   
   integer 			 i;
   
   reg 				 new_packet;   
   always @(posedge clk, posedge reset)
     begin
	new_packet
	  = ($dist_uniform(seed, 0, 99) < packet_rate) &&
	    run && !reset;
     end
   
   wire waiting_packet_count_zero;
   
   wire packet_ready;
   assign packet_ready = new_packet & ~waiting_packet_count_zero;
   
   generate
      
      if(max_packet_count >= 0)
	begin
	   
	   wire [0:packet_count_width-1] waiting_packet_count_s,
					 waiting_packet_count_q;
	   assign waiting_packet_count_s
	     = waiting_packet_count_q - packet_ready;
	   dff
	     #(.width(packet_count_width),
	       .reset_value(max_packet_count))
	   waiting_packet_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(waiting_packet_count_s),
	      .q(waiting_packet_count_q));
	   
	   assign waiting_packet_count_zero = ~|waiting_packet_count_q;
	   
	end
      else
	assign waiting_packet_count_zero = 1'b0;
      
   endgenerate
   
   wire 				 packet_sent;
   
   wire [0:packet_count_width-1] 	 ready_packet_count_s,
					 ready_packet_count_q;
   assign ready_packet_count_s
     = run ?
       ready_packet_count_q - packet_sent + packet_ready :
       {packet_count_width{1'b0}};
   dff
     #(.width(packet_count_width))
   ready_packet_countq
     (.clk(clk),
      .reset(reset),
      .d(ready_packet_count_s),
      .q(ready_packet_count_q));
   
   wire 				 ready_packet_count_zero;
   assign ready_packet_count_zero = ~|ready_packet_count_q;
   
   wire 				 flit_count_max;
   wire 				 flit_count_zero;
   wire 				 flit_sent;
   wire [0:num_vcs-1] 			 flit_sent_ovc;
   
   wire [0:num_vcs-1] 			 free_ovc;
   wire [0:num_vcs-1] 			 head_free_ovc;
   
   wire [0:num_vcs-1] 			 error_hct_ovc;
   wire [0:num_vcs*2-1] 		 error_cred_ovc;
   
   genvar 				 ovc;
   
   generate
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   case(flow_control_type)
	     
	     `FLOW_CONTROL_TYPE_CREDIT:
	       begin
		  
		  wire cred_valid;
		  
		  if(num_vcs > 1)
		    begin
		       
		       wire [0:vc_idx_width-1] cred_vc;
		       assign cred_vc = flow_ctrl_in[1:1+vc_idx_width-1];
		       
		       assign cred_valid = flow_ctrl_in[0] && (cred_vc == ovc);
		       
		    end
		  else
		    assign cred_valid = flow_ctrl_in[0];
		  
		  wire 			       credit;
		  assign credit = cred_valid;
		  
		  wire 			       debit;
		  assign debit = flit_sent_ovc[ovc];
		  
		  wire [0:cred_count_width-1]  cred_count_s;
		  
		  if(num_header_buffers == num_flit_buffers)
		    begin
		       
		       assign head_free_ovc[ovc] = 1'b1;
		       assign error_hct_ovc[ovc] = 1'b0;
		       
		    end
		  else
		    begin
		       
		       wire head_credit;
		       
		       if(num_header_buffers == 1)
			 begin
			    
			    // if we can only have one packet per buffer, we can
			    // accept the next one once the buffer has been 
			    // emptied
			    assign head_credit
			      = credit && (cred_count_s == num_flit_buffers);
			    
			 end
		       else
			 begin
			    
			    wire [0:num_flit_buffers-1] push_mask;
			    wire [0:num_flit_buffers-1] pop_mask;
			    
			    wire [0:num_flit_buffers-1] tail_queue_s, 
							tail_queue_q;
			    assign tail_queue_s
			      = (tail_queue_q & ~({num_flit_buffers{credit}} &
						  pop_mask)) |
				({num_flit_buffers{debit & flit_tail}} &
				 push_mask);
			    dff
			      #(.width(num_flit_buffers))
			    tail_queueq
			      (.clk(clk),
			       .reset(reset),
			       .d(tail_queue_s),
			       .q(tail_queue_q));
			    
			    wire [0:flit_buffer_idx_width-1] push_ptr_q,
							     push_ptr_next;
			    incr
			      #(.width(flit_buffer_idx_width),
				.min_value(0),
				.max_value(num_flit_buffers-1))
			    push_ptr_incr
			      (.data_in(push_ptr_q),
			       .data_out(push_ptr_next));
			    
			    wire [0:flit_buffer_idx_width-1] push_ptr_s;
			    assign push_ptr_s
			      = debit ? push_ptr_next : push_ptr_q;
			    dff
			      #(.width(flit_buffer_idx_width))
			    push_ptrq
			      (.clk(clk),
			       .reset(reset),
			       .d(push_ptr_s),
			       .q(push_ptr_q));
			    
			    decoder
			      #(.num_ports(num_flit_buffers))
			    push_mask_dec
			      (.data_in(push_ptr_q),
			       .data_out(push_mask));
			    
			    wire [0:flit_buffer_idx_width-1] pop_ptr_q, 
							     pop_ptr_next;
			    incr
			      #(.width(flit_buffer_idx_width),
				.min_value(0),
				.max_value(num_flit_buffers-1))
			    pop_ptr_incr
			      (.data_in(pop_ptr_q),
			       .data_out(pop_ptr_next));
			    
			    wire [0:flit_buffer_idx_width-1] pop_ptr_s;
			    assign pop_ptr_s
			      = credit ? pop_ptr_next : pop_ptr_q;
			    dff
			      #(.width(flit_buffer_idx_width))
			    pop_ptrq
			      (.clk(clk),
			       .reset(reset),
			       .d(pop_ptr_s),
			       .q(pop_ptr_q));
			    
			    decoder
			      #(.num_ports(num_flit_buffers))
			    pop_mask_dec
			      (.data_in(pop_ptr_q),
			       .data_out(pop_mask));
			    
			    assign head_credit
			      = |(tail_queue_q & pop_mask) & credit;
			    
			 end
		       
		       wire 				     head_debit;
		       assign head_debit = debit & flit_count_max;
		       
		       // track header credits using stock credit tracker module
		       wire 				     head_free;
		       wire 				     head_free_early;
		       wire 				     error_hct;
		       credit_tracker
			 #(.num_credits(num_header_buffers),
			   .checker_enable(1),
			   .checker_capture_mode(0))
		       hct
			 (.clk(clk),
			  .reset(reset),
			  .credit(head_credit),
			  .debit(head_debit),
			  .free(head_free),
			  .free_early(head_free_early),
			  .error(error_hct));
		       
		       assign head_free_ovc[ovc] = head_free;
		       assign error_hct_ovc[ovc] = error_hct;
		       
		    end
		  
		  wire [0:cred_count_width-1] 		     cred_count_q;
		  assign cred_count_s = cred_count_q + credit - debit;
		  dff
		    #(.width(cred_count_width),
		      .reset_value(num_flit_buffers))
		  cred_countq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_count_s),
		     .q(cred_count_q));
		  
		  assign free_ovc[ovc] = |cred_count_q;
		  
		  wire [0:1] 				     error_cred;
		  assign error_cred
		    = {(cred_count_q == num_flit_buffers) && credit,
		       (cred_count_q == 0) && debit};
		  
		  assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
		  
	       end
	     
	   end
      
      if(num_vcs > 1)
	begin
	   
	   mux_nto1
	     #(.num_ports(num_vcs),
	       .width(1))
	   free_mux
	     (.select(vc_q),
	      .data_in(free_ovc),
	      .data_out(free));
	   
	   mux_nto1
	     #(.num_ports(num_vcs),
	       .width(1))
	head_free_mux
	  (.select(vc_q),
	   .data_in(head_free_ovc),
	   .data_out(head_free));
	   
	end
      else
	begin
	   assign free = free_ovc;
	   assign head_free = head_free_ovc;
	end
      
   endgenerate
   
   wire free;
   wire head_free;
   
   wire flit_valid_q;
   assign flit_sent = flit_valid_q & free & (head_free | ~flit_count_max);
   
   assign packet_sent = flit_count_zero & flit_sent;
   
   wire flit_valid_s;
   assign flit_valid_s = ~ready_packet_count_zero |
			 (flit_valid_q & ~(flit_sent & flit_count_zero));
   dff
     #(.width(1))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   generate
      
      if(max_packet_length > 1)
	begin
	   
	   wire [0:packet_length_width-1] packet_length;
	   assign packet_length
	     = random_head_info[route_info_width:
				route_info_width+packet_length_width-1];
	   
	   wire [0:packet_length_width-1] flit_count_s;
	   reg [0:packet_length_width-1]  flit_count_q;
	   assign flit_count_s = packet_sent ?
				 packet_length :
				 (flit_count_q - flit_sent);
	   always @(posedge clk, posedge reset)
	     if(reset)
	       flit_count_q <= packet_length;
	     else
	       flit_count_q <= flit_count_s;
	   
	   wire 			  head_s, head_q;
	   assign head_s = (head_q & ~flit_sent) | packet_sent;
	   dff
	     #(.width(1),
	       .reset_value(1'b1))
	   headq
	     (.clk(clk),
	      .reset(reset),
	      .d(head_s),
	      .q(head_q));
	   
	   assign flit_count_max = head_q;
	   assign flit_count_zero = ~|flit_count_q;
	   
	end
      else
	begin
	   assign flit_count_max = 1'b1;
	   assign flit_count_zero = 1'b1;
	end
      
   endgenerate
   
   reg [0:flit_data_width-1] data_q;
   always @(posedge clk, posedge reset)
     begin
	if(reset | flit_sent)
	  begin
	     for(i = 0; i < flit_data_width; i = i + 1)
	       data_q[i] = $dist_uniform(seed, 0, 1);
	     if(packet_sent)
	       begin
		  data_q[0:addr_width-1]
		    = address + $dist_uniform(seed, 1, 2**addr_width-1);
		  data_q[addr_width:(2*addr_width)-1]
		    = address + $dist_uniform(seed, 1, 2**addr_width-1);
		  if(max_packet_length > 1)
		    case(packet_length_mode)
		      0:
			data_q[route_info_width:
			       route_info_width+packet_length_width-1]
			= $dist_uniform(seed, min_packet_length-1,
					max_packet_length-1);
		      1:
			data_q[route_info_width:
			       route_info_width+packet_length_width-1]
			= ($dist_uniform(seed, 0, 1) < 1) ?
			  min_packet_length :
			  max_packet_length;
		    endcase
	       end
	  end
     end
   
   assign flit_valid = flit_sent;
   assign flit_head = flit_count_max;
   assign flit_tail = flit_count_zero;
   assign flit_data = data_q;

   reg [0:vc_idx_width-1] vc_q;
   always @(posedge clk, posedge reset)
     begin
	if(reset | packet_sent)
	  vc_q = $dist_uniform(seed, 0, num_vcs-1);
     end
   
   assign flit_vc = vc_q;

   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL:
	  begin
	     
	     assign flit_ctrl_out[0] = flit_valid;
	     assign flit_ctrl_out[1] = flit_head;
	     assign flit_ctrl_out[2] = flit_tail;
	     
	     if(num_vcs > 1)
	       begin
		  assign flit_ctrl_out[3:3+vc_idx_width-1] = flit_vc;
	       end
	     
	  end
	
      endcase
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:num_vcs-1] flit_vc_1hot;
	   decoder
	     #(.num_ports(num_vcs))
	   flit_vc_1hot_dec
	     (.data_in(flit_vc),
	      .data_out(flit_vc_1hot));
	   
	   assign flit_sent_ovc = {num_vcs{flit_sent}} & flit_vc_1hot;
	   
	end
      else
	assign flit_sent_ovc = flit_sent;
      
   endgenerate
   
   assign error = |error_hct_ovc | |error_cred_ovc;
   
   wire [0:packet_count_width-1] out_flits_s, out_flits_q;
   assign out_flits_s = out_flits_q + flit_valid;
   dff
     #(.width(packet_count_width))
   out_flitsq
     (.clk(clk),
      .reset(reset),
      .d(out_flits_s),
      .q(out_flits_q));
   
   assign out_flits = out_flits_s;
   
endmodule
