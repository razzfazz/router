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
   parameter adaptive_rate = 1;
   parameter packet_count_width = 32;
   parameter inj_channel_delay = 0;
   parameter min_channel_delay = 2;
   parameter warmup_time = 1000;
   parameter measure_time = 100000;
   
   // select network topology
   parameter network_topology = `NETWORK_TOPOLOGY_MESH;
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
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
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
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
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // total number of bits required for storing routing information
   localparam route_info_width = 2 * addr_width;
   
   // maximum packet length (in flits)
   parameter max_packet_length = 8;
   
   // minimum packet length (in flits)
   parameter min_packet_length = 8;
   
   // select packet length mode (0: uniform random, 1: bimodal)
   parameter packet_length_mode = 0;
   
   // total number of bits required to represent maximum packet length
   localparam packet_length_width = clogb(max_packet_length);
   
   // total number of bits required for storing header information
   localparam head_info_width = route_info_width + packet_length_width;
   
   // flit width
   parameter flit_data_width = 64;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
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
   
   // select routing function type
   localparam routing_function_type
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       `ROUTING_FUNCTION_TYPE_BY_RELATION :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       `ROUTING_FUNCTION_TYPE_BY_DIFFERENCE :
       -1;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_control_type = `INT_FLOW_CONTROL_TYPE_CREDIT_PUSH;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select implementation variant for VC allocator
   parameter vca_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vca_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter swa_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter swa_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   reg 		    reset;
   reg 		    clk;
   
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_in_ip;
   wire [0:num_ports*flit_data_width-1] flit_data_in_ip;
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip;
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op;
   wire [0:num_ports*flit_data_width-1] flit_data_out_op;
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_in_op;
   
   wire [0:num_ports-1] 		flit_valid_in_ip;
   
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
		
		// no injection port => no traffic injected
		
		assign flit_ctrl_in_ip[ip*flit_ctrl_width:
				       (ip+1)*flit_ctrl_width-1]
			 = {flit_ctrl_width{1'b0}};
		assign flit_data_in_ip[ip*flit_data_width:
				       (ip+1)*flit_data_width-1]
			 = {flit_data_width{1'b0}};
		
		assign flit_valid_in_ip[ip] = 1'b0;
		
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
		
		// injection port => connect to packet source
		
		
		// flow control signals are delayed by given number of cycles
		
		wire [0:flow_ctrl_width-1] flow_ctrl_out;
		assign flow_ctrl_out
		  = flow_ctrl_out_ip[ip*flow_ctrl_width:
				     (ip+1)*flow_ctrl_width-1];
		
		wire [0:flow_ctrl_width-1] flow_ctrl_in;
		delay
		  #(.width(flow_ctrl_width),
		    .delay(inj_channel_delay))
		flow_ctrl_in_delay
		  (.clk(clk),
		   .reset(reset),
		   .data_in(flow_ctrl_out),
		   .data_out(flow_ctrl_in));
		
		// connect packet source
		
		wire [0:flit_ctrl_width-1] flit_ctrl_out;
		wire [0:flit_data_width-1] flit_data_out;
		
		wire [0:packet_count_width-1] ps_out_flits;
		
		wire 			      ps_error;
		packet_source
		  #(
		    .num_flit_buffers(num_flit_buffers),
		    .num_header_buffers(num_header_buffers),
		    .num_vcs(num_vcs),
		    .addr_width(addr_width),
		    .address(router_address+
			     ip-(num_ports-num_nodes_per_router)),
		    .packet_format(packet_format),
		    .max_packet_count(max_packet_count),
		    .packet_rate(packet_rate),
		    .initial_seed(initial_seed+ip),
		    .adaptive_rate(adaptive_rate),
		    .packet_count_width(packet_count_width),
		    .max_packet_length(max_packet_length),
		    .min_packet_length(min_packet_length),
		    .packet_length_mode(packet_length_mode),
		    .flit_data_width(flit_data_width))
		ps
		  (.clk(clk),
		   .reset(reset),
		   .flit_ctrl_out(flit_ctrl_out),
		   .flit_data_out(flit_data_out),
		   .flow_ctrl_in(flow_ctrl_in),
		   .run(run),
		   .out_flits(ps_out_flits),
		   .error(ps_error));
		
		
		// also delay flit data and control
		
		wire [0:flit_ctrl_width-1] flit_ctrl_in;
		delay
		  #(.width(flit_ctrl_width),
		    .delay(inj_channel_delay))
		flit_ctrl_in_delay
		  (.clk(clk),
		   .reset(reset),
		   .data_in(flit_ctrl_out),
		   .data_out(flit_ctrl_in));
		
		assign flit_ctrl_in_ip[ip*flit_ctrl_width:
				       (ip+1)*flit_ctrl_width-1]
			 = flit_ctrl_in;
		
		wire [0:flit_data_width-1] flit_data_in;
		delay
		  #(.width(flit_data_width),
		    .delay(inj_channel_delay))
		flit_data_in_delay
		  (.clk(clk),
		   .reset(reset),
		   .data_in(flit_data_out),
		   .data_out(flit_data_in));
		
		assign flit_data_in_ip[ip*flit_data_width:
				       (ip+1)*flit_data_width-1]
			 =  flit_data_in;
		
		assign ps_error_ip[ip] = ps_error;
		
		wire 			   flit_valid_in;
		wire 			   flit_head_in;
		wire 			   flit_tail_in;
		
		case(packet_format)
		  
		  `PACKET_FORMAT_HEAD_TAIL:
		    begin
		       assign flit_valid_in = flit_ctrl_in[0];
		       assign flit_head_in = flit_ctrl_in[1];
		       assign flit_tail_in = flit_ctrl_in[2];
		    end
		  
		endcase
		
		assign flit_valid_in_ip = flit_valid_in;
		
		wire [0:head_info_width-1] head_info;
		assign head_info = flit_data_in[0:head_info_width-1];
		
		wire [0:route_info_width-1] route_info;
		assign route_info = head_info[0:route_info_width-1];
		
		wire [0:num_vcs*num_ports-1] next_port_ivc;
		wire [0:num_vcs*num_vcs-1]   next_vcs_ivc;
		wire [0:num_vcs-1] 	     rtl_error_ivc;
		
		genvar 			     ivc;
		
		for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		  begin:ivs
		     
		     wire [0:num_ports-1]  next_port;
		     wire [0:num_vcs-1]    next_vcs;
		     wire 		   rtl_error_unmasked;
		     
		     routing_logic
		       #(.num_vcs(num_vcs),
			 .num_traffic_classes(num_traffic_classes),
			 .num_routing_classes(num_routing_classes),
			 .num_ports(num_ports),
			 .num_dimensions(num_dimensions),
			 .num_routers_per_dim(num_routers_per_dim),
			 .num_neighbors_per_dim(num_neighbors_per_dim),
			 .routing_function_type(routing_function_type),
			 .port_id(ip),
			 .vc_id(ivc))
		     rtl
		       (.clk(clk),
			.reset(reset),
			.router_address(router_address),
			.route_info(route_info),
			.next_port(next_port),
			.next_vcs(next_vcs),
			.error(rtl_error_unmasked));
		     
		     assign next_port_ivc[ivc*num_ports:(ivc+1)*num_ports-1]
			      = next_port;
		     assign next_vcs_ivc[ivc*num_vcs:(ivc+1)*num_vcs-1]
			      = next_vcs;
		     
		     wire 		   rtl_error;
		     assign rtl_error
		       = rtl_error_unmasked & flit_valid_in & flit_head_in;
		     
		     assign rtl_error_ivc[ivc] = rtl_error;
		     
		  end
		
		wire [0:num_ports-1] 	   next_port;
		wire [0:num_vcs-1] 	   next_vcs;
		wire [0:num_vcs-1] 	   flit_valid_ivc;
		
		if(num_vcs > 1)
		  begin
		     
		     wire [0:vc_idx_width-1] flit_vc_in;
		     
		     case(packet_format)
		       
		       `PACKET_FORMAT_HEAD_TAIL:
			 begin
			    assign flit_vc_in
			      = flit_ctrl_in[3:3+vc_idx_width-1];
			 end
		       
		     endcase
		     
		     mux_nto1
		       #(.num_ports(num_vcs),
			 .width(num_ports))
		     next_port_mux
		       (.select(flit_vc_in),
			.data_in(next_port_ivc),
			.data_out(next_port));
		     
		     mux_nto1
		       #(.num_ports(num_vcs),
			 .width(num_vcs))
		     next_vcs_mux
		       (.select(flit_vc_in),
			.data_in(next_vcs_ivc),
			.data_out(next_vcs));
		     
		     wire [0:num_vcs-1] flit_vc_1hot;
		     decoder
		       #(.num_ports(num_vcs))
		     flit_vc_1hot_dec
		       (.data_in(flit_vc_in),
			.data_out(flit_vc_1hot));
		     
		     assign flit_valid_ivc
		       = {num_vcs{flit_valid_in}} & flit_vc_1hot;
		     
		  end
		else
		  begin
		     assign next_port = next_port_ivc;
		     assign next_vcs = next_vcs_ivc;
		     assign flit_valid_ivc = flit_valid_in;
		  end
		
		wire [0:port_idx_width-1]  next_port_enc;
		encoder
		  #(.num_ports(num_ports))
		next_port_enc_enc
		  (.data_in(next_port),
		   .data_out(next_port_enc));
		
		assign rtl_error_ip[ip] = |rtl_error_ivc;
		
		wire [0:port_idx_width-1]  dest_port_s, dest_port_q;
		assign dest_port_s = flit_valid_in ?
				     (flit_head_in ?
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
		assign dest_port = (flit_valid_in & flit_head_in) ?
				   next_port_enc :
				   dest_port_q;

		wire [0:num_vcs-1] 	      dest_vcs_s, dest_vcs_q;
		assign dest_vcs_s = flit_valid_in ?
				    (flit_head_in ?
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
		assign dest_vcs = (flit_valid_in & flit_head_in) ?
				  next_vcs :
				  dest_vcs_q;
		
		wire [0:addr_width-1] 	      next_address;
		assign next_address = route_info[0:addr_width-1];
		
		wire [0:addr_width-1] 	      final_address;
		assign final_address = route_info[addr_width:2*addr_width-1];
		
		wire 			      update_addr;
		assign update_addr
		  = flit_head_in &&
		    (router_address == next_address[0:router_addr_width-1]);
		
		wire [0:route_info_width-1]   next_route_info;
		assign next_route_info
		  = {update_addr ? final_address : next_address, final_address};
		
		wire [0:flit_data_width-1] 	      flit_data_muxed;
		assign flit_data_muxed[0:route_info_width-1] = next_route_info;
		assign flit_data_muxed[route_info_width:flit_data_width-1]
			 = flit_data_in[route_info_width:flit_data_width-1];
		
		wire [0:(2+flit_data_width+port_idx_width+num_vcs)-1] data_in;
		assign data_in[0] = flit_head_in;
		assign data_in[1] = flit_tail_in;
		assign data_in[2:2+flit_data_width-1]
			 = flit_data_muxed[0:flit_data_width-1];
		assign data_in[2+flit_data_width:
			       2+flit_data_width+port_idx_width-1]
			 = dest_port;
		assign data_in[2+flit_data_width+port_idx_width:
			       2+flit_data_width+port_idx_width+num_vcs-1]
			 = dest_vcs;
		
		for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		  begin:ivcs
		     
		     wire [0:2+flit_data_width+
			   port_idx_width+num_vcs-1] data_out;
		     
		     wire 			     ref_head;
		     assign ref_head = data_out[0];
		     
		     wire 			     ref_tail;
		     assign ref_tail = data_out[1];
		     
		     wire [0:flit_data_width-1]      ref_data;
		     assign ref_data = data_out[2:2+flit_data_width-1];
		     
		     wire [0:port_idx_width-1] 	     ref_port;
		     assign ref_port
		       = data_out[2+flit_data_width:
				  2+flit_data_width+port_idx_width-1];
		     
		     wire [0:num_vcs-1] 	     ref_vcs;
		     assign ref_vcs
		       = data_out[2+flit_data_width+port_idx_width:
				  2+flit_data_width+port_idx_width+num_vcs-1];
		     
		     wire [0:flit_ctrl_width-1]      flit_ctrl_out;
		     assign flit_ctrl_out
		       = flit_ctrl_out_op[ref_port*flit_ctrl_width +:
					  flit_ctrl_width];
		     
		     wire 			     flit_valid_out;
		     wire 			     flit_head_out;
		     wire 			     flit_tail_out;

		     case(packet_format)

		       `PACKET_FORMAT_HEAD_TAIL:
			 begin
			    assign flit_valid_out = flit_ctrl_out[0];
			    assign flit_head_out = flit_ctrl_out[1];
			    assign flit_tail_out = flit_ctrl_out[2];
			 end

		     endcase
		     
		     wire [0:flit_data_width-1]      flit_data_out;
		     assign flit_data_out
		       = flit_data_out_op[ref_port*flit_data_width +: 
					  flit_data_width];

		     wire 			     match_head;
		     assign match_head = ref_head == flit_head_out;
		     
		     wire 			     match_tail;
		     assign match_tail = ref_tail == flit_tail_out;
		     
		     wire 			     match_data;
		     assign match_data = ref_data == flit_data_out;
		     
		     wire 			     match_vcs;
		     
		     if(num_vcs > 1)
		       begin
			  
			  wire [0:vc_idx_width-1] flit_vc_out;
			  assign flit_vc_out
			    = flit_ctrl_out[3:3+vc_idx_width-1];
			  
			  assign match_vcs = ref_vcs[flit_vc_out];
			  
		       end
		     else
		       assign match_vcs = 1'b1;
		     
		     wire 			  fifo_empty;
		     
		     wire 			  match;
		     assign match
		       = flit_valid_out & ~fifo_empty &
			 match_head & match_tail & match_data & match_vcs;
		     
		     wire 			  push;
		     assign push = flit_valid_ivc[ivc];
		     
		     wire 			  pop;
		     assign pop = match;
		     
		     wire 			  fifo_full;
		     wire 			  fifo_error;
		     
		     fifo
		       #(.depth(num_flit_buffers),
			 .width(2+flit_data_width+port_idx_width+num_vcs))
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
		     
		     wire [0:num_ports-1] 	     port_mask;
		     decoder
		       #(.num_ports(num_ports))
		     port_mask_dec
		       (.data_in(ref_port),
			.data_out(port_mask));
		     
		     wire [0:num_ports-1] 	     match_op;
		     assign match_op = {num_ports{match}} & port_mask;
		     
		     assign match_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
					    (ip*num_vcs+ivc+1)*num_ports-1]
			      = match_op;
		     
		  end
	     end
	end
      
   endgenerate
   
   wire 					     rtr_error;
   
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
       .flit_data_width(flit_data_width),
       .perf_ctr_enable(perf_ctr_enable),
       .perf_ctr_width(perf_ctr_width),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .packet_format(packet_format),
       .flow_control_type(flow_control_type),
       .routing_function_type(routing_function_type),
       .int_flow_control_type(int_flow_control_type),
       .header_fifo_type(header_fifo_type),
       .fbf_regfile_type(fbf_regfile_type),
       .vca_allocator_type(vca_allocator_type),
       .vca_arbiter_type(vca_arbiter_type),
       .swa_allocator_type(swa_allocator_type),
       .swa_arbiter_type(swa_arbiter_type),
       .sw_spec_level(sw_spec_level),
       .xbc_crossbar_type(xbc_crossbar_type),
       .xbd_crossbar_type(xbd_crossbar_type),
       .reset_type(reset_type))
   rtr
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
   
   wire [0:num_ports*num_vcs-1] 	pkt_error_op_ovc;
   wire [0:num_ports-1] 		x_error_op;
   wire [0:num_ports-1] 		flit_valid_out_op;
   
   generate
      
      genvar 				op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   // connect all ports to packet sinks
	   
	   
	   // delay flit control and data signals
	   
	   wire [0:flit_ctrl_width-1] flit_ctrl_out;
	   assign flit_ctrl_out = flit_ctrl_out_op[op*flit_ctrl_width:
						   (op+1)*flit_ctrl_width-1];
	   
	   case(packet_format)
	     
	     `PACKET_FORMAT_HEAD_TAIL:
	       begin
		  assign flit_valid_out_op[op] = flit_ctrl_out[0];
	       end
	     
	   endcase
	   
	   wire [0:flit_ctrl_width-1] flit_ctrl_in;
	   delay
	     #(.width(flit_ctrl_width),
	       .delay(min_channel_delay))
	   flit_ctrl_in_delay
	     (.data_in(flit_ctrl_out),
	      .data_out(flit_ctrl_in));
	   
	   wire [0:flit_data_width-1] flit_data_out;
	   assign flit_data_out = flit_data_out[op*flit_data_width:
						(op+1)*flit_data_width-1];
	   
	   wire [0:flit_data_width-1] flit_data_in;
	   delay
	     #(.width(flit_data_width),
	       .delay(min_channel_delay))
	   flit_data_in_delay
	     (.data_in(flit_data_out),
	      .data_out(flit_data_in));
	   
	   genvar ovc;
	   
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		wire flit_valid_in;
		wire flit_head_in;
		wire flit_tail_in;
		
		case(packet_format)
		  
		  `PACKET_FORMAT_HEAD_TAIL:
		    begin
		       
		       assign flit_head_in = flit_ctrl_in[1];
		       assign flit_tail_in = flit_ctrl_in[2];
		       
		       if(num_vcs > 1)
			 begin
			    
			    wire [0:vc_idx_width-1] flit_vc_in;
			    assign flit_vc_in
			      = flit_ctrl_in[3:3+vc_idx_width-1];
			    
			    assign flit_valid_in
			      = flit_ctrl_in[0] && (flit_vc_in == ovc);
			    
			 end
		       else
			 assign flit_valid_in = flit_ctrl_in[0];
		       
		    end
		  
		endcase
		
		if(max_packet_length > 1)
		  begin
		     
		     wire flit_count_zero;
		     
		     wire wait_head_s, wait_head_q;
		     assign wait_head_s = (wait_head_q &
					   ~(flit_valid_in & flit_head_in)) |
					  (flit_valid_in & flit_count_zero);
		     dff
		       #(.width(1),
			 .reset_type(reset_type),
			 .reset_value(1'b1))
		     wait_headq
		       (.clk(clk),
			.reset(reset),
			.d(wait_head_s),
			.q(wait_head_q));
		     
		     wire [0:head_info_width-1] head_info;
		     assign head_info = flit_data_in[0:head_info_width-1];
		     
		     wire [0:packet_length_width-1] packet_length;
		     assign packet_length
		       = head_info[route_info_width:
				   route_info_width+packet_length_width-1];
		     
		     wire [0:packet_length_width-1] flit_count_s, flit_count_q;
		     assign flit_count_s
		       = (flit_valid_in & flit_head_in) ?
			 packet_length :
			 (flit_count_q - flit_valid_in);
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
			      = flit_valid_in & (flit_head_in ^ wait_head_q);
		     
		  end
		else
		  assign pkt_error_op_ovc[op*num_vcs+ovc] = 1'b0;
		
	     end

	   wire 				    flit_valid_out;
	   assign flit_valid_out = flit_ctrl_out[0];
	   
	   assign x_error_op[op]
		    = (flit_valid_out === 1'bx) ||
		      ((flit_valid_out === 1'b1) &&
		       (^{flit_ctrl_out, flit_data_out} === 1'bx));
	   
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
   always @(negedge clk)
     begin
	for(port = 0; port < num_ports; port = port + 1)
	  begin
	     if(check_error_op[port])
	       begin
		  $display("check error: op=%d, cyc=%d", port, $time);
		  $display("ctrl=%x, data=%x",
			   flit_ctrl_out_op[port*flit_ctrl_width +:
					    flit_ctrl_width],
			   flit_data_out_op[port*flit_data_width +:
					    flit_data_width]);
	       end
	     if(x_error_op[port])
	       begin
		  $display("X value error: op=%d, cyc=%d", port, $time);
		  $display("ctrl=%x, data=%x",
			   flit_ctrl_out_op[port*flit_ctrl_width +:
					    flit_ctrl_width],
			   flit_data_out_op[port*flit_data_width +:
					    flit_data_width]);
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
   
   integer cycles;
   
   initial
   begin

      reset = 1'b0;
      clk_en = 1'b0;
      run = 1'b0;
      count_en = 1'b0;
      cycles = 0;
      
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
      
      while(in_flits > out_flits)
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
