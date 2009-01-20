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
  (clk, reset, flit_valid, flit_head, flit_tail, flit_vc, flit_data, cred_valid,
   cred_vc, run, out_flits, error);
   
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
   
   parameter max_packet_count = 1000;
   parameter packet_rate = 25;
   parameter initial_seed = 0;
   parameter packet_count_width = 32;

   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // nuber of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 2;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = num_ports + ((num_routing_classes > 1) ? 1 : 0);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // current router's address
   parameter [0:router_addr_width-1] router_address = {router_addr_width{1'b0}};
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   localparam num_nodes_per_router
     = num_ports - num_dimensions * num_neighbors_per_dim;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_routing_classes * router_addr_width + node_addr_width;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // ID of current port
   parameter port_id = 0;
   
   // maximum packet length (in flits)
   parameter max_packet_length = 8;
   
   // minimum packet length (in flits)
   parameter min_packet_length = 8;
   
   // select packet length mode (0: uniform random, 1: bimodal)
   parameter packet_length_mode = 0;
   
   // total number of bits required to represent maximum packet length
   localparam packet_length_width = clogb(max_packet_length);
   
   // total number of bits required for storing header information
   localparam header_info_width
     = la_route_info_width + route_info_width + packet_length_width;
   
   // flit width
   parameter data_width = 64;
   
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   input clk;
   input reset;
   
   output flit_valid;
   wire flit_valid;
   
   output flit_head;
   wire flit_head;
   
   output flit_tail;
   wire flit_tail;
   
   output [0:vc_idx_width-1] flit_vc;
   wire [0:vc_idx_width-1] flit_vc;
   
   output [0:data_width-1] flit_data;
   wire [0:data_width-1]   flit_data;
   
   input cred_valid;
   
   input [0:vc_idx_width-1] cred_vc;
   
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
	  <= ($dist_uniform(seed, 0, 99) < packet_rate) && run && !reset;
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
	begin
	   assign waiting_packet_count_zero = 1'b0;
	end
   endgenerate
   
   wire 			  packet_sent;
   
   wire 			  ready_packet_count_zero;
   wire [0:packet_count_width-1]  ready_packet_count_s, ready_packet_count_q;
   assign ready_packet_count_s
     = run ?
       ready_packet_count_q - (packet_sent & ~ready_packet_count_zero) + 
       packet_ready :
       {packet_count_width{1'b0}};
   dff
     #(.width(packet_count_width))
   ready_packet_countq
     (.clk(clk),
      .reset(reset),
      .d(ready_packet_count_s),
      .q(ready_packet_count_q));
   
   assign ready_packet_count_zero = ~|ready_packet_count_q;
   
   wire 			  flit_sent;
   assign flit_valid = flit_sent;
   
   reg [0:vc_idx_width-1] 	  vc_q;
   assign flit_vc = vc_q;
   
   wire [0:num_vcs-1] 		  free_ovc;
   wire [0:num_vcs-1] 		  head_free_ovc;
   
   wire [0:num_vcs-1] 		  error_hct_ovc;
   wire [0:num_vcs*2-1] 	  error_cred_ovc;
   
   genvar 			  ovc;
   
   generate
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   assign credit = cred_valid && (cred_vc == ovc);
	   
	   wire debit;
	   assign debit = flit_sent && (vc_q == ovc);
	   
	   wire head_credit;
	   wire [0:cred_count_width-1] cred_count_s;
	   
	   if(num_header_buffers > 1)
	     begin
		
		wire [0:num_flit_buffers-1] push_mask;
		wire [0:num_flit_buffers-1] pop_mask;
		
		wire [0:num_flit_buffers-1] tail_queue_s, tail_queue_q;
		assign tail_queue_s
		  = (tail_queue_q & ~({num_flit_buffers{credit}} & pop_mask)) |
		    ({num_flit_buffers{debit & flit_tail}} & push_mask);
		dff
		  #(.width(num_flit_buffers))
		tail_queueq
		  (.clk(clk),
		   .reset(reset),
		   .d(tail_queue_s),
		   .q(tail_queue_q));
		
		wire [0:flit_buffer_idx_width-1] push_ptr_q, push_ptr_next;
		incr
		  #(.width(flit_buffer_idx_width),
		    .min_value(0),
		    .max_value(num_flit_buffers-1))
		push_ptr_incr
		  (.data_in(push_ptr_q),
		   .data_out(push_ptr_next));
		
		wire [0:flit_buffer_idx_width-1] push_ptr_s;
		assign push_ptr_s = debit ? push_ptr_next : push_ptr_q;
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
		
		wire [0:flit_buffer_idx_width-1] pop_ptr_q, pop_ptr_next;
		incr
		  #(.width(flit_buffer_idx_width),
		    .min_value(0),
		    .max_value(num_flit_buffers-1))
		pop_ptr_incr
		  (.data_in(pop_ptr_q),
		   .data_out(pop_ptr_next));

		wire [0:flit_buffer_idx_width-1] pop_ptr_s;
		assign pop_ptr_s = credit ? pop_ptr_next : pop_ptr_q;
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
		
		assign head_credit = |(tail_queue_q & pop_mask) & credit;
		
	     end
	   else
	     begin

		// if we can only have one packet per buffer, we can accept the
		// next one once the buffer has been emptied
		assign head_credit = credit &&
				     (cred_count_s == num_flit_buffers);
		
	     end
	   
	   wire 			    head_debit;
	   assign head_debit = debit & flit_head;
	   
	   // track header credits using stock credit tracker module
	   wire 			    head_free;
	   wire 			    head_free_early;
	   wire 			    error_hct;
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
	   
	   wire [0:cred_count_width-1] cred_count_q;
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
	   
	   wire [0:1] 		       error_cred;
	   assign error_cred = {(cred_count_q == num_flit_buffers) && credit,
				(cred_count_q == 0) && debit};
	   
	   assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
	   
	end
      
   endgenerate
   
   wire 			       free;
   mux_nto1
     #(.num_ports(num_vcs),
       .width(1))
   free_mux
     (.select(vc_q),
      .data_in(free_ovc),
      .data_out(free));

   wire 			       head_free;
   mux_nto1
     #(.num_ports(num_vcs),
       .width(1))
   head_free_mux
     (.select(vc_q),
      .data_in(head_free_ovc),
      .data_out(head_free));
   
   wire 			       flit_valid_q;
   assign flit_sent = flit_valid_q & free & (head_free | ~flit_head);
   
   assign packet_sent = flit_tail & flit_sent;
   
   wire 			       flit_valid_s;
   assign flit_valid_s = flit_valid_q ?
			 ~(flit_sent & flit_tail) :
			 ~ready_packet_count_zero;
   dff
     #(.width(1))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   reg [0:data_width-1] 	  data_q;
   always @(posedge clk, posedge reset)
     begin
	if(reset | flit_sent)
	  for(i = 0; i < data_width; i = i + 1)
	    data_q[i] <= $dist_uniform(seed, 0, 1);
     end
   
   wire [0:route_info_width-1] route_info;
   wire [0:num_vcs*la_route_info_width-1] la_route_info_ivc;
   wire [0:num_vcs-1] 			  rtl_error_ivc;
   
   generate
      
      genvar 				  itc;
      
      for(itc = 0; itc < num_traffic_classes; itc = itc + 1)
	begin:itcs
	   
	   genvar irc;
	   
	   for(irc = 0; irc < num_routing_classes; irc = irc + 1)
	     begin:ircs
		
		wire [0:((irc == (num_routing_classes - 1)) ?
			 addr_width :
			 router_addr_width)-1] vc_route_info;
		
		assign vc_route_info[0:router_addr_width-1]
			 = route_info[irc*router_addr_width:
				      (irc+1)*router_addr_width-1];
		
		if((irc == (num_routing_classes - 1)) &&
		   (num_nodes_per_router > 1))
		  assign vc_route_info[router_addr_width:addr_width-1]
			   = route_info[num_routing_classes*
					router_addr_width:
					num_routing_classes*
					router_addr_width+node_addr_width-1];
		
		wire 			       rtl_error;
		wire [0:num_ports-1] 	       next_port;
		wire [0:num_classes-1] 	       next_class;
		routing_logic
		  #(.num_traffic_classes(num_traffic_classes),
		    .num_routing_classes(num_routing_classes),
		    .num_vcs_per_class(num_vcs_per_class),
		    .num_ports(num_ports),
		    .num_dimensions(num_dimensions),
		    .num_routers_per_dim(num_routers_per_dim),
		    .num_neighbors_per_dim(num_neighbors_per_dim),
		    .routing_function_type(routing_function_type),
		    .dimension_order(dimension_order),
		    .port_id(port_id),
		    .traffic_class(itc),
		    .routing_class(irc))
		rtl
		  (.router_address(router_address),
		   .vc_route_info(vc_route_info),
		   .next_port(next_port),
		   .next_class(next_class),
		   .error(rtl_error));
		
		wire [0:la_route_info_width-1] la_route_info;
		
		assign la_route_info[0:num_ports-1] = next_port;
		
		if(num_routing_classes > 1)
		  assign la_route_info[num_ports]
			   = ~next_class[itc*num_routing_classes+irc];
		
		assign la_route_info_ivc[(itc*num_routing_classes+irc)*
					 num_vcs_per_class*
					 la_route_info_width:
					 (itc*num_routing_classes+irc+1)*
					 num_vcs_per_class*
					 la_route_info_width-1]
		    = {num_vcs_per_class{la_route_info}};
		
		assign rtl_error_ivc[(itc*num_routing_classes+irc)*
				     num_vcs_per_class:
				     (itc*num_routing_classes+irc+1)*
				     num_vcs_per_class-1]
			 = {num_vcs_per_class{rtl_error}};
		
	     end
	   
	end
      
   endgenerate
   
   wire [0:la_route_info_width-1] 	  la_route_info;
   assign la_route_info
     = la_route_info_ivc[vc_q*la_route_info_width +: la_route_info_width];
   
   assign flit_data[0:la_route_info_width-1]
	    = flit_head ?
	      la_route_info :
	      data_q[0:la_route_info_width-1];
   
   generate
      
      genvar 				  irc;
      
      for(irc = 0; irc < num_routing_classes; irc = irc + 1)
	begin:ircs
	   
	   reg [0:router_addr_width-1] 		  router_addr_q;
	   always @(posedge clk, posedge reset)
	     begin
		if(reset | packet_sent)
		  router_addr_q
		    <= router_address + 
		       $dist_uniform(seed, 1, 2**router_addr_width-1);
	     end
	   
	   assign route_info[irc*router_addr_width:(irc+1)*router_addr_width-1]
		    = router_addr_q;
	   
	end
      
      if(num_nodes_per_router > 1)
	begin
	   
	   reg [0:node_addr_width-1] node_addr_q;
	   always @(posedge clk, posedge reset)
	     begin
		if(reset | packet_sent)
		  node_addr_q
		    <= $dist_uniform(seed, 0, num_nodes_per_router-1);
	     end
	   
	   assign route_info[route_info_width-node_addr_width:
			     route_info_width-1]
		    = node_addr_q;
	   
	end
      
   endgenerate
   
   assign flit_data[la_route_info_width:
		    la_route_info_width+route_info_width-1]
	    = flit_head ?
	      route_info :
	      data_q[la_route_info_width:
		     la_route_info_width+route_info_width-1];
   
   generate
      
      if(max_packet_length > 1)
	begin
	   
	   reg [0:packet_length_width-1] random_length_q;
	   reg [0:packet_length_width-1] flit_count_q;
	   reg 				 tail_q;
	   always @(posedge clk, posedge reset)
	     begin
		case(packet_length_mode)
		  0:
		    random_length_q <= $dist_uniform(seed, min_packet_length-1,
						     max_packet_length-1);
		  1:
		    random_length_q <= ($dist_uniform(seed, 0, 1) < 1) ?
				       min_packet_length :
				       max_packet_length;
		endcase
		if(reset)
		  begin
		     flit_count_q <= min_packet_length-1;
		     tail_q <= ~|(min_packet_length-1);
		  end
		else if(packet_sent)
		  begin
		     flit_count_q <= random_length_q;
		     tail_q <= ~|random_length_q;
		  end
		else if(flit_sent)
		  begin
		     flit_count_q <= flit_count_q - |flit_count_q;
		     tail_q <= ~|(flit_count_q - |flit_count_q);
		  end
	     end
	   
	   wire head_s, head_q;
	   assign head_s = (head_q & ~flit_sent) | packet_sent;
	   dff
	     #(.width(1),
	       .reset_value(1'b1))
	   headq
	     (.clk(clk),
	      .reset(reset),
	      .d(head_s),
	      .q(head_q));
	   
	   assign flit_head = head_q;
	   assign flit_tail = tail_q;
	   
	   assign flit_data[la_route_info_width+route_info_width:
			    la_route_info_width+route_info_width+
			    packet_length_width-1]
		    = flit_head ?
		      flit_count_q :
		      data_q[la_route_info_width+route_info_width:
			     la_route_info_width+route_info_width+
			     packet_length_width-1];
	   
	end
      else
	begin
	   assign flit_head = 1'b1;
	   assign flit_tail = 1'b1;
	end
      
   endgenerate
   
   assign flit_data[la_route_info_width+route_info_width+packet_length_width:
		    data_width-1]
	    = data_q[la_route_info_width+route_info_width+packet_length_width:
		     data_width-1];
   
   always @(posedge clk, posedge reset)
     begin
	if(reset | packet_sent)
	  vc_q <= $dist_uniform(seed, 0, num_vcs-1);
     end
   
   wire 				  rtl_error;
   assign rtl_error = |rtl_error_ivc;
   
   assign error = |error_hct_ovc | |error_cred_ovc;
   
   wire [0:packet_count_width-1] out_flits_s, out_flits_q;
   assign out_flits_s = out_flits_q + flit_sent;
   dff
     #(.width(packet_count_width))
   out_flitsq
     (.clk(clk),
      .reset(reset),
      .d(out_flits_s),
      .q(out_flits_q));
   
   assign out_flits = out_flits_s;
   
endmodule
