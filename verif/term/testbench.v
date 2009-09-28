// $Id: testbench.v 1527 2009-09-11 03:12:13Z dub $

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
   
   // width of control register data
   parameter reg_data_width = 32;
   
   // number of bits required to select an individual register
   parameter reg_addr_width = 6;
   
   // width of run cycle counter
   parameter num_packets_width = 16;
   
   // width of arrival rate LFSR
   parameter arrival_rv_width = 16;
   
   // width of payload length selection LFSR
   parameter plength_sel_rv_width = 4;
   
   // width of register that holds the number of outstanding packets
   parameter packet_count_width = 8;
   
   // RNG seed value
   parameter initial_seed = 0;
   
   // channel latency in cycles
   parameter channel_latency = 1;
   
   reg 		    reset;
   reg 		    clk;
   
   reg [0:flit_ctrl_width-1] flit_ctrl_in;
   reg [0:flit_data_width-1] flit_data_in;
   wire [0:flow_ctrl_width-1] flow_ctrl_out;
   
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_data_width-1] flit_data_out;
   wire [0:flow_ctrl_width-1] flow_ctrl_in;
   
   reg 			      reg_write;
   reg 			      reg_read;
   reg [0:reg_addr_width-1]   reg_addr;
   reg [0:reg_data_width-1]   reg_write_data;
   wire [0:reg_data_width-1]  reg_read_data;
   wire 		      reg_done;
   
   wire 		      error;
   
   vcr_term_mac
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
       .reg_data_width(reg_data_width),
       .reg_addr_width(reg_addr_width),
       .num_packets_width(num_packets_width),
       .arrival_rv_width(arrival_rv_width),
       .plength_sel_rv_width(plength_sel_rv_width),
       .packet_count_width(packet_count_width),
       .reset_type(reset_type))
   dut
     (.clk(clk),
      .reset(reset),
      .address(address),
      .flit_ctrl_out(flit_ctrl_out),
      .flit_data_out(flit_data_out),
      .flow_ctrl_in(flow_ctrl_in),
      .flit_ctrl_in(flit_ctrl_in),
      .flit_data_in(flit_data_in),
      .flow_ctrl_out(flow_ctrl_out),
      .reg_write(reg_write),
      .reg_read(reg_read),
      .reg_addr(reg_addr),
      .reg_write_data(reg_write_data),
      .reg_read_data(reg_read_data),
      .reg_done(reg_done),
      .error(error));
   
   wire [0:flit_ctrl_width-1] flit_ctrl_dly;
   
   generate
      
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
		     flit_ctrl_dly_q[0:(channel_latency-1)*flit_ctrl_width-1]};
		assign flit_ctrl_dly
		  = flit_ctrl_dly_q[(channel_latency-1)*flit_ctrl_width:
				    channel_latency*flit_ctrl_width-1];
	     end
	   
	end
      
   endgenerate
   
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
   
   generate
      
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
      
   endgenerate
   
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
      reg_write = 1'b0;
      reg_read = 1'b0;
      reg_addr = 'b0;
      reg_write_data = 'b0;
      done = 1'b0;
      flit_ctrl_in = 'd0;
      flit_data_in = 'd0;
      
      #(Tclk);
      
      reset = 1'b0;
      
      #(Tclk);
      
      clk_en = 1'b1;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd3;
      for(i = 0; i < reg_data_width; i = i + 1)
	reg_write_data[i] = $dist_uniform(seed, 0, 1);
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd4;
      reg_write_data = 'd20;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd5;
      reg_write_data = 'd16384;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd6;
      reg_write_data = 'd8;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd7;
      reg_write_data = 'd0 + 'd4;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(10*Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd0;
      reg_write_data[0] = 'd1;
      reg_write_data[1] = 'd0;
      reg_write_data[2:reg_data_width-1] = 'd0;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      while(!done)
	begin
	   
	   #(10*Tclk);
	   
	   reg_read = 1'b1;
	   reg_addr = 'd1;
	   while(!reg_done)
	     #(Tclk);
	   reg_read = 1'b0;
	   done = ~reg_read_data[0];
	   
	end
      done = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd0;
      reg_write_data = 'd0;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd4;
      reg_write_data = 'd20;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(10*Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd0;
      reg_write_data[0] = 'd1;
      reg_write_data[1] = 'd1;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      while(!done)
	begin
	   
	   #(10*Tclk);
	   
	   reg_read = 1'b1;
	   reg_addr = 'd1;
	   while(!reg_done)
	     #(Tclk);
	   reg_read = 1'b0;
	   done = ~reg_read_data[0];
	   
	end
      done = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd0;
      reg_write_data = 'd0;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(3*Tclk/4);
      
      #(Tclk);
      
      $finish;
      
   end
   
endmodule
