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

`default_nettype none

module testbench
  ();
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
`include "parameters.v"
   
   parameter Tclk = 4;
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // total number of routers
   localparam num_routers
     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   
   // number of routers in each dimension
   localparam num_routers_per_dim = croot(num_routers, num_dimensions);
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // current node's address
   localparam [0:addr_width-1] address = {addr_width{1'b0}};
   
   // connectivity within each dimension
   localparam connectivity
     = (topology == `TOPOLOGY_MESH) ?
       `CONNECTIVITY_LINE :
       (topology == `TOPOLOGY_TORUS) ?
       `CONNECTIVITY_RING :
       (topology == `TOPOLOGY_FBFLY) ?
       `CONNECTIVITY_FULL :
       -1;
   
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
   
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = port_idx_width + ((num_resource_classes > 1) ? 1 : 0);
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
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
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // select set of feedback polynomials used for LFSRs
   parameter lfsr_index = 0;
   
   // number of bits in address that are considered base address
   parameter cfg_addr_prefix_width = 10;
   
   // number of distinct base addresses to which this node replies
   parameter num_cfg_addr_prefixes = 2;
   
   // width of control register data
   parameter cfg_data_width = 32;
   
   // number of bits required to select an individual register
   parameter cfg_addr_width = 16;
   
   // width of register selector part of control register address
   localparam cfg_addr_suffix_width = cfg_addr_width - cfg_addr_prefix_width;
   
   // width of run cycle counter
   parameter num_packets_width = 16;
   
   // width of arrival rate LFSR
   parameter arrival_rv_width = 16;
   
   // width of message class selection LFSR
   parameter mc_idx_rv_width = 4;
   
   // width of resource class selection LFSR
   parameter rc_idx_rv_width = 4;
   
   // width of payload length selection LFSR
   parameter plength_idx_rv_width = 4;
   
   // number of selectable payload lengths
   parameter num_plength_vals = 2;
   
   // width of register that holds the number of outstanding packets
   parameter packet_count_width = 8;
   
   // RNG seed value
   parameter initial_seed = 0;
   
   // channel latency in cycles
   parameter channel_latency = 1;
   
   reg 		    reset;
   reg 		    clk;
   
   wire [0:flit_ctrl_width-1] dut0_flit_ctrl;
   wire [0:flit_data_width-1] dut0_flit_data;
   wire [0:flow_ctrl_width-1] dut0_flow_ctrl;
   
   wire [0:flit_ctrl_width-1] dut1_flit_ctrl_dly;
   wire [0:flit_data_width-1] dut1_flit_data_dly;
   wire [0:flow_ctrl_width-1] dut1_flow_ctrl_dly;
   
   reg [0:num_cfg_addr_prefixes*cfg_addr_prefix_width-1] dut0_cfg_addr_prefixes;
   reg 							 cfg_req;
   reg 							 cfg_write;
   reg [0:cfg_addr_width-1] 				 cfg_addr;
   reg [0:cfg_data_width-1] 				 cfg_write_data;
   wire [0:cfg_data_width-1] 				 dut0_cfg_read_data;
   wire 						 dut0_cfg_done;
   
   wire 						 dut0_error;
   
   tc_node_mac
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .flit_data_width(flit_data_width),
       .error_capture_mode(error_capture_mode),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .lfsr_index(lfsr_index),
       .cfg_data_width(cfg_data_width),
       .cfg_addr_width(cfg_addr_width),
       .num_packets_width(num_packets_width),
       .arrival_rv_width(arrival_rv_width),
       .mc_idx_rv_width(mc_idx_rv_width),
       .rc_idx_rv_width(rc_idx_rv_width),
       .plength_idx_rv_width(plength_idx_rv_width),
       .num_plength_vals(num_plength_vals),
       .packet_count_width(packet_count_width),
       .reset_type(reset_type))
   dut0
     (.clk(clk),
      .reset(reset),
      .address(address),
      .flit_ctrl_out(dut0_flit_ctrl),
      .flit_data_out(dut0_flit_data),
      .flow_ctrl_in(dut1_flow_ctrl_dly),
      .flit_ctrl_in(dut1_flit_ctrl_dly),
      .flit_data_in(dut1_flit_data_dly),
      .flow_ctrl_out(dut0_flow_ctrl),
      .cfg_addr_prefixes(dut0_cfg_addr_prefixes),
      .cfg_req(cfg_req),
      .cfg_write(cfg_write),
      .cfg_addr(cfg_addr),
      .cfg_write_data(cfg_write_data),
      .cfg_read_data(dut0_cfg_read_data),
      .cfg_done(dut0_cfg_done),
      .error(dut0_error));
   
   wire [0:flit_ctrl_width-1] dut1_flit_ctrl;
   c_shift_reg
     #(.width(flit_ctrl_width),
       .depth(channel_latency),
       .reset_type(reset_type))
   dut1_flit_ctrl_dly_sr
     (.clk(clk),
      .reset(reset),
      .enable(1'b1),
      .data_in(dut1_flit_ctrl),
      .data_out(dut1_flit_ctrl_dly));
   
   wire [0:flit_data_width-1] dut1_flit_data;
   c_shift_reg
     #(.width(flit_data_width),
       .depth(channel_latency),
       .reset_type(reset_type))
   dut1_flit_data_dly_sr
     (.clk(clk),
      .reset(reset),
      .enable(1'b1),
      .data_in(dut1_flit_data),
      .data_out(dut1_flit_data_dly));
   
   wire [0:flow_ctrl_width-1] dut1_flow_ctrl;
   c_shift_reg
     #(.width(flow_ctrl_width),
       .depth(channel_latency),
       .reset_type(reset_type))
   dut1_flow_ctrl_dly_sr
     (.clk(clk),
      .reset(reset),
      .enable(1'b1),
      .data_in(dut1_flow_ctrl),
      .data_out(dut1_flow_ctrl_dly));
   
   wire [0:flit_ctrl_width-1] dut0_flit_ctrl_dly;
   c_shift_reg
     #(.width(flit_ctrl_width),
       .depth(channel_latency),
       .reset_type(reset_type))
   dut0_flit_ctrl_dly_sr
     (.clk(clk),
      .reset(reset),
      .enable(1'b1),
      .data_in(dut0_flit_ctrl),
      .data_out(dut0_flit_ctrl_dly));
   
   wire [0:flit_data_width-1] dut0_flit_data_dly;
   c_shift_reg
     #(.width(flit_data_width),
       .depth(channel_latency),
       .reset_type(reset_type))
   dut0_flit_data_dly_sr
     (.clk(clk),
      .reset(reset),
      .enable(1'b1),
      .data_in(dut0_flit_data),
      .data_out(dut0_flit_data_dly));
   
   wire [0:flow_ctrl_width-1] dut0_flow_ctrl_dly;
   c_shift_reg
     #(.width(flow_ctrl_width),
       .depth(channel_latency),
       .reset_type(reset_type))
   dut0_flow_ctrl_dly_sr
     (.clk(clk),
      .reset(reset),
      .enable(1'b1),
      .data_in(dut0_flow_ctrl),
      .data_out(dut0_flow_ctrl_dly));
   
   reg [0:num_cfg_addr_prefixes*cfg_addr_prefix_width-1] dut1_cfg_addr_prefixes;
   wire [0:cfg_data_width-1] 				 dut1_cfg_read_data;
   wire 						 dut1_cfg_done;
   
   wire 						 dut1_error;
   
   tc_node_mac
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .flit_data_width(flit_data_width),
       .error_capture_mode(error_capture_mode),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .lfsr_index(lfsr_index),
       .cfg_data_width(cfg_data_width),
       .cfg_addr_width(cfg_addr_width),
       .num_packets_width(num_packets_width),
       .arrival_rv_width(arrival_rv_width),
       .mc_idx_rv_width(mc_idx_rv_width),
       .rc_idx_rv_width(rc_idx_rv_width),
       .plength_idx_rv_width(plength_idx_rv_width),
       .num_plength_vals(num_plength_vals),
       .packet_count_width(packet_count_width),
       .reset_type(reset_type))
   dut1
     (.clk(clk),
      .reset(reset),
      .address(address),
      .flit_ctrl_out(dut1_flit_ctrl),
      .flit_data_out(dut1_flit_data),
      .flow_ctrl_in(dut0_flow_ctrl_dly),
      .flit_ctrl_in(dut0_flit_ctrl_dly),
      .flit_data_in(dut0_flit_data_dly),
      .flow_ctrl_out(dut1_flow_ctrl),
      .cfg_addr_prefixes(dut1_cfg_addr_prefixes),
      .cfg_req(cfg_req),
      .cfg_write(cfg_write),
      .cfg_addr(cfg_addr),
      .cfg_write_data(cfg_write_data),
      .cfg_read_data(dut1_cfg_read_data),
      .cfg_done(dut1_cfg_done),
      .error(dut1_error));
   
   wire [0:cfg_data_width-1] 				 cfg_read_data;
   assign cfg_read_data = dut0_cfg_read_data | dut1_cfg_read_data;
   
   wire 						 cfg_done;
   assign cfg_done = dut0_cfg_done | dut1_cfg_done;
   
   wire 						 error;
   assign error = dut0_error | dut1_error;
   
   reg 			      clk_en;
   
   always
   begin
      clk <= clk_en;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   always @(posedge clk)
     begin
	if(error)
	  begin
	     $display("internal error detected, cyc=%d", $time);
	     $stop;
	  end
     end
   
   reg done;
   integer i;
   integer seed = initial_seed;
   
   initial
   begin
      
      reset = 1'b0;
      clk_en = 1'b0;
      
      #(Tclk);
      
      #(Tclk/4);
      
      reset = 1'b1;
      dut0_cfg_addr_prefixes[0:cfg_addr_prefix_width-1]
	= 'd0;
      dut0_cfg_addr_prefixes[cfg_addr_prefix_width:2*cfg_addr_prefix_width-1]
	= 'd3;
      dut1_cfg_addr_prefixes[0:cfg_addr_prefix_width-1]
	= 'd1;
      dut1_cfg_addr_prefixes[cfg_addr_prefix_width:2*cfg_addr_prefix_width-1]
	= 'd3;
      cfg_req = 1'b0;
      cfg_write = 1'b0;
      cfg_addr = 'b0;
      cfg_write_data = 'b0;
      done = 1'b0;
      
      #(Tclk);
      
      reset = 1'b0;
      
      #(Tclk);
      
      clk_en = 1'b1;
      
      #(Tclk);
      
      
      // set LFSR seeds
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd0;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd3;
      for(i = 0; i < cfg_data_width; i = i + 1)
	cfg_write_data[i] = $dist_uniform(seed, 0, 1);
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd1;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd3;
      for(i = 0; i < cfg_data_width; i = i + 1)
	cfg_write_data[i] = $dist_uniform(seed, 0, 1);
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // set number of packets
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd4;
      cfg_write_data = 'd0;
      cfg_write_data[0:num_packets_width-1] = 'd1024;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // set arrival rate threshold
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd5;
      cfg_write_data = 'd0;
      cfg_write_data[0:arrival_rv_width-1] = 'd16384;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // set packet length selection threshold
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd6;
      cfg_write_data = 'd0;
      cfg_write_data[0:plength_idx_rv_width-1] = 'd8;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // set packet length values
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd7;
      cfg_write_data = 'd0;
      cfg_write_data[0:payload_length_width-1] = 'd0;
      cfg_write_data[payload_length_width:2*payload_length_width-1] = 'd4;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // set message class selection thresholds
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd8;
      cfg_write_data = 'd0;
      cfg_write_data[0:mc_idx_rv_width-1] = 'd10;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // set resource class selection thresholds
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd9;
      cfg_write_data = 'd0;
      cfg_write_data[0:rc_idx_rv_width-1] = 'd12;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(10*Tclk);
      
      
      // start experiment
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd0;
      cfg_write_data = 'd0;
      cfg_write_data[0] = 'd1;
      cfg_write_data[1] = 'd0;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      
      // wait for experiment to finish
      
      while(!done)
	begin
	   
	   #(10*Tclk);
	   
	   cfg_req = 1'b1;
	   cfg_write = 1'b0;
	   cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
	   cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd1;
	   cfg_write_data = 'd0;
	   while(!cfg_done)
	     #(Tclk);
	   cfg_req = 1'b0;
	   done = ~cfg_read_data[0];
	   
	end
      done = 1'b0;
      
      #(Tclk);
      
      
      // disable nodes
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd0;
      cfg_write_data = 'd0;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(Tclk);
      
      
      // reset number of packets
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd4;
      cfg_write_data = 'd0;
      cfg_write_data[0:num_packets_width-1] = 'd1024;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(10*Tclk);
      
      
      // restart experiment in loopback mode
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd0;
      cfg_write_data = 'd0;
      cfg_write_data[0] = 'd1;
      cfg_write_data[1] = 'd1;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      
      // wait for experiment to finish
      
      while(!done)
	begin
	   
	   #(10*Tclk);
	   
	   cfg_req = 1'b1;
	   cfg_write = 1'b0;
	   cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
	   cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd1;
	   cfg_write_data = 'd0;
	   while(!cfg_done)
	     #(Tclk);
	   cfg_req = 1'b0;
	   done = ~cfg_read_data[0];
	   
	end
      done = 1'b0;
      
      #(Tclk);
      
      
      // disable nodes
      
      cfg_req = 1'b1;
      cfg_write = 1'b1;
      cfg_addr[0:cfg_addr_prefix_width-1] = 'd3;
      cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1] = 'd0;
      cfg_write_data = 'd0;
      while(!cfg_done)
	#(Tclk);
      cfg_req = 1'b0;
      
      #(3*Tclk/4);
      
      #(Tclk);
      
      $finish;
      
   end
   
endmodule
