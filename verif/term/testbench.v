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
   
   // address within each dimensions
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
   
   // number of internal registers
   localparam num_regs = 8;
   
   // number of bits required to select an individual register
   localparam reg_addr_width = clogb(num_regs);
   
   // width of control register data
   parameter reg_data_width = 32;
   
   // width of run cycle counter
   parameter run_ctr_width = 16;
   
   // width of arrival rate LFSR
   parameter arrival_rv_width = 16;
   
   // width of payload length selection LFSR
   parameter plength_sel_rv_width = 4;
   
   // select width (and thus period) for LFSRs
   parameter lfsr_width = 16;
   
   // feedback matrix
   localparam [0:lfsr_width*lfsr_width-1] lfsr_feedback
     = {16'b1100000000010110,
	16'b0110000000001011,
	16'b1011000000010011,
	16'b1101100000011111,
	16'b1110110000011001,
	16'b1111011000011010,
	16'b0111101100001101,
	16'b1011110110010000,
	16'b0101111011001000,
	16'b0010111101100100,
	16'b0001011110110010,
	16'b0000101111011001,
	16'b1000010111111010,
	16'b0100001011111101,
	16'b1010000101101000,
	16'b1101000010100010};
   
   reg 		    reset;
   reg 		    clk;
   
   reg [0:flit_ctrl_width-1] flit_ctrl_in;
   reg [0:flit_data_width-1] flit_data_in;
   wire [0:flow_ctrl_width-1] flow_ctrl_out;
   
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_data_width-1] flit_data_out;
   reg [0:flow_ctrl_width-1]  flow_ctrl_in;
   
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
       . checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .lfsr_width(lfsr_width),
       .reset_type(reset_type))
   dut
     (.clk(clk),
      .reset(reset),
      .lfsr_feedback(lfsr_feedback),
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
      flow_ctrl_in = 'd0;
      
      #(Tclk);
      
      reset = 1'b0;
      
      #(Tclk);
      
      clk_en = 1'b1;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd1;
      reg_write_data[0:run_ctr_width-1] = 'd20;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd3;
      reg_write_data[0:arrival_rv_width-1] = 'd16384;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd5;
      reg_write_data[0:plength_sel_rv_width-1] = 'd8;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd6;
      reg_write_data[0:payload_length_width-1] = 'd0;
      reg_write_data[payload_length_width:2*payload_length_width-1] = 'd4;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      #(10*Tclk);
      
      reg_write = 1'b1;
      reg_addr = 'd0;
      reg_write_data[0] = 'd1;
      while(!reg_done)
	#(Tclk);
      reg_write = 1'b0;
      
      while(!done)
	begin
	   
	   #(10*Tclk);
	   
	   reg_read = 1'b1;
	   reg_addr = 'd0;
	   while(!reg_done)
	     #(Tclk);
	   reg_read = 1'b0;
	   done = ~|reg_read_data;
	   
	end
      
      #(3*Tclk/4);
      
      #(Tclk);
      
      $finish;
      
   end
   
endmodule
