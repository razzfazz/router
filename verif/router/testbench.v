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

module testbench
  ();
   
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
   
   // compute ceiling of base-th root of argument
   function integer croot(input integer argument, input integer base);
      integer 		     i;
      integer 		     j;
      begin
	 croot = 0;
	 i = 0;
	 while(i < argument)
	   begin
	      croot = croot + 1;
	      i = 1;
	      for(j = 0; j < base; j = j + 1)
		i = i * croot;
	   end
      end
   endfunction
   
   // population count (count ones)
   function integer pop_count(input integer argument);
      integer i;
      begin
	 pop_count = 0;
	 for(i = argument; i > 0; i = i >> 1)
	   pop_count = pop_count + (i & 1);
      end
   endfunction
   
   parameter Tclk = 2;
   parameter initial_seed = 0;
   parameter max_packet_count = -1;
   parameter packet_rate = 25;
   parameter packet_count_width = 32;
   parameter credit_latency = 6;
   parameter warmup_time = 1000;
   parameter measure_time = 100000;
   
   // select network topology
   parameter network_topology = `NETWORK_TOPOLOGY_MESH;
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 1;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 1;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // total number of nodes
   parameter num_nodes = 64;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 4;

   // total number of routers
   localparam num_routers
     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   
   // number of routers in each dimension
   localparam num_routers_per_dim = croot(num_routers, num_dimensions);
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // current router's address
   parameter [0:router_addr_width-1] router_address = {router_addr_width{1'b0}};
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       2 :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = port_idx_width + ((num_routing_classes > 1) ? 1 : 0);
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_routing_classes * router_addr_width + node_addr_width;
   
   // maximum packet length (in flits)
   parameter max_packet_length = 8;
   
   // minimum packet length (in flits)
   parameter min_packet_length = 1;
   
   // select packet length mode (0: uniform random, 1: bimodal)
   parameter packet_length_mode = 0;
   
   // total number of bits required to represent maximum packet length
   localparam packet_length_width = clogb(max_packet_length);
   
   // total number of bits required for storing header information
   localparam header_info_width
     = la_route_info_width + route_info_width + packet_length_width;
   
   // flit width
   parameter data_width = 64;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select routing function type
   localparam routing_function_type
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       `ROUTING_FUNCTION_TYPE_MESH :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       `ROUTING_FUNCTION_TYPE_FBFLY :
       -1;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   // enable speculative switch allocation
   localparam sw_spec_enable = (sw_spec_level == `SW_SPEC_LEVEL_NONE) ?
			       0 :
			       1;
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   reg 		    reset;
   reg 		    clk;
   
   wire [0:num_ports-1] flit_valid_in_ip;
   wire [0:num_ports*vc_idx_width-1] flit_vc_in_ip;
   wire [0:num_ports-1] 	     flit_head_in_ip;
   wire [0:num_ports-1] 	     flit_tail_in_ip;
   wire [0:num_ports*data_width-1]   flit_data_in_ip;
   wire [0:num_ports-1] 	     cred_valid_out_ip;
   wire [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   wire [0:num_ports-1] 	     flit_valid_out_op;
   wire [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   wire [0:num_ports-1] 	     flit_head_out_op;
   wire [0:num_ports-1] 	     flit_tail_out_op;
   wire [0:num_ports*data_width-1]   flit_data_out_op;
   wire [0:num_ports-1] 	     cred_valid_in_op;
   wire [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   wire [0:num_ports-1] 	     ps_error_ip;
   wire [0:num_ports-1] 	     rtl_error_ip;
   wire [0:num_ports*num_vcs*num_ports-1] match_ip_ivc_op;
   wire [0:num_ports*num_vcs-1] 	  fifo_error_ip_ivc;
   
   reg 					  run;
   
   generate
      
      genvar 				  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   if(ip < num_ports - num_nodes_per_router)
	     begin
		
		assign flit_valid_in_ip[ip] = 1'b0;
		assign flit_vc_in_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]
			 = {vc_idx_width{1'b0}};
		assign flit_head_in_ip[ip] = 1'b0;
		assign flit_tail_in_ip[ip] = 1'b0;
		assign flit_data_in_ip[ip*data_width:(ip+1)*data_width-1]
			 = {data_width{1'b0}};
		assign ps_error_ip[ip] = 1'b0;
		assign rtl_error_ip[ip] = 1'b0;
		assign match_ip_ivc_op[ip*num_vcs*num_ports:
				       (ip+1)*num_vcs*num_ports-1]
			 = {num_vcs*num_ports{1'b0}};
		assign fifo_error_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
			 = {num_vcs{1'b0}};
		
	     end
	   else
	     begin
		
		wire cred_valid;
		wire [0:vc_idx_width-1] cred_vc;
		
		wire [0:credit_latency-1] cred_valid_dly_s,
					  cred_valid_dly_q;
		wire [0:credit_latency*vc_idx_width-1] cred_vc_dly_s,
						       cred_vc_dly_q;
		
		if(credit_latency > 1)
		  begin
		     assign cred_valid_dly_s
		       = {cred_valid_out_ip[ip],
			  cred_valid_dly_q[0:(credit_latency-1)-1]};
		     assign cred_valid
		       = cred_valid_dly_q[(credit_latency-1):credit_latency-1];
		     assign cred_vc_dly_s
		       = {cred_vc_out_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1],
			  cred_vc_dly_q[0:vc_idx_width*(credit_latency-1)-1]};
		     assign cred_vc
		       = cred_vc_dly_q[vc_idx_width*(credit_latency-1):
				       vc_idx_width*credit_latency-1];
		  end
		else
		  begin
		     assign cred_valid_dly_s = cred_valid_out_ip[ip];
		     assign cred_valid = cred_valid_dly_q;
		     assign cred_vc_dly_s
		       = cred_vc_out_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1];
		     assign cred_vc = cred_vc_dly_q;
		  end
		
		dff
		  #(.width(credit_latency))
		cred_valid_dlyq
		  (.clk(clk),
		   .reset(reset),
		   .d(cred_valid_dly_s),
		   .q(cred_valid_dly_q));
		
		dff
		  #(.width(vc_idx_width*credit_latency))
		cred_vc_dlyq
		  (.clk(clk),
		   .reset(reset),
		   .d(cred_vc_dly_s),
		   .q(cred_vc_dly_q));
		
		wire 			flit_valid;
		wire [0:vc_idx_width-1] flit_vc;
		wire 			flit_head;
		wire 			flit_tail;
		wire [0:data_width-1] 	flit_data;
		
		wire [0:packet_count_width-1] ps_out_flits;
		
		wire 			      ps_error;
		packet_source
		  #(.max_packet_count(max_packet_count),
		    .packet_rate(packet_rate),
		    .initial_seed(initial_seed+ip),
		    .packet_count_width(packet_count_width),
		    .num_flit_buffers(num_flit_buffers),
		    .num_header_buffers(num_header_buffers),
		    .num_traffic_classes(num_traffic_classes),
		    .num_routing_classes(num_routing_classes),
		    .num_vcs_per_class(num_vcs_per_class),
		    .num_ports(num_ports),
		    .port_id(ip),
		    .num_dimensions(num_dimensions),
		    .num_routers_per_dim(num_routers_per_dim),
		    .router_address(router_address),
		    .num_neighbors_per_dim(num_neighbors_per_dim),
		    .routing_function_type(routing_function_type),
		    .max_packet_length(max_packet_length),
		    .min_packet_length(min_packet_length),
		    .packet_length_mode(packet_length_mode),
		    .data_width(data_width))
		ps
		  (.clk(clk),
		   .reset(reset),
		   .flit_valid(flit_valid),
		   .flit_head(flit_head),
		   .flit_tail(flit_tail),
		   .flit_vc(flit_vc),
		   .flit_data(flit_data),
		   .cred_valid(cred_valid),
		   .cred_vc(cred_vc),
		   .run(run),
		   .out_flits(ps_out_flits),
		   .error(ps_error));
		
		assign flit_valid_in_ip[ip] = flit_valid;
		assign flit_vc_in_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]
			 = flit_vc;
		assign flit_head_in_ip[ip] = flit_head;
		assign flit_tail_in_ip[ip] = flit_tail;
		assign flit_data_in_ip[ip*data_width:(ip+1)*data_width-1]
			 =  flit_data;
		assign ps_error_ip[ip] = ps_error;
		
		wire [0:header_info_width-1]  header_info;
		assign header_info = flit_data[0:header_info_width-1];
		
		wire [0:la_route_info_width-1] la_route_info_in;
		assign la_route_info_in
		  = header_info[0:la_route_info_width-1];
		
		wire [0:num_ports-1] 	       la_route_port;
		decoder
		  #(.num_ports(num_ports))
		la_route_port_dec
		  (.data_in(la_route_info_in[0:port_idx_width-1]),
		   .data_out(la_route_port));

		wire 			       la_route_class;
		
		if(num_routing_classes > 1)
		  assign la_route_class = la_route_info_in[port_idx_width];
		else
		  assign la_route_class = 1'b0;
		
		wire [0:route_info_width-1]    route_info;
		assign route_info
		  = header_info[la_route_info_width:
				la_route_info_width+route_info_width-1];
		
		wire [0:num_vcs*num_ports-1]   next_port_ivc;
		wire [0:num_vcs*num_vcs-1]     next_vcs_ivc;
		wire [0:num_vcs-1] 	       rtl_error_ivc;
		wire [0:num_vcs*la_route_info_width-1] la_route_info_ivc;
		
		genvar 				       itc;
		
		for(itc = 0; itc < num_traffic_classes; itc = itc + 1)
		  begin:itcs
		     
		     genvar irc;
		     
		     for(irc = 0; irc < num_routing_classes; irc = irc + 1)
		       begin:ircs
			  
			  wire [0:((irc == 
				    (num_routing_classes - 1)) ?
				   addr_width :
				   router_addr_width)-1] vc_route_info;
			  
			  assign vc_route_info[0:router_addr_width-1]
				   = route_info[irc*
						router_addr_width:
						(irc+1)*
						router_addr_width-1];
			  
			  if((irc == (num_routing_classes - 1)) &&
			     (num_nodes_per_router > 1))
			    assign vc_route_info[router_addr_width:addr_width-1]
				     = route_info[num_routing_classes*
						  router_addr_width:
						  num_routing_classes*
						  router_addr_width+
						  node_addr_width-1];
			  
			  wire [0:num_ports-1] 		 next_port;
			  wire [0:num_classes-1] 	 next_class;
			  wire 				 rtl_error_unmasked;
			  
			  routing_logic
			    #(.num_traffic_classes(num_traffic_classes),
			      .num_routing_classes(num_routing_classes),
			      .num_vcs_per_class(num_vcs_per_class),
			      .num_ports(num_ports),
			      .num_dimensions(num_dimensions),
			      .num_routers_per_dim(num_routers_per_dim),
			      .num_neighbors_per_dim(num_neighbors_per_dim),
			      .routing_function_type(routing_function_type),
			      .port_id(ip),
			      .traffic_class(itc),
			      .routing_class(irc))
			  rtl
			    (.router_address(router_address),
			     .vc_route_info(vc_route_info),
			     .next_port(next_port),
			     .next_class(next_class),
			     .error(rtl_error_unmasked));
			  
			  wire [0:num_vcs-1] 		 next_vcs;
			  replicator
			    #(.width(num_classes),
			      .count(num_vcs_per_class))
			  next_vcs_repl
			    (.data_in(next_class),
			     .data_out(next_vcs));
			  
			  assign next_port_ivc[(itc*num_routing_classes+irc)*
					       num_vcs_per_class*num_ports:
					       (itc*num_routing_classes+irc+1)*
					       num_vcs_per_class*num_ports-1]
				   = {num_vcs_per_class{next_port}};
			  assign next_vcs_ivc[(itc*num_routing_classes+irc)*
					      num_vcs_per_class*num_vcs:
					      (itc*num_routing_classes+irc+1)*
					      num_vcs_per_class*num_vcs-1]
				   = {num_vcs_per_class{next_vcs}};
			  
			  wire 				 rtl_error;
			  assign rtl_error
			    = rtl_error_unmasked & flit_valid &  flit_head;
			  
			  assign rtl_error_ivc[(itc*num_routing_classes+irc)*
					       num_vcs_per_class:
					       (itc*num_routing_classes+irc+1)*
					       num_vcs_per_class-1]
				   = {num_vcs_per_class{rtl_error}};
			  
			  wire [0:((irc ==
				    (num_routing_classes - 1)) ?
				   addr_width :
				   (irc ==
				    (num_routing_classes - 2)) ?
				   (router_addr_width + addr_width) :
				   (2*router_addr_width))-1] vc_route_info_la;
			  
			  if(irc == (num_routing_classes - 1))
			    assign vc_route_info_la
			      = route_info[route_info_width-addr_width:
					   route_info_width-1];
			  else if(irc == (num_routing_classes - 2))
			    assign vc_route_info_la
			      = route_info[route_info_width-
					   (router_addr_width+addr_width):
					   route_info_width-1];
			  else
			    assign vc_route_info_la
			      = route_info[irc*router_addr_width:
					   (irc+2)*router_addr_width-1];
			  
			  wire [0:la_route_info_width-1]     la_route_info;
			  la_routing_logic
			    #(.num_traffic_classes(num_traffic_classes),
			      .num_routing_classes(num_routing_classes),
			      .num_vcs_per_class(num_vcs_per_class),
			      .num_ports(num_ports),
			      .num_dimensions(num_dimensions),
			      .num_routers_per_dim(num_routers_per_dim),
			      .num_neighbors_per_dim(num_neighbors_per_dim),
			      .routing_function_type(routing_function_type),
			      .port_id(ip),
			      .traffic_class(itc),
			      .routing_class(irc))
			  lar
			    (.router_address(router_address),
			     .route_port(la_route_port),
			     .route_class(la_route_class),
			     .vc_route_info(vc_route_info_la),
			     .la_route_info(la_route_info));
			  
			  assign la_route_info_ivc[(itc*num_routing_classes+
						    irc)*num_vcs_per_class*
						   la_route_info_width:
						   (itc*num_routing_classes+
						    irc+1)*num_vcs_per_class*
						   la_route_info_width-1]
				   = {num_vcs_per_class{la_route_info}};
			  
		       end
		     
		  end
		
		wire [0:num_ports-1] 	   next_port;
		mux_nto1
		  #(.num_ports(num_vcs),
		    .width(num_ports))
		next_port_mux
		  (.select(flit_vc),
		   .data_in(next_port_ivc),
		   .data_out(next_port));
		
		wire [0:port_idx_width-1]  next_port_enc;
		encoder
		  #(.num_ports(num_ports))
		next_port_enc_enc
		  (.data_in(next_port),
		   .data_out(next_port_enc));
		
		assign rtl_error_ip[ip] = |rtl_error_ivc;
		
		wire [0:port_idx_width-1]  dest_port_s, dest_port_q;
		assign dest_port_s = flit_valid ?
				     (flit_head ?
				      next_port_enc :
				      dest_port_q) :
				     dest_port_q;
		dff
		  #(.width(port_idx_width))
		dest_portq
		  (.clk(clk),
		   .reset(reset),
		   .d(dest_port_s),
		   .q(dest_port_q));
		
		wire [0:port_idx_width-1]     dest_port;
		assign dest_port = (flit_valid & flit_head) ?
				   next_port_enc :
				   dest_port_q;

		wire [0:num_vcs-1] 	      next_vcs;
		mux_nto1
		  #(.num_ports(num_vcs),
		    .width(num_vcs))
		next_vcs_mux
		  (.select(flit_vc),
		   .data_in(next_vcs_ivc),
		   .data_out(next_vcs));
		
		wire [0:num_vcs-1] 	      dest_vcs_s, dest_vcs_q;
		assign dest_vcs_s = flit_valid ?
				    (flit_head ?
				     next_vcs :
				     dest_vcs_q) :
				    dest_vcs_q;
		dff
		  #(.width(num_vcs))
		dest_vcsq
		  (.clk(clk),
		   .reset(reset),
		   .d(dest_vcs_s),
		   .q(dest_vcs_q));
		
		wire [0:num_vcs-1] 	      dest_vcs;
		assign dest_vcs = (flit_valid & flit_head) ?
				  next_vcs :
				  dest_vcs_q;
		
		wire [0:la_route_info_width-1] la_route_info_out;
		mux_nto1
		  #(.num_ports(num_vcs),
		    .width(la_route_info_width))
		la_route_info_out_mux
		  (.select(flit_vc),
		   .data_in(la_route_info_ivc),
		   .data_out(la_route_info_out));
		
		wire [0:(2+data_width+port_idx_width+num_vcs)-1] data_in;
		assign data_in[0] = flit_head;
		assign data_in[1] = flit_tail;
		assign data_in[2:2+la_route_info_width-1]
			 = flit_head ?
			   la_route_info_out :
			   flit_data[0:la_route_info_width-1];
		assign data_in[2+la_route_info_width:2+data_width-1]
			 = flit_data[la_route_info_width:data_width-1];
		assign data_in[2+data_width:2+data_width+port_idx_width-1]
			 = dest_port;
		assign data_in[2+data_width+port_idx_width:
			       2+data_width+port_idx_width+num_vcs-1]
			 = dest_vcs;
		
		genvar 						 ivc;
		for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		  begin:ivcs
		     
		     wire [0:2+data_width+port_idx_width+num_vcs-1] data_out;
		     
		     wire 					    ref_head;
		     assign ref_head = data_out[0];
		     
		     wire 					    ref_tail;
		     assign ref_tail = data_out[1];
		     
		     wire [0:data_width-1] 			    ref_data;
		     assign ref_data = data_out[2:2+data_width-1];
		     
		     wire [0:port_idx_width-1] 			    ref_port;
		     assign ref_port
		       = data_out[2+data_width:
				  2+data_width+port_idx_width-1];
		     
		     wire [0:num_vcs-1] 			    ref_vcs;
		     assign ref_vcs
		       = data_out[2+data_width+port_idx_width:
				  2+data_width+port_idx_width+num_vcs-1];
		     
		     wire 					    check_head;
		     assign check_head = flit_head_out_op[ref_port];
		     
		     wire 					    check_tail;
		     assign check_tail = flit_tail_out_op[ref_port];
		     
		     wire [0:data_width-1] 			    check_data;
		     assign check_data
		       = flit_data_out_op[ref_port*data_width +: data_width];
		     
		     wire [0:vc_idx_width-1] 			    check_vc;
		     assign check_vc
		       = flit_vc_out_op[ref_port*vc_idx_width +: vc_idx_width];
		     
		     wire 					    push;
		     assign push = flit_valid && (flit_vc == ivc);
		     
		     wire 					    match_head;
		     assign match_head = ref_head == check_head;
		     
		     wire 					    match_tail;
		     assign match_tail = ref_tail == check_tail;
		     
		     wire 					    match_data;
		     assign match_data = ref_data == check_data;
		     
		     wire 					    match_vcs;
		     assign match_vcs = ref_vcs[check_vc];
		     
		     wire 					    fifo_empty;
		     
		     wire 					    match;
		     assign match
		       = flit_valid_out_op[ref_port] & ~fifo_empty &
			 match_head & match_tail & match_data & match_vcs;
		     
		     wire 					    pop;
		     assign pop = match;
		     
		     wire 					    fifo_full;
		     wire 					    fifo_error;
		     
		     fifo
		       #(.depth(num_flit_buffers),
			 .width(2+data_width+port_idx_width+num_vcs))
		     ref_fifo
		       (.clk(clk),
			.reset(reset),
			.full(fifo_full),
			.data_in(data_in),
			.push(push),
			.empty(fifo_empty),
			.data_out(data_out),
			.pop(pop),
			.error(fifo_error));
		     
		     assign fifo_error_ip_ivc[ip*num_vcs+ivc] = fifo_error;
		     
		     wire [0:num_ports-1] 			    port_mask;
		     decoder
		       #(.num_ports(num_ports))
		     port_mask_dec
		       (.data_in(ref_port),
			.data_out(port_mask));
		     
		     wire [0:num_ports-1] 			    match_op;
		     assign match_op = {num_ports{match}} & port_mask;
		     
		     assign match_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
					    (ip*num_vcs+ivc+1)*num_ports-1]
			      = match_op;
		     
		  end
	     end
	end
      
   endgenerate
   
   wire 				rtr_error;
   
   router
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       /*.max_packet_length(max_packet_length),*/
       .data_width(data_width),
       .perf_ctr_enable(perf_ctr_enable),
       .perf_ctr_width(perf_ctr_width),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .routing_function_type(routing_function_type),
       .credit_handling_type(credit_handling_type),
       .header_fifo_type(header_fifo_type),
       .fbf_regfile_type(fbf_regfile_type),
       .vc_allocator_type(vc_allocator_type),
       .vc_arbiter_type(vc_arbiter_type),
       .sw_allocator_type(sw_allocator_type),
       .sw_arbiter_type(sw_arbiter_type),
       .sw_spec_level(sw_spec_level),
       .xbc_crossbar_type(xbc_crossbar_type),
       .xbd_crossbar_type(xbd_crossbar_type),
       .reset_type(reset_type))
   rtr
     (.clk(clk),
      .reset(reset),
      .router_address(router_address),
      .flit_valid_in_ip(flit_valid_in_ip),
      .flit_vc_in_ip(flit_vc_in_ip),
      .flit_head_in_ip(flit_head_in_ip),
      .flit_tail_in_ip(flit_tail_in_ip),
      .flit_data_in_ip(flit_data_in_ip),
      .cred_valid_out_ip(cred_valid_out_ip),
      .cred_vc_out_ip(cred_vc_out_ip),
      .flit_valid_out_op(flit_valid_out_op),
      .flit_vc_out_op(flit_vc_out_op),
      .flit_head_out_op(flit_head_out_op),
      .flit_tail_out_op(flit_tail_out_op),
      .flit_data_out_op(flit_data_out_op),
      .cred_valid_in_op(cred_valid_in_op),
      .cred_vc_in_op(cred_vc_in_op),
      .error(rtr_error));
   
   wire [0:num_ports*num_vcs-1] 	pkt_error_op_ovc;
   wire [0:num_ports-1] 		x_error_op;
   
   generate
      
      genvar 					    op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:credit_latency-1] cred_valid_dly_s, cred_valid_dly_q;
	   wire [0:credit_latency*vc_idx_width-1] cred_vc_dly_s, cred_vc_dly_q;
	   
	   dff
	     #(.width(credit_latency),
	       .reset_type(reset_type))
	   cred_valid_dlyq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_valid_dly_s),
	      .q(cred_valid_dly_q));
	   
	   dff
	     #(.width(vc_idx_width*credit_latency),
	       .reset_type(reset_type))
	   cred_vc_dlyq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_vc_dly_s),
	      .q(cred_vc_dly_q));
	   
	   if(credit_latency > 1)
	     begin
		assign cred_valid_dly_s
		  = {flit_valid_out_op[op],
		     cred_valid_dly_q[0:(credit_latency-1)-1]};
		assign cred_valid_in_op[op]
		  = cred_valid_dly_q[(credit_latency-1):credit_latency-1];
		assign cred_vc_dly_s
		  = {flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1],
		     cred_vc_dly_q[0:vc_idx_width*(credit_latency-1)-1]};
		assign cred_vc_in_op[op*vc_idx_width:(op+1)*vc_idx_width-1]
		  = cred_vc_dly_q[vc_idx_width*(credit_latency-1):
				  vc_idx_width*credit_latency-1];
	     end
	   else
	     begin
		assign cred_valid_dly_s = flit_valid_out_op[op];
		assign cred_valid_in_op[op] = cred_valid_dly_q;
		assign cred_vc_dly_s
		  = flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1];
		assign cred_vc_in_op[op*vc_idx_width:(op+1)*vc_idx_width-1]
			 = cred_vc_dly_q;
	     end
	   
	   genvar ovc;
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		wire flit_valid;
		assign flit_valid
		  = flit_valid_out_op[op] &&
		    (flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1] ==
		     ovc);
		
		if(max_packet_length > 1)
		  begin

		     wire flit_count_zero;
		     
		     wire wait_head_s, wait_head_q;
		     assign wait_head_s = (wait_head_q &
					   ~(flit_valid &
					     flit_head_out_op[op])) |
					  (flit_valid & flit_count_zero);
		     dff
		       #(.width(1),
			 .reset_type(reset_type),
			 .reset_value(1'b1))
		     wait_headq
		       (.clk(clk),
			.reset(reset),
			.d(wait_head_s),
			.q(wait_head_q));

		     wire [0:header_info_width-1] header_info;
		     assign header_info
		       = flit_data_out_op[op*data_width:
					  op*data_width+header_info_width-1];
		     
		     wire [0:packet_length_width-1] packet_length;
		     assign packet_length
		       = header_info[la_route_info_width+route_info_width:
				     la_route_info_width+route_info_width+
				     packet_length_width-1];
		     
		     wire [0:packet_length_width-1] flit_count_s, flit_count_q;
		     assign flit_count_s
		       = (flit_valid & flit_head_out_op[op]) ?
			 packet_length :
			 (flit_count_q - flit_valid);
		     dff
		       #(.width(packet_length_width),
			 .reset_type(reset_type))
		     flit_countq
		       (.clk(clk),
			.reset(reset),
			.d(flit_count_s),
			.q(flit_count_q));
		     
		     assign flit_count_zero = ~|flit_count_s;
		     
		     assign pkt_error_op_ovc[op*num_vcs+ovc]
			      = flit_valid &
				(flit_head_out_op[op] ^ wait_head_q);
		     
		  end
		else
		  assign pkt_error_op_ovc[op*num_vcs+ovc] = 1'b0;
		
	     end
	   
	   wire 				    flit_valid_out;
	   assign flit_valid_out = flit_valid_out_op[op];
	   
	   wire 				    flit_head_out;
	   assign flit_head_out = flit_head_out_op[op];
	   
	   wire 				    flit_tail_out;
	   assign flit_tail_out = flit_tail_out_op[op];
	   
	   wire [0:vc_idx_width-1] 		    flit_vc_out;
	   assign flit_vc_out = flit_vc_out_op[op*vc_idx_width +: vc_idx_width];
	   
	   wire [0:data_width-1] 		    flit_data_out;
	   assign flit_data_out = flit_data_out_op[op*data_width +: data_width];
	   
	   assign x_error_op[op]
		    = (flit_valid_out === 1'bx) ||
		      ((flit_valid_out === 1'b1) &&
		       (^{flit_head_out,
			  flit_tail_out,
			  flit_vc_out,
			  flit_data_out} === 1'bx));
	   
	end
      
   endgenerate
   
   wire [0:num_ports-1] 			    match_op;
   or_nto1
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports))
   match_op_or
     (.data_in(match_ip_ivc_op),
      .data_out(match_op));
   
   wire [0:num_ports-1] 			    check_error_op;
   assign check_error_op = (flit_valid_out_op & ~match_op);

   integer 					    port;
   always @(posedge clk)
     begin
	for(port = 0; port < num_ports; port = port + 1)
	  begin
	     if(check_error_op[port])
	       begin
		  $display("check error: op=%d, cyc=%d", port, $time);
		  $display("head=%d, tail=%d, vc=%d, data=%x",
			   flit_head_out_op[port],
			   flit_tail_out_op[port],
			   flit_vc_out_op[port*vc_idx_width +: vc_idx_width],
			   flit_data_out_op[port*data_width +: data_width]);
	       end
	     if(x_error_op[port])
	       begin
		  $display("X value error: op=%d, cyc=%d", port, $time);
		  $display("valid = %d, head=%d, tail=%d, vc=%d, data=%x",
			   flit_valid_out_op[port],
			   flit_head_out_op[port],
			   flit_tail_out_op[port],
			   flit_vc_out_op[port*vc_idx_width +: vc_idx_width],
			   flit_data_out_op[port*data_width +: data_width]);
	       end
	  end
     end
   
   wire [0:6] errors;
   assign errors = {|ps_error_ip,
		    |rtl_error_ip,
		    |check_error_op,
		    |x_error_op,
		    |fifo_error_ip_ivc,
		    rtr_error,
		    |pkt_error_op_ovc};
   
   wire       error;
   assign error = |errors;
   
   wire [0:31] in_flits_s, in_flits_q;
   assign in_flits_s = in_flits_q + pop_count(flit_valid_in_ip);
   dff
     #(.width(32),
       .reset_type(reset_type))
   in_flitsq
     (.clk(clk),
      .reset(reset),
      .d(in_flits_s),
      .q(in_flits_q));
   
   wire [0:31] in_flits;
   assign in_flits = in_flits_s;
   
   wire [0:31] in_creds_s, in_creds_q;
   assign in_creds_s = in_creds_q + pop_count(cred_valid_out_ip);
   dff
     #(.width(32),
       .reset_type(reset_type))
   in_credsq
     (.clk(clk),
      .reset(reset),
      .d(in_creds_s),
      .q(in_creds_q));
   
   wire [0:31] in_creds;
   assign in_creds = in_creds_q;
   
   wire [0:31] out_flits_s, out_flits_q;
   assign out_flits_s = out_flits_q + pop_count(flit_valid_out_op);
   dff
     #(.width(32),
       .reset_type(reset_type))
   out_flitsq
     (.clk(clk),
      .reset(reset),
      .d(out_flits_s),
      .q(out_flits_q));
   
   wire [0:31] out_flits;
   assign out_flits = out_flits_s;
   
   wire [0:31] out_creds_s, out_creds_q;
   assign out_creds_s = out_creds_q + pop_count(cred_valid_in_op);
   dff
     #(.width(32),
       .reset_type(reset_type))
   out_credsq
     (.clk(clk),
      .reset(reset),
      .d(out_creds_s),
      .q(out_creds_q));
   
   wire [0:31] out_creds;
   assign out_creds = out_creds_q;
   
   reg 	       count_en;
   
   wire [0:31] count_in_flits_s, count_in_flits_q;
   assign count_in_flits_s
     = count_en ?
       count_in_flits_q + pop_count(flit_valid_in_ip) :
       count_in_flits_q;
   dff
     #(.width(32),
       .reset_type(reset_type))
   count_in_flitsq
     (.clk(clk),
      .reset(reset),
      .d(count_in_flits_s),
      .q(count_in_flits_q));
   
   wire [0:31] count_in_flits;
   assign count_in_flits = count_in_flits_s;
   
   wire [0:31] count_out_flits_s, count_out_flits_q;
   assign count_out_flits_s
     = count_en ?
       count_out_flits_q + pop_count(flit_valid_out_op) :
       count_out_flits_q;
   dff
     #(.width(32),
       .reset_type(reset_type))
   count_out_flitsq
     (.clk(clk),
      .reset(reset),
      .d(count_out_flits_s),
      .q(count_out_flits_q));
   
   wire [0:31] count_out_flits;
   assign count_out_flits = count_out_flits_s;
   
   reg 	       clk_en;
   
   always
   begin
      clk <= clk_en;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   always @(posedge clk)
     if(error)
       begin
	  $display("logic error detected, cyc=%d", $time);
	  $stop;
       end
   
   integer cycles;
   
   initial
   begin

      reset = 1'b0;
      clk_en = 1'b0;
      run = 1'b0;
      count_en = 1'b0;
      cycles = 0;
      
      #(Tclk);
      
      #(Tclk/2);
      
      reset = 1'b1;
      
      #(Tclk);
      
      reset = 1'b0;
      
      #(Tclk);
      
      clk_en = 1'b1;
      
      #(Tclk/2);
      
      $display("warming up...");
      
      run = 1'b1;

      while(cycles < warmup_time)
	begin
	   cycles = cycles + 1;
	   #(Tclk);
	end
      
      $display("measuring...");
      
      count_en = 1'b1;
      
      while(cycles < warmup_time + measure_time)
	begin
	   cycles = cycles + 1;
	   #(Tclk);
	end
      
      count_en = 1'b0;
      
      $display("measured %d cycles", measure_time);
      
      $display("%d flits in, %d flits out", count_in_flits, count_out_flits);
      
      $display("cooling down...");
      
      run = 1'b0;
      
      while((in_flits > out_flits) || (in_flits > in_creds))
	begin
	   cycles = cycles + 1;
	   #(Tclk);
	end
      
      #(Tclk*10);
      
      $display("simulation ended after %d cycles", cycles);
      
      $display("%d flits received, %d flits sent", in_flits, out_flits);
      
      $finish;
      
   end
   
endmodule
