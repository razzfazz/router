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
   
`include "c_constants.v"
`include "vcr_constants.v"
   
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
   parameter channel_latency = 1;
   parameter warmup_time = 1000;
   parameter measure_time = 100000;
   
   // select network topology
   parameter network_topology = `NETWORK_TOPOLOGY_MESH;//FBFLY;
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 1;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 1;
   
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
     = num_ports + ((num_routing_classes > 1) ? 1 : 0);
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_routing_classes * router_addr_width + node_addr_width;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
//   parameter packet_format = `PACKET_FORMAT_HEAD_TAIL;
   
   // maximum payload length (in flits)
   parameter max_payload_length = 4;
   
   // minimum payload length (in flits)
   parameter min_payload_length = 0;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);

   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   // select packet length mode (0: uniform random, 1: bimodal)
   parameter packet_length_mode = 0;
   
   // total number of bits required for storing header information
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 1;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   localparam routing_function_type
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       `ROUTING_FUNCTION_TYPE_MESH :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       `ROUTING_FUNCTION_TYPE_FBFLY :
       -1;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_OF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type
     = `SW_ALLOCATOR_TYPE_WF_BASE + `WF_ALLOCATOR_TYPE_DPA;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_CONFL_NONSPEC_REQ_MASKS;
   
   // enable speculative switch allocation
   localparam sw_spec_enable = (sw_spec_level == `SW_SPEC_LEVEL_NONE) ?
			       0 :
			       1;
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type = `CROSSBAR_TYPE_TRISTATE;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type = `CROSSBAR_TYPE_TRISTATE;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   reg 		    reset;
   reg 		    clk;
   
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_in_ip;
   wire [0:num_ports*flit_data_width-1] flit_data_in_ip;
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip;
   wire [0:num_ports-1] 		flit_valid_in_ip;
   wire [0:num_ports-1] 		cred_valid_out_ip;
   
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op;
   wire [0:num_ports*flit_data_width-1] flit_data_out_op;
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_in_op;
   wire [0:num_ports-1] 		flit_valid_out_op;
   wire [0:num_ports-1] 		cred_valid_in_op;
   
   wire [0:num_ports-1] 		ps_error_ip;
   wire [0:num_ports-1] 		rtl_error_ip;
   wire [0:num_ports*num_vcs*num_ports-1] match_ip_ivc_op;
   wire [0:num_ports*num_vcs-1] 	  fifo_error_ip_ivc;
   
   reg 					  run;
   
   generate
      
      genvar 				  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   if(ip < num_ports - num_nodes_per_router)
	     begin
		
		assign flit_ctrl_in_ip[ip*flit_ctrl_width:
				       (ip+1)*flit_ctrl_width-1]
			 = {flit_ctrl_width{1'b0}};
		assign flit_valid_in_ip[ip] = 1'b0;
		assign flit_data_in_ip[ip*flit_data_width:
				       (ip+1)*flit_data_width-1]
			 = {flit_data_width{1'b0}};
		
		wire [0:flow_ctrl_width-1] flow_ctrl_out;
		assign flow_ctrl_out
		  = flow_ctrl_out_ip[ip*flow_ctrl_width:
				     (ip+1)*flow_ctrl_width-1];
		
		assign cred_valid_out_ip[ip] = flow_ctrl_out[0];
		
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
		
		wire [0:flow_ctrl_width-1] flow_ctrl;
		assign flow_ctrl
		  = flow_ctrl_out_ip[ip*flow_ctrl_width:
				     (ip+1)*flow_ctrl_width-1];
		
		assign cred_valid_out_ip[ip] = flow_ctrl[0];
		
		wire [0:flit_ctrl_width-1] flit_ctrl;
		wire [0:flit_data_width-1] flit_data;
		
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
		    .restrict_turns(restrict_turns),
		    .routing_function_type(routing_function_type),
		    .dimension_order(dimension_order),
		    .packet_format(packet_format),
		    .max_payload_length(max_payload_length),
		    .min_payload_length(min_payload_length),
		    .packet_length_mode(packet_length_mode),
		    .flit_data_width(flit_data_width))
		ps
		  (.clk(clk),
		   .reset(reset),
		   .flit_ctrl(flit_ctrl),
		   .flit_data(flit_data),
		   .flow_ctrl(flow_ctrl),
		   .run(run),
		   .out_flits(ps_out_flits),
		   .error(ps_error));
		
		assign flit_ctrl_in_ip[ip*flit_ctrl_width:
				       (ip+1)*flit_ctrl_width-1]
			 = flit_ctrl;
		assign flit_valid_in_ip[ip] = flit_ctrl[0];
		assign flit_data_in_ip[ip*flit_data_width:
				       (ip+1)*flit_data_width-1]
			 =  flit_data;
		assign ps_error_ip[ip] = ps_error;
		
		wire [0:header_info_width-1]  header_info;
		assign header_info = flit_data[0:header_info_width-1];
		
		wire [0:la_route_info_width-1] la_route_info_in;
		assign la_route_info_in
		  = header_info[0:la_route_info_width-1];
		
		wire [0:num_ports-1] 	       la_route_op;
		assign la_route_op = la_route_info_in[0:num_ports-1];
		
		wire 			       la_inc_rc;
		
		if(num_routing_classes > 1)
		  assign la_inc_rc = la_route_info_in[num_ports];
		else
		  assign la_inc_rc = 1'b0;
		
		wire [0:route_info_width-1]    route_info;
		assign route_info
		  = header_info[la_route_info_width:
				la_route_info_width+route_info_width-1];
		
		wire 			      flit_valid;
		assign flit_valid = flit_ctrl[0];
		
		wire 			      flit_head;
		assign flit_head = flit_ctrl[1+vc_idx_width+0];
		
		wire 			      flit_tail;
		
		case(packet_format)
		  `PACKET_FORMAT_HEAD_TAIL:
		    assign flit_tail = flit_ctrl[1+vc_idx_width+1];
		  `PACKET_FORMAT_EXPLICIT_LENGTH:
		    begin
		       
		       if(max_payload_length == 0)
			 assign flit_tail = flit_head;
		       else if(max_payload_length == 1)
			 begin
			    
			    wire has_payload;
			    
			    if(payload_length_width > 0)
			      assign has_payload
				= header_info[la_route_info_width+
					      route_info_width];
			    else
			      assign has_payload = 1'b1;
			    
			    assign flit_tail = ~flit_head | ~has_payload;
			    
			 end
		       else
			 begin
			    
			    wire [0:flit_ctr_width-1] flit_ctr_q;
			    wire [0:flit_ctr_width-1] flit_ctr_next;
			    
			    if(payload_length_width > 0)
			      begin
				 
				 wire [0:payload_length_width-1] payload_length;
				 assign payload_length
				   = header_info[la_route_info_width+
						 route_info_width:
						 la_route_info_width+
						 route_info_width+
						 payload_length_width-1];
				 
				 assign flit_ctr_next
				   = (min_payload_length - 1) + payload_length;
				 
				 if(max_payload_length == 0)
				   assign flit_tail = flit_head ?
						      ~|payload_length :
						      ~|flit_ctr_q;
				 else
				   assign flit_tail = ~flit_head & ~|flit_ctr_q;
				 
			      end
			    else
			      begin
				 assign flit_ctr_next = max_payload_length - 1;
				 assign flit_tail = ~flit_head & ~|flit_ctr_q;
			      end
			    
			    wire [0:flit_ctr_width-1] flit_ctr_s;
			    assign flit_ctr_s = flit_valid ? 
						flit_head ? 
						flit_ctr_next : 
						(flit_ctr_q - 1'b1) : 
						flit_ctr_q;
			    c_dff
			      #(.width(flit_ctr_width),
				.reset_type(reset_type))
			    flit_ctrq
			      (.clk(clk),
			       .reset(reset),
			       .d(flit_ctr_s),
			       .q(flit_ctr_q));
			    
			 end
		       
		    end
		endcase
		
		wire [0:num_vcs*num_ports-1]   route_ivc_op;
		wire [0:num_vcs*num_vcs-1]     route_ivc_ovc;
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
				   router_addr_width)-1] hop_route_info;
			  
			  assign hop_route_info[0:router_addr_width-1]
				   = route_info[irc*
						router_addr_width:
						(irc+1)*
						router_addr_width-1];
			  
			  if((irc == (num_routing_classes - 1)) &&
			     (num_nodes_per_router > 1))
			    assign hop_route_info[router_addr_width:addr_width-1]
				     = route_info[num_routing_classes*
						  router_addr_width:
						  num_routing_classes*
						  router_addr_width+
						  node_addr_width-1];
			  
			  wire [0:num_ports-1] 		 route_op;
			  wire 				 inc_rc;
			  wire 				 rtl_error_unmasked;
			  
			  c_routing_logic
			    #(.num_traffic_classes(num_traffic_classes),
			      .num_routing_classes(num_routing_classes),
			      .num_ports(num_ports),
			      .num_dimensions(num_dimensions),
			      .num_routers_per_dim(num_routers_per_dim),
			      .num_neighbors_per_dim(num_neighbors_per_dim),
			      .restrict_turns(restrict_turns),
			      .routing_function_type(routing_function_type),
			      .dimension_order(dimension_order),
			      .port_id(ip),
			      .traffic_class(itc),
			      .routing_class(irc))
			  rtl
			    (.router_address(router_address),
			     .hop_route_info(hop_route_info),
			     .route_op(route_op),
			     .inc_rc(inc_rc),
			     .error(rtl_error_unmasked));
			  
			  wire [0:num_vcs-1] 		 route_ovc;
			  
			  if(itc > 0)
			    assign route_ovc[0:itc*num_routing_classes*
					     num_vcs_per_class-1]
				     = {(itc*num_routing_classes*
					 num_vcs_per_class){1'b0}};
			  
			  if(irc > 0)
			    assign route_ovc[itc*num_routing_classes*
					     num_vcs_per_class:
					     (itc*num_routing_classes+irc)*
					     num_vcs_per_class-1]
				     = {(irc*num_vcs_per_class){1'b0}};
			  
			  assign route_ovc[(itc*num_routing_classes+irc)*
					   num_vcs_per_class:
					   (itc*num_routing_classes+irc+1)*
					   num_vcs_per_class-1]
				   = {num_vcs_per_class{~inc_rc}};
			  
			  if(irc < (num_routing_classes - 1))
			    assign route_ovc[(itc*num_routing_classes+irc+1)*
					     num_vcs_per_class:
					     (itc*num_routing_classes+irc+2)*
					     num_vcs_per_class-1]
				     = {num_vcs_per_class{inc_rc}};
			  
			  if(irc < (num_routing_classes - 2))
			    assign route_ovc[(itc*num_routing_classes+irc+2)*
					     num_vcs_per_class:
					     (itc+1)*num_routing_classes*
					     num_vcs_per_class-1]
				     = {(num_routing_classes-irc-2){1'b0}};
			  
			  if(itc < (num_traffic_classes - 1))
			    assign route_ovc[(itc+1)*num_routing_classes*
					     num_vcs_per_class:
					     num_traffic_classes*
					     num_routing_classes*
					     num_vcs_per_class-1]
				     = {((num_traffic_classes-itc-1)*
					 num_routing_classes*
					 num_vcs_per_class){1'b0}};
			  
			  assign route_ivc_op[(itc*num_routing_classes+irc)*
					      num_vcs_per_class*num_ports:
					      (itc*num_routing_classes+irc+1)*
					      num_vcs_per_class*num_ports-1]
				   = {num_vcs_per_class{route_op}};
			  assign route_ivc_ovc[(itc*num_routing_classes+irc)*
					       num_vcs_per_class*num_vcs:
					       (itc*num_routing_classes+irc+1)*
					       num_vcs_per_class*num_vcs-1]
				   = {num_vcs_per_class{route_ovc}};
			  
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
				   (2*router_addr_width))-1] hop_route_info_la;
			  
			  if(irc == (num_routing_classes - 1))
			    assign hop_route_info_la
			      = route_info[route_info_width-addr_width:
					   route_info_width-1];
			  else if(irc == (num_routing_classes - 2))
			    assign hop_route_info_la
			      = route_info[route_info_width-
					   (router_addr_width+addr_width):
					   route_info_width-1];
			  else
			    assign hop_route_info_la
			      = route_info[irc*router_addr_width:
					   (irc+2)*router_addr_width-1];
			  
			  wire [0:la_route_info_width-1]     la_route_info;
			  c_la_routing_logic
			    #(.num_traffic_classes(num_traffic_classes),
			      .num_routing_classes(num_routing_classes),
			      .num_ports(num_ports),
			      .num_dimensions(num_dimensions),
			      .num_routers_per_dim(num_routers_per_dim),
			      .num_neighbors_per_dim(num_neighbors_per_dim),
			      .routing_function_type(routing_function_type),
			      .dimension_order(dimension_order),
			      .port_id(ip),
			      .traffic_class(itc),
			      .routing_class(irc))
			  lar
			    (.router_address(router_address),
			     .route_op(la_route_op),
			     .inc_rc(la_inc_rc),
			     .hop_route_info(hop_route_info_la),
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
		
		wire [0:num_ports-1] 			     route_op;
		
		if(num_vcs > 1)
		  begin:route_op_mux
		     
		     wire [0:vc_idx_width-1] flit_vc;
		     assign flit_vc = flit_ctrl[1:1+vc_idx_width-1];
		     
		     assign route_op
		       = route_ivc_op[flit_vc*num_ports +: num_ports];
		     
		  end
		else
		  assign route_op = route_ivc_op;
		
		wire [0:port_idx_width-1]    route_port;
		c_encoder
		  #(.num_ports(num_ports))
		route_port_enc
		  (.data_in(route_op),
		   .data_out(route_port));
		
		assign rtl_error_ip[ip] = |rtl_error_ivc;
		
		wire [0:port_idx_width-1]    dest_port_s, dest_port_q;
		assign dest_port_s = flit_valid ?
				     (flit_head ?
				      route_port :
				      dest_port_q) :
				     dest_port_q;
		c_dff
		  #(.width(port_idx_width))
		dest_portq
		  (.clk(clk),
		   .reset(reset),
		   .d(dest_port_s),
		   .q(dest_port_q));
		
		wire [0:port_idx_width-1]    dest_port;
		assign dest_port = (flit_valid & flit_head) ?
				   route_port :
				   dest_port_q;
		
		wire [0:num_vcs-1] 	     route_ovc;
		
		if(num_vcs > 1)
		  begin:route_ovc_mux
		     
		     wire [0:vc_idx_width-1] flit_vc;
		     assign flit_vc = flit_ctrl[1:1+vc_idx_width-1];
		     
		     assign route_ovc
		       = route_ivc_ovc[flit_vc*num_vcs +: num_vcs];
		     
		  end
		else
		  assign route_ovc = route_ivc_ovc;
		
		wire [0:num_vcs-1] 	     dest_ovc_s, dest_ovc_q;
		assign dest_ovc_s = flit_valid ?
				    (flit_head ?
				     route_ovc :
				     dest_ovc_q) :
				    dest_ovc_q;
		c_dff
		  #(.width(num_vcs))
		dest_ovcq
		  (.clk(clk),
		   .reset(reset),
		   .d(dest_ovc_s),
		   .q(dest_ovc_q));
		
		wire [0:num_vcs-1] 	     dest_ovc;
		assign dest_ovc = (flit_valid & flit_head) ?
				  route_ovc :
				  dest_ovc_q;
		
		wire [0:la_route_info_width-1] la_route_info_out;
		
		if(num_vcs > 1)
		  begin:la_route_info_out_mux
		     
		     wire [0:vc_idx_width-1] flit_vc;
		     assign flit_vc = flit_ctrl[1:1+vc_idx_width-1];
		     
		     assign la_route_info_out
		       = la_route_info_ivc[flit_vc*la_route_info_width +:
					   la_route_info_width];
		     
		  end
		else
		  assign la_route_info_out = la_route_info_ivc;
		
		wire [0:(flit_ctrl_width+flit_data_width+port_idx_width+
			 num_vcs)-1] 	     data_in;
		assign data_in[0:flit_ctrl_width-1] = flit_ctrl;
		assign data_in[flit_ctrl_width:
			       flit_ctrl_width+la_route_info_width-1]
			 = flit_head ? 
			   la_route_info_out : 
			   flit_data[0:la_route_info_width-1];
		assign data_in[flit_ctrl_width+la_route_info_width:
			       flit_ctrl_width+flit_data_width-1]
			 = flit_data[la_route_info_width:flit_data_width-1];
		assign data_in[flit_ctrl_width+flit_data_width:
			       flit_ctrl_width+flit_data_width+port_idx_width-1]
			 = dest_port;
		assign data_in[flit_ctrl_width+flit_data_width+port_idx_width:
			       flit_ctrl_width+flit_data_width+port_idx_width+
			       num_vcs-1]
			 = dest_ovc;
		
		genvar 			     ivc;
		for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		  begin:ivcs
		     
		     wire [0:flit_ctrl_width+flit_data_width+port_idx_width+
			   num_vcs-1] data_out;
		     
		     wire [0:flit_ctrl_width-1] ref_ctrl;
		     assign ref_ctrl = data_out[0:flit_ctrl_width-1];
		     
		     wire [0:flit_data_width-1] ref_data;
		     assign ref_data
		       = data_out[flit_ctrl_width:
				  flit_ctrl_width+flit_data_width-1];
		     
		     wire [0:port_idx_width-1] 	ref_port;
		     assign ref_port
		       = data_out[flit_ctrl_width+flit_data_width:
				  flit_ctrl_width+flit_data_width+
				  port_idx_width-1];
		     
		     wire [0:num_vcs-1] 	ref_ovc;
		     assign ref_ovc
		       = data_out[flit_ctrl_width+flit_data_width+
				  port_idx_width:
				  flit_ctrl_width+flit_data_width+
				  port_idx_width+num_vcs-1];
		     
		     wire [0:flit_ctrl_width-1] check_ctrl;
		     assign check_ctrl
		       = flit_ctrl_out_op[ref_port*flit_ctrl_width +:
					  flit_ctrl_width];
		     
		     wire [0:flit_data_width-1] check_data;
		     assign check_data
		       = flit_data_out_op[ref_port*flit_data_width +: 
					  flit_data_width];
		     
		     wire 			push;
		     
		     if(num_vcs > 1)
		       begin
			  
			  wire [0:vc_idx_width-1] flit_vc;
			  assign flit_vc = flit_ctrl[1:1+vc_idx_width-1];
			  
			  assign push = flit_valid && (flit_vc == ivc);
			  
		       end
		     else
		       assign push = flit_valid;
		     
		     wire 			  valid;
		     assign valid = check_ctrl[0];
		     
		     wire 			  match_ctrl;
		     
		     if(flit_ctrl_width > (1 + vc_idx_width))
		       assign match_ctrl = (ref_ctrl[0] == check_ctrl[0]) &&
					   (ref_ctrl[1+vc_idx_width:
						     flit_ctrl_width-1] ==
					    check_ctrl[1+vc_idx_width:
						       flit_ctrl_width-1]);
		     else
		       assign match_ctrl = (ref_ctrl[0] == check_ctrl[0]);
		     
		     wire 			  match_data;
		     assign match_data = (ref_data == check_data);
		     
		     wire 			  match_vcs;
		     
		     if(num_vcs > 1)
		       begin
			  
			  wire [0:vc_idx_width-1] check_vc;
			  assign check_vc = check_ctrl[1:1+vc_idx_width-1];
			  
			  assign match_vcs = ref_ovc[check_vc];
			  
		       end
		     else
		       assign match_vcs = 1'b1;
		     
		     wire 			  fifo_empty;
		     
		     wire 			  match;
		     assign match = valid & ~fifo_empty & 
				    match_ctrl & match_data & match_vcs;
		     
		     wire 			  pop;
		     assign pop = match;
		     
		     wire 			  fifo_full;
		     wire 			  fifo_error;
		     
		     c_fifo
		       #(.depth(num_flit_buffers),
			 .width(flit_ctrl_width+flit_data_width+port_idx_width+
				num_vcs))
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
		     
		     wire [0:num_ports-1] 	  port_mask;
		     c_decoder
		       #(.num_ports(num_ports))
		     port_mask_dec
		       (.data_in(ref_port),
			.data_out(port_mask));
		     
		     wire [0:num_ports-1] 	  match_op;
		     assign match_op = {num_ports{match}} & port_mask;
		     
		     assign match_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
					    (ip*num_vcs+ivc+1)*num_ports-1]
			      = match_op;
		     
		  end
	     end
	end
      
   endgenerate
   
   wire 					  rtr_error;
   
   vcr_top
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .flit_data_width(flit_data_width),
       .perf_ctr_enable(perf_ctr_enable),
       .perf_ctr_width(perf_ctr_width),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .track_vcs_at_output(track_vcs_at_output),
       .restrict_turns(restrict_turns),
       .routing_function_type(routing_function_type),
       .dimension_order(dimension_order),
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
   vcr
     (.clk(clk),
      .reset(reset),
      .router_address(router_address),
      .flit_ctrl_in_ip(flit_ctrl_in_ip),
      .flit_data_in_ip(flit_data_in_ip),
      .flow_ctrl_out_ip(flow_ctrl_out_ip),
      .flit_ctrl_out_op(flit_ctrl_out_op),
      .flit_data_out_op(flit_data_out_op),
      .flow_ctrl_in_op(flow_ctrl_in_op),
      .error(rtr_error));
   
   wire [0:num_ports-1] 		x_error_op;
   
   generate
      
      genvar 					    op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:flit_ctrl_width-1] flit_ctrl_out;
	   assign flit_ctrl_out = flit_ctrl_out_op[op*flit_ctrl_width:
						   (op+1)*flit_ctrl_width-1];
	   
	   assign flit_valid_out_op[op] = flit_ctrl_out[0];
	   
	   wire [0:flit_ctrl_width-1] flit_ctrl_dly;
	   
	   if(channel_latency == 0)
	     assign flit_ctrl_dly = flit_ctrl_out;
	   else
	     begin
		
		wire [0:channel_latency*flit_ctrl_width-1] flit_ctrl_dly_s,
							   flit_ctrl_dly_q;
		c_dff
		  #(.width(channel_latency*flit_ctrl_width),
		    .reset_type(reset_type))
		flit_ctrl_dlyq
		  (.clk(clk),
		   .reset(reset),
		   .d(flit_ctrl_dly_s),
		   .q(flit_ctrl_dly_q));
		
		if(channel_latency == 1)
		  begin
		     assign flit_ctrl_dly_s = flit_ctrl_out;
		     assign flit_ctrl_dly = flit_ctrl_dly_q;
		  end
		else
		  begin
		     assign flit_ctrl_dly_s
		       = {flit_ctrl_out, 
			  flit_ctrl_dly_q[0:(channel_latency-1)*
					  flit_ctrl_width-1]};
		     assign flit_ctrl_dly
		       = flit_ctrl_dly_q[(channel_latency-1)*flit_ctrl_width:
					 channel_latency*flit_ctrl_width-1];
		  end
		
	     end
	   
	   wire [0:flow_ctrl_width-1] flow_ctrl_s, flow_ctrl_q;
	   assign flow_ctrl_s = flit_ctrl_dly[0:1+vc_idx_width-1];
	   c_dff
	     #(.width(flow_ctrl_width),
	       .reset_type(reset_type))
	   flow_ctrlq
	     (.clk(clk),
	      .reset(reset),
	      .d(flow_ctrl_s),
	      .q(flow_ctrl_q));
	   
	   wire [0:flow_ctrl_width-1] flow_ctrl_in;
	   
	   if(channel_latency == 0)
	     assign flow_ctrl_in = flow_ctrl_q;
	   else
	     begin
		
		wire [0:channel_latency*flow_ctrl_width-1] flow_ctrl_dly_s,
							   flow_ctrl_dly_q;
		
		c_dff
		  #(.width(channel_latency*flow_ctrl_width),
		    .reset_type(reset_type))
		flow_ctrl_dlyq
		  (.clk(clk),
		   .reset(reset),
		   .d(flow_ctrl_dly_s),
		   .q(flow_ctrl_dly_q));
		
		if(channel_latency == 1)
		  begin
		     assign flow_ctrl_dly_s = flow_ctrl_q;
		     assign flow_ctrl_in = flow_ctrl_dly_q;
		  end
		else
		  begin
		     assign flow_ctrl_dly_s
		       = {flow_ctrl_q,
			  flow_ctrl_dly_q[0:(channel_latency-1)*
					  flow_ctrl_width-1]};
		     assign flow_ctrl_in
		       = flow_ctrl_dly_q[(channel_latency-1)*flow_ctrl_width:
					 channel_latency*flow_ctrl_width-1];
		  end
		
	     end
	   
	   assign flow_ctrl_in_op[op*flow_ctrl_width:(op+1)*flow_ctrl_width-1]
		    = flow_ctrl_in;
	   assign cred_valid_in_op[op] = flow_ctrl_in[0];
	   
	   wire 		      flit_valid_out;
	   assign flit_valid_out = flit_ctrl_out[0];
	   
	   wire [0:flit_data_width-1] flit_data_out;
	   assign flit_data_out = flit_data_out_op[op*flit_data_width +: 
						   flit_data_width];
	   
	   assign x_error_op[op]
		    = (flit_valid_out === 1'bx) ||
		      ((flit_valid_out === 1'b1) &&
		       (^{flit_ctrl_out, flit_data_out} === 1'bx));
	   
	end
      
   endgenerate
   
   wire [0:num_ports-1] 	      match_op;
   c_or_nto1
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports))
   match_op_or
     (.data_in(match_ip_ivc_op),
      .data_out(match_op));
   
   wire [0:num_ports-1] 	      check_error_op;
   assign check_error_op = (flit_valid_out_op & ~match_op);
   
   integer 			      port;
   always @(posedge clk)
     begin
	for(port = 0; port < num_ports; port = port + 1)
	  begin
	     if(check_error_op[port])
	       begin
		  $display("check error: op=%d, cyc=%d", port, $time);
		  $display("ctrl=%b, data=%x",
			   flit_ctrl_out_op[port*flit_ctrl_width +: 
					    flit_ctrl_width],
			   flit_data_out_op[port*flit_data_width +: 
					    flit_data_width]);
	       end
	     if(x_error_op[port])
	       begin
		  $display("X value error: op=%d, cyc=%d", port, $time);
		  $display("ctrl=%b, data=%x",
			   flit_ctrl_out_op[port*flit_ctrl_width +:
					    flit_ctrl_width],
			   flit_data_out_op[port*flit_data_width +: 
					    flit_data_width]);
	       end
	  end
     end
   
   wire [0:4] tb_errors;
   assign tb_errors = {|ps_error_ip,
		       |rtl_error_ip,
		       |check_error_op,
		       |x_error_op,
		       |fifo_error_ip_ivc};
   
   wire       tb_error;
   assign tb_error = |tb_errors;
   
   wire [0:31] in_flits_s, in_flits_q;
   assign in_flits_s = in_flits_q + pop_count(flit_valid_in_ip);
   c_dff
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
   c_dff
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
   c_dff
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
   c_dff
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
   c_dff
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
   c_dff
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
     begin
	if(rtr_error)
	  begin
	     $display("internal error detected, cyc=%d", $time);
	     $stop;
	  end
	if(tb_error)
	  begin
	     $display("external error detected, cyc=%d", $time);
	     $stop;
	  end
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
