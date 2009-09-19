// $Id: vcr_top.v 1212 2009-04-23 19:52:00Z dub $

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

// network terminal (combined packet source / sink) for VC router
module vcr_term_mac
  (clk, reset, address, flit_ctrl_out, flit_data_out, flow_ctrl_in, 
   flit_ctrl_in, flit_data_in, flow_ctrl_out, reg_write, reg_read, reg_addr, 
   reg_write_data, reg_read_data, reg_done, error);
   
// register address declarations
`define REG_ADDR_CTRL               0
`define REG_ADDR_NUM_PACKETS        1
`define REG_ADDR_ARRIVAL_RV         2
`define REG_ADDR_ARRIVAL_THRESH     3
`define REG_ADDR_PACKET_RVS         4
`define REG_ADDR_PLENGTH_SEL_THRESH 5
`define REG_ADDR_PLENGTH_VALS       6
`define REG_ADDR_FLIT_DATA_RV       7
`define REG_ADDR_LAST `REG_ADDR_FLIT_DATA_RV   
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // width required to select individual message class
   localparam mc_idx_width = clogb(num_message_classes);
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // width required to select individual resource class
   localparam rc_idx_width = clogb(num_resource_classes);
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // width required to select individual packet class
   localparam pc_idx_width = clogb(num_packet_classes);
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of nodes per router (a.k.a. concentration factor)
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
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = port_idx_width + ((num_resource_classes > 1) ? 1 : 0);
   
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
   
   // maximum packet length (in flits)
   localparam max_packet_length = 1 + max_payload_length;
   
   // total number of bits required to represent maximum packet length
   localparam packet_length_width = clogb(max_packet_length);
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // total number of bits of header information encoded in header flit payload
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
   parameter  flit_data_width = 64;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // select width (and thus period) for LFSRs
   parameter lfsr_width = 20;
   
   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   // number of internal registers
   localparam num_regs = `REG_ADDR_LAST + 1;
   
   // number of bits required to select an individual register
   localparam reg_addr_width = clogb(num_regs);
   
   // width of control register data
   parameter reg_data_width = 32;
   
   // width of run cycle counter
   parameter num_packets_width = 16;
   
   // width of arrival rate LFSR
   parameter arrival_rv_width = 16;
   
   // width of payload length selection LFSR
   parameter plength_sel_rv_width = 1;
   
   // width of register that holds the number of outstanding packets
   parameter packet_count_width = 8;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:addr_width-1] address;
   
   // control signals for outgoing flit
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] flit_ctrl_out;
   
   // flit data for outgoing flit
   output [0:flit_data_width-1] flit_data_out;
   wire [0:flit_data_width-1] flit_data_out;
   
   // incoming flow control signals
   input [0:flow_ctrl_width-1] flow_ctrl_in;
   
   // control signals for incoming flit
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // flit data for incoming flit
   input [0:flit_data_width-1] flit_data_in;
   
   // outgoing flow control signals
   output [0:flow_ctrl_width-1] flow_ctrl_out;
   wire [0:flow_ctrl_width-1] flow_ctrl_out;
   
   // config register write access pending
   input reg_write;
   
   // config register read access pending
   input reg_read;
   
   // select config register to access
   input [0:reg_addr_width-1] reg_addr;
   
   // data to be written to selected config register for write accesses
   input [0:reg_data_width-1] reg_write_data;
   
   // contents of selected config register for read accesses
   output [0:reg_data_width-1] reg_read_data;
   wire [0:reg_data_width-1] reg_read_data;
   
   // config register access complete
   output reg_done;
   wire 		     reg_done;
   
   // internal error condition detected
   output error;
   wire 		     error;
   
   
   //---------------------------------------------------------------------------
   // configuration register interface
   //---------------------------------------------------------------------------
   
   wire 		     reg_write_q;
   wire 		     reg_read_q;
   
   wire 		     reg_active_s, reg_active_q;
   assign reg_active_s = (reg_read | reg_write | reg_read_q | reg_write_q);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   reg_activeq
     (.clk(clk),
      .reset(reset),
      .d(reg_active_s),
      .q(reg_active_q));
   
   wire 		     reg_write_s;
   assign reg_write_s = reg_active_q ? reg_write : reg_write_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   reg_writeq
     (.clk(clk),
      .reset(reset),
      .d(reg_write_s),
      .q(reg_write_q));
   
   wire 		     reg_read_s;
   assign reg_read_s = reg_active_q ? reg_read : reg_read_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   reg_readq
     (.clk(clk),
      .reset(reset),
      .d(reg_read_s),
      .q(reg_read_q));
   
   wire [0:reg_addr_width-1] reg_addr_s, reg_addr_q;
   assign reg_addr_s = reg_active_q ? reg_addr : reg_addr_q;
   c_dff
     #(.width(reg_addr_width),
       .reset_type(reset_type))
   reg_addrq
     (.clk(clk),
      .reset(reset),
      .d(reg_addr_s),
      .q(reg_addr_q));
   
   wire 		     reg_sel_ctrl;
   assign reg_sel_ctrl
     = (reg_addr_q == `REG_ADDR_CTRL);
   
   wire 		     reg_sel_num_packets;
   assign reg_sel_num_packets
     = (reg_addr_q == `REG_ADDR_NUM_PACKETS);
   
   wire 		     reg_sel_arrival_thresh;
   assign reg_sel_arrival_thresh
     = (reg_addr_q == `REG_ADDR_ARRIVAL_THRESH);
   
   wire 		     reg_sel_arrival_rv;
   assign reg_sel_arrival_rv
     = (reg_addr_q == `REG_ADDR_ARRIVAL_RV);
   
   wire 		     reg_sel_packet_rvs;
   assign reg_sel_packet_rvs
     = (reg_addr_q == `REG_ADDR_PACKET_RVS);
   
   wire 		     reg_sel_plength_sel_thresh;
   assign reg_sel_plength_sel_thresh
     = (reg_addr_q == `REG_ADDR_PLENGTH_SEL_THRESH);
   
   wire 		     reg_sel_plength_vals;
   assign reg_sel_plength_vals
     = (reg_addr_q == `REG_ADDR_PLENGTH_VALS);
   
   wire 		     reg_sel_flit_data_rv;
   assign reg_sel_flit_data_rv
     = (reg_addr_q == `REG_ADDR_FLIT_DATA_RV);
   
   wire [0:reg_data_width-1] reg_read_data_ctrl;
   wire [0:reg_data_width-1] reg_read_data_num_packets;
   wire [0:reg_data_width-1] reg_read_data_arrival_thresh;
   wire [0:reg_data_width-1] reg_read_data_arrival_rv;
   wire [0:reg_data_width-1] reg_read_data_packet_rvs;
   wire [0:reg_data_width-1] reg_read_data_plength_sel_thresh;
   wire [0:reg_data_width-1] reg_read_data_plength_vals;
   wire [0:reg_data_width-1] reg_read_data_flit_data_rv;
   
   wire [0:num_regs*reg_data_width-1] reg_read_data_vec;
   assign reg_read_data_vec = {reg_read_data_ctrl,
			       reg_read_data_num_packets,
			       reg_read_data_arrival_thresh,
			       reg_read_data_arrival_rv,
			       reg_read_data_packet_rvs,
			       reg_read_data_plength_sel_thresh,
			       reg_read_data_plength_vals,
			       reg_read_data_flit_data_rv};
   
   wire [0:reg_data_width-1] 	      reg_read_data_muxed;
   assign reg_read_data_muxed
     = reg_read_data_vec[reg_addr_q*reg_data_width +: reg_data_width];
   
   wire [0:reg_data_width-1] 	      reg_data_s, reg_data_q;
   assign reg_data_s = reg_active_q ? 
		       (reg_read_q ? reg_read_data_muxed : reg_write_data) : 
		       reg_data_q;
   c_dff
     #(.width(reg_data_width),
       .reset_type(reset_type))
   reg_dataq
     (.clk(clk),
      .reset(reset),
      .d(reg_data_s),
      .q(reg_data_q));
   
   assign reg_read_data = reg_data_q;
   
   wire 			      reg_done_s, reg_done_q;
   assign reg_done_s
     = reg_active_q ? ((reg_write_q | reg_read_q) & ~reg_done_q) : reg_done_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   reg_doneq
     (.clk(clk),
      .reset(reset),
      .d(reg_done_s),
      .q(reg_done_q));
   
   assign reg_done = reg_done_q;
   
   
   //---------------------------------------------------------------------------
   // run control register
   // (writing to this register starts the experiment; 
   // reading from this register returns a non-zero value for as long as there 
   // are more packets and/or flits to send)
   //---------------------------------------------------------------------------
   
   wire 			      write_ctrl;
   assign write_ctrl = reg_write_q & reg_sel_ctrl;
   
   wire 			      ctrl_s, ctrl_q;
   assign ctrl_s = reg_active_q ? (write_ctrl & ~ctrl_q) : ctrl_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   ctrlq
     (.clk(clk),
      .reset(reset),
      .d(ctrl_s),
      .q(ctrl_q));
   
   wire 			      start;
   assign start = ctrl_q;
   
   wire 			      packet_sent;
   wire 			      packet_count_zero;
   wire 			      gen_packets;
   
   wire 			      last_packet_sent;
   assign last_packet_sent = (packet_sent & packet_count_zero & ~gen_packets);
   
   wire 			      num_packets_zero_b;
   
   wire 			      active_s, active_q;
   assign active_s
     = start ? num_packets_zero_b : (active_q & ~last_packet_sent);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   activeq
     (.clk(clk),
      .reset(reset),
      .d(active_s),
      .q(active_q));
   
   c_align
     #(.data_width(1),
       .dest_width(reg_data_width),
       .offset(0))
   reg_read_data_ctrl_alg
     (.data_in(active_q),
      .dest_in({reg_data_width{1'b0}}),
      .data_out(reg_read_data_ctrl));
   
   
   //---------------------------------------------------------------------------
   // specify how many packets to generate during the experiment
   // (special value of -1 corresponds to an infinite number of packets)
   //---------------------------------------------------------------------------
   
   wire 			      write_num_packets;
   assign write_num_packets = reg_write_q & reg_sel_num_packets;
   
   wire [0:num_packets_width-1]       num_packets_s, num_packets_q;
   assign num_packets_s
     = write_num_packets ? reg_data_q[0:num_packets_width-1] : num_packets_q;
   c_dff
     #(.width(num_packets_width),
       .reset_type(reset_type))
   num_packetsq
     (.clk(clk),
      .reset(reset),
      .d(num_packets_s),
      .q(num_packets_q));
   
   assign num_packets_zero_b = |num_packets_q;
   
   wire 			      inf_packets_s, inf_packets_q;
   assign inf_packets_s
     = write_num_packets ? &reg_data_q[0:num_packets_width-1] : inf_packets_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   inf_packetsq
     (.clk(clk),
      .reset(reset),
      .d(inf_packets_q),
      .q(inf_packets_q));
   
   c_align
     #(.data_width(num_packets_width),
       .dest_width(reg_data_width),
       .offset(0))
   reg_read_data_num_packets_alg
     (.data_in(num_packets_q),
      .dest_in({reg_data_width{1'b0}}),
      .data_out(reg_read_data_num_packets));
   
   
   //---------------------------------------------------------------------------
   // run counter
   //---------------------------------------------------------------------------
   
   wire 			      new_packet_rv;
   
   wire 			      update_run_ctr;
   assign update_run_ctr = start | (gen_packets & ~inf_packets_q);
   
   wire [0:num_packets_width-1] 	      run_ctr_s, run_ctr_q;
   assign run_ctr_s
     = update_run_ctr ?
       (start ? num_packets_q : (run_ctr_q - new_packet_rv)) :
       run_ctr_q;
   c_dff
     #(.width(num_packets_width),
       .reset_type(reset_type))
   run_ctrq
     (.clk(clk),
      .reset(reset),
      .d(run_ctr_s),
      .q(run_ctr_q));
   
   assign gen_packets = |run_ctr_q;
   
   
   //---------------------------------------------------------------------------
   // generate packet arrival times
   //---------------------------------------------------------------------------
   
   wire 			      write_arrival_rv;
   assign write_arrival_rv = reg_write_q & reg_sel_arrival_rv;

   wire [0:lfsr_width-1] 	      arrival_rv_feedback;
   c_fbgen
     #(.width(lfsr_width),
       .index(0))
   arrival_rv_feedback_fbgen
     (.feedback(arrival_rv_feedback));
   
   wire [0:lfsr_width-1] 	      arrival_rv_s, arrival_rv_q;
   assign arrival_rv_s
     = {lfsr_width{write_arrival_rv}} & reg_data_q[0:lfsr_width-1];
   c_lfsr
     #(.width(lfsr_width),
       .iterations(lfsr_width),
       .reset_type(reset_type))
   arrival_rv_lfsr
     (.clk(clk),
      .reset(reset),
      .load(write_arrival_rv),
      .run(gen_packets),
      .feedback(arrival_rv_feedback),
      .complete(1'b1),
      .d(arrival_rv_s),
      .q(arrival_rv_q));
   
   wire [0:arrival_rv_width-1] 	      arrival_rv;
   assign arrival_rv = arrival_rv_q[0:arrival_rv_width-1];
   
   c_align
     #(.data_width(arrival_rv_width),
       .dest_width(reg_data_width),
       .offset(0))
   reg_read_data_arrival_rv_alg
     (.data_in(arrival_rv),
      .dest_in({reg_data_width{1'b0}}),
      .data_out(reg_read_data_arrival_rv));
   
   wire 			      write_arrival_thresh;
   assign write_arrival_thresh = reg_write_q & reg_sel_arrival_thresh;
   
   wire [0:arrival_rv_width-1] 	      arrival_thresh_s, arrival_thresh_q;
   assign arrival_thresh_s = write_arrival_thresh ? 
			     reg_data_q[0:arrival_rv_width-1] : 
			     arrival_thresh_q;
   c_dff
     #(.width(arrival_rv_width),
       .reset_type(reset_type))
   arrival_threshq
     (.clk(clk),
      .reset(reset),
      .d(arrival_thresh_s),
      .q(arrival_thresh_q));
   
   assign new_packet_rv = (arrival_rv <= arrival_thresh_q);
   
   c_align
     #(.data_width(arrival_rv_width),
       .dest_width(reg_data_width),
       .offset(0))
   reg_read_data_arrival_thresh_alg
     (.data_in(arrival_thresh_q),
      .dest_in({reg_data_width{1'b0}}),
      .data_out(reg_read_data_arrival_thresh));
   
   
   //---------------------------------------------------------------------------
   // shared LFSR for per-packet random values
   //---------------------------------------------------------------------------
   
   wire 			      write_packet_rvs;
   assign write_packet_rvs = reg_write_q & reg_sel_packet_rvs;
   
   wire [0:lfsr_width-1] 	      packet_rvs_feedback;
   c_fbgen
     #(.width(lfsr_width),
       .index(1))
   packet_rvs_feedback_fbgen
     (.feedback(packet_rvs_feedback));
   
   wire [0:lfsr_width-1] 	      packet_rvs_s, packet_rvs_q;
   assign packet_rvs_s
     = {lfsr_width{write_packet_rvs}} & reg_data_q[0:lfsr_width-1];
   c_lfsr
     #(.width(lfsr_width),
       .iterations(lfsr_width),
       .reset_type(reset_type))
   packet_rvs_lfsr
     (.clk(clk),
      .reset(reset),
      .load(write_packet_rvs),
      .run(packet_sent),
      .feedback(packet_rvs_feedback),
      .complete(1'b1),
      .d(packet_rvs_s),
      .q(packet_rvs_q));
   
   c_align
     #(.data_width(lfsr_width),
       .dest_width(reg_data_width),
       .offset(0))
   reg_read_data_packet_rvs_alg
     (.data_in(packet_rvs_q),
      .dest_in({reg_data_width{1'b0}}),
      .data_out(reg_read_data_packet_rvs));
   
   
   //---------------------------------------------------------------------------
   // determine random message and resource class
   //---------------------------------------------------------------------------
   
   wire [0:num_message_classes-1]     sel_mc_rv;
   wire [0:num_resource_classes-1]    sel_rc_rv;
   
   wire [0:num_packet_classes-1]      sel_pc_rv;
   c_mat_mult
     #(.dim1_width(num_message_classes),
       .dim2_width(1),
       .dim3_width(num_resource_classes))
   sel_pc_rv_mmult
     (.input_a(sel_mc_rv),
      .input_b(sel_rc_rv),
      .result(sel_pc_rv));
   
   wire [0:num_vcs_per_class-1]       vc_alloc_cvc;
   
   wire 			      vc_alloc;
   assign vc_alloc = |vc_alloc_cvc;
   
   wire [0:num_vcs_per_class-1]       next_free_cvc;
   
   wire 			      any_free;
   assign any_free = |next_free_cvc;
   
   wire [0:num_vcs_per_class-1]       sel_cvc;
   assign sel_cvc = vc_alloc ? vc_alloc_cvc : next_free_cvc;
   
   wire [0:num_vcs-1] 		      sel_vc;
   c_mat_mult
     #(.dim1_width(num_packet_classes),
       .dim2_width(1),
       .dim3_width(num_vcs_per_class))
   sel_vc_mmult
     (.input_a(sel_pc_rv),
      .input_b(sel_cvc),
      .result(sel_vc));
   
   wire [0:num_vcs-1] 		      next_free_vc;
   wire [0:num_resource_classes*num_vcs_per_class-1] next_free_rc_cvc;
   
   wire [0:num_vcs-1] 				     free_vc;
   wire [0:num_resource_classes*num_vcs_per_class-1] free_rc_cvc;
   wire [0:num_vcs_per_class-1] 		     free_cvc;
   wire 					     free;
   
   generate
      
      if(num_message_classes > 1)
	begin
	   
	   wire [0:mc_idx_width-1] mc_idx_rv;
	   assign mc_idx_rv
	     = packet_rvs_q[0:mc_idx_width-1] % 
	       num_message_classes;
	   
	   assign next_free_rc_cvc
	     = next_free_vc[mc_idx_rv*num_resource_classes*num_vcs_per_class +: 
			    num_resource_classes*num_vcs_per_class];
	   
	   assign free_rc_cvc
	     = free_vc[mc_idx_rv*num_resource_classes*num_vcs_per_class +: 
		       num_resource_classes*num_vcs_per_class];
	   
	   c_decoder
	     #(.num_ports(num_message_classes))
	   sel_mc_rv_dec
	     (.data_in(mc_idx_rv),
	      .data_out(sel_mc_rv));
	   
	end
      else
	begin
	   assign sel_mc_rv = 1'b1;
	   assign next_free_rc_cvc = next_free_vc;
	   assign free_rc_cvc = free_vc;
	end
      
      if(num_resource_classes > 1)
	begin
	   
	   wire [0:rc_idx_width-1] rc_idx_rv;
	   assign rc_idx_rv
	     = packet_rvs_q[mc_idx_width:(mc_idx_width+rc_idx_width)-1] % 
	       num_resource_classes;
	   
	   assign next_free_cvc
	     = next_free_rc_cvc[rc_idx_rv*num_vcs_per_class +: 
				num_vcs_per_class];
	   
	   assign free_cvc
	     = free_rc_cvc[rc_idx_rv*num_vcs_per_class +: 
			   num_vcs_per_class];
	   
	   c_decoder
	     #(.num_ports(num_resource_classes))
	   sel_rc_rv_dec
	     (.data_in(rc_idx_rv),
	      .data_out(sel_rc_rv));
	   
	end
      else
	begin
	   assign sel_rc_rv = 1'b1;
	   assign next_free_cvc = next_free_rc_cvc;
	   assign free_cvc = free_rc_cvc;
	end
      
      if(num_vcs_per_class > 1)
	begin
	   c_select_1ofn
	     #(.width(1),
	       .num_ports(num_vcs_per_class))
	   free_sel
	     (.select(sel_cvc),
	      .data_in(free_cvc),
	      .data_out(free));
	end
      else
	assign free = free_cvc;
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // VC state tracking
   //---------------------------------------------------------------------------
   
   wire active;
   
   wire flit_sent;
   wire flit_tail;
   
   generate
      
      genvar 					       mc;
      
      for(mc = 0; mc < num_message_classes; mc = mc + 1)
	begin:mcs
	   
	   genvar rc;
	   
	   for(rc = 0; rc < num_resource_classes; rc = rc + 1)
	     begin:rcs
		
		wire sel;
		assign sel = sel_mc_rv[mc] & sel_rc_rv[rc];
		
		genvar cvc;
		
		for(cvc = 0; cvc < num_vcs_per_class; cvc = cvc + 1)
		  begin:cvcs
		     // FIXME
		  end
		
		wire [0:num_vcs_per_class-1] free_cvc_s, free_cvc_q;
		assign free_cvc_s = free_cvc_q; // FIXME
		c_dff
		  #(.width(num_vcs_per_class),
		    .reset_value({num_vcs_per_class{1'b1}}),
		    .reset_type(reset_type))
		free_cvcq
		  (.clk(clk),
		   .reset(reset),
		   .d(free_cvc_s),
		   .q(free_cvc_q));
		
		assign free_vc[(mc*num_resource_classes+rc)*
			       num_vcs_per_class:
			       (mc*num_resource_classes+rc+1)*
			       num_vcs_per_class-1]
			 = free_cvc_q;
		
		wire [0:num_vcs_per_class-1] head_free_cvc_s, head_free_cvc_q;
		assign head_free_cvc_s = head_free_cvc_q; // FIXME
		c_dff
		  #(.width(num_vcs_per_class),
		    .reset_value({num_vcs_per_class{1'b1}}),
		    .reset_type(reset_type))
		head_free_cvcq
		  (.clk(clk),
		   .reset(reset),
		   .d(head_free_cvc_s),
		   .q(head_free_cvc_q));
		
		wire [0:num_vcs_per_class-1] req_cvc;
		assign req_cvc = free_cvc_s & head_free_cvc_s;
		
		wire [0:num_vcs_per_class-1] gnt_cvc;
		c_fp_arbiter
		  #(.num_ports(num_vcs_per_class))
		gnt_cvc_arb
		  (.req(req_cvc),
		   .gnt(gnt_cvc));
		
		wire [0:num_vcs_per_class-1] next_free_cvc_s, next_free_cvc_q;
		assign next_free_cvc_s = active ? gnt_cvc : next_free_cvc_q;
		c_dff
		  #(.width(num_vcs_per_class),
		    .reset_type(reset_type))
		next_free_cvcq
		  (.clk(clk),
		   .reset(reset),
		   .d(next_free_cvc_s),
		   .q(next_free_cvc_q));
		
		assign next_free_vc[(mc*num_resource_classes+rc)*
				    num_vcs_per_class:
				    (mc*num_resource_classes+rc+1)*
				    num_vcs_per_class-1]
			 = next_free_cvc_q;
		
	     end
	   
	end
      
   endgenerate   
   
   
   //---------------------------------------------------------------------------
   // generate random header data
   //---------------------------------------------------------------------------
   
   wire [0:header_info_width-1]    header_info_rv;
   
   
   //---------------------------------------------------------------------------
   // generate random route info
   //---------------------------------------------------------------------------
   
   wire [0:addr_width-1] 	   dest_addr_rv;
   
   wire [0:route_info_width-1] 	   route_info_rv;
   assign route_info_rv[(num_resource_classes-1)*router_addr_width:
			route_info_width-1]
	    = dest_addr_rv;
   
   genvar 			   dim;
   
   generate
      
      
      //------------------------------------------------------------------------
      // generate random final destination address
      //------------------------------------------------------------------------
	   
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   assign dest_addr_rv[dim*dim_addr_width:(dim+1)*dim_addr_width-1]
		    = packet_rvs_q[mc_idx_width+rc_idx_width+
				   (num_resource_classes-1)*router_addr_width+
				   dim*dim_addr_width:
				   mc_idx_width+rc_idx_width+
				   (num_resource_classes-1)*router_addr_width+
				   (dim+1)*dim_addr_width-1] % 
		      num_routers_per_dim;
	   
	end
      
      if(num_nodes_per_router > 1)
	   assign dest_addr_rv[router_addr_width:addr_width-1]
		    = packet_rvs_q[mc_idx_width+rc_idx_width+
				   num_resource_classes*router_addr_width:
				   mc_idx_width+rc_idx_width+
				   num_resource_classes*router_addr_width+
				   node_addr_width-1] % 
		      num_nodes_per_router;
      
      
      //------------------------------------------------------------------------
      // generate random intermediate addresses
      //------------------------------------------------------------------------
      
      if(num_resource_classes > 1)
	begin
	   
	   wire [0:num_resource_classes*router_addr_width-1] intm_addr_rvs;
	   assign intm_addr_rvs[(num_resource_classes-1)*router_addr_width:
				num_resource_classes*router_addr_width-1]
		    = dest_addr_rv[0:router_addr_width-1];
	   
	   genvar 					     rc;
	   
	   for(rc = 0; rc < (num_resource_classes - 1); rc = rc + 1)
	     begin:rcs

		wire [0:router_addr_width-1] intm_addr_rv;
		
		for(dim = 0; dim < num_dimensions; dim = dim + 1)
		  begin:dims
		     
		     assign intm_addr_rv[dim*dim_addr_width:
					 (dim+1)*dim_addr_width-1]
			      = packet_rvs_q[mc_idx_width+rc_idx_width+
					     rc*router_addr_width+
					     dim*dim_addr_width:
					     mc_idx_width+rc_idx_width+
					     rc*router_addr_width+
					     (dim+1)*dim_addr_width-1] %
				num_routers_per_dim;
		     
		  end
		
		assign intm_addr_rvs[rc*router_addr_width:
				     (rc+1)*router_addr_width-1]
			 = intm_addr_rv;
		
		// get the intermediate address for the next resource class
		wire [0:router_addr_width-1] next_addr_rv;
		assign next_addr_rv = intm_addr_rvs[(rc+1)*router_addr_width:
						    (rc+2)*router_addr_width-1];
		
		//--------------------------------------------------------------
		// NOTE:
		//--------------------------------------------------------------
		// Packets transition from one resource class to the next at 
		// each intermediate address; in particular, the router logic
		// assumes that a packet's current resource class is incremented
		// by one at each intermediate address. Thus, the router cannot
		// currently handle the case where multiple successive 
		// intermediate addresses (or the last intermediate and the 
		// final address) are identical, as this would require the
		// resource class to be incremented by more than one or the 
		// packet to be moved between different VCs at a router's input 
		// port, neither of which the RTL currently supports. 
		// Consequently, we must make sure that no two successive 
		// intermediate addresses nor the last intermediate and the 
		// final destination addresses are pairwise identical. 
		//--------------------------------------------------------------
		
		// if the intermediate address for the current resource class 
		// matches that for the next one, ...
		wire 			     flip_bits;
		assign flip_bits = (intm_addr_rv == next_addr_rv);
		
		// ... flip all its bits to get a different intermediate address
		assign route_info_rv[rc*router_addr_width:
				     (rc+1)*router_addr_width-1]
			 = intm_addr_rv ^ {router_addr_width{flip_bits}};
		
	     end
	   
	end
      
   endgenerate
   
   assign header_info_rv[la_route_info_width:
			 la_route_info_width+route_info_width-1]
	    = route_info_rv;
   
   
   //---------------------------------------------------------------------------
   // generate random lookahead routing info
   //---------------------------------------------------------------------------

   wire [0:router_addr_width-1] 	     router_address;
   assign router_address = address[0:router_addr_width-1];
   
   wire [0:port_idx_width-1] 		     route_port_rv;
   wire 				     inc_rc_rv;
   vcr_routing_logic
     #(.num_resource_classes(num_resource_classes),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order),
       .reset_type(reset_type))
   rtl
     (.clk(clk),
      .reset(reset),
      .router_address(router_address),
      .sel_rc(sel_rc_rv),
      .route_info(route_info_rv),
      .route_port(route_port_rv),
      .inc_rc(inc_rc_rv));
   
   wire [0:la_route_info_width-1] 	     la_route_info_rv;
   assign la_route_info_rv[0:port_idx_width-1] = route_port_rv;
   
   generate
      
      if(num_resource_classes > 1)
	assign la_route_info_rv[port_idx_width] = inc_rc_rv;
      
   endgenerate
   
   assign header_info_rv[0:la_route_info_width-1]
	    = la_route_info_rv;
   
   
   //---------------------------------------------------------------------------
   // generate random packet length
   //---------------------------------------------------------------------------
   
   wire [0:packet_length_width-1] 	     flit_count_rv;
   
   generate
      
      if(max_payload_length > min_payload_length)
	begin
	   
	   wire write_plength_sel_thresh;
	   assign write_plength_sel_thresh
	     = reg_write_q & reg_sel_plength_sel_thresh;
	   
	   wire [0:plength_sel_rv_width-1] plength_sel_thresh_s, 
					   plength_sel_thresh_q;
	   assign plength_sel_thresh_s = write_plength_sel_thresh ? 
					 reg_data_q[0:plength_sel_rv_width-1] :
					 plength_sel_thresh_q;
	   c_dff
	     #(.width(plength_sel_rv_width),
	       .reset_type(reset_type))
	   plength_sel_threshq
	     (.clk(clk),
	      .reset(reset),
	      .d(plength_sel_thresh_s),
	      .q(plength_sel_thresh_q));
	   
	   c_align
	     #(.data_width(plength_sel_rv_width),
	       .dest_width(reg_data_width),
	       .offset(0))
	   reg_read_data_plength_sel_thresh_alg
	     (.data_in(plength_sel_thresh_q),
	      .dest_in({reg_data_width{1'b0}}),
	      .data_out(reg_read_data_plength_sel_thresh));
	   
	   wire [0:plength_sel_rv_width-1] plength_sel_rv;
	   assign plength_sel_rv
	     = packet_rvs_q[mc_idx_width+rc_idx_width+route_info_width:
			    mc_idx_width+rc_idx_width+route_info_width+
			    plength_sel_rv_width-1];
	   
	   wire 			   write_plength_vals;
	   assign write_plength_vals = reg_write_q & reg_sel_plength_vals;
	   
	   wire [0:2*payload_length_width-1] plength_vals_s, plength_vals_q;
	   assign plength_vals_s
	     = write_plength_vals ? 
	       reg_data_q[0:2*payload_length_width-1] : 
	       plength_vals_q;
	   c_dff
	     #(.width(2*payload_length_width),
	       .reset_type(reset_type))
	   plength_valsq
	     (.clk(clk),
	      .reset(reset),
	      .d(plength_vals_s),
	      .q(plength_vals_q));
	   
	   c_align
	     #(.data_width(2*payload_length_width),
	       .dest_width(reg_data_width),
	       .offset(0))
	   reg_read_data_plength_vals_alg
	     (.data_in(plength_vals_q),
	      .dest_in({reg_data_width{1'b0}}),
	      .data_out(reg_read_data_plength_vals));
	   
	   wire [0:payload_length_width-1] plength_rv;
	   assign plength_rv
	     = (plength_sel_rv >= plength_sel_thresh_q) ? 
	       plength_vals_q[payload_length_width:2*payload_length_width-1] : 
	       plength_vals_q[0:payload_length_width-1];
	   
	   if(packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH)
	     assign header_info_rv[la_route_info_width+route_info_width:
				   la_route_info_width+route_info_width+
				   payload_length_width-1]
		      = plength_rv;
	   
	   assign flit_count_rv = min_payload_length + plength_rv;
	   
	end
      else
	assign flit_count_rv = min_payload_length;
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // keep track of packets being processed
   //---------------------------------------------------------------------------
   
   wire 				   packet_count_zero_b;
   wire 				   packet_valid_q;
   
   assign active = start | gen_packets | packet_count_zero_b | packet_valid_q;
   
   wire 				   packet_count_decr;
   assign packet_count_decr
     = (~packet_valid_q | packet_sent) & (packet_count_zero_b | new_packet_rv);
   
   wire 				   packet_count_max_b;
   
   wire 				   packet_count_incr;
   assign packet_count_incr
     = new_packet_rv & (packet_count_max_b | ~packet_valid_q | packet_sent);
   
   wire [0:packet_count_width-1] 	   packet_count_s, packet_count_q;
   assign packet_count_s
     = active ?
       ({packet_count_width{~start}} &
	(packet_count_q + packet_count_incr - packet_count_decr)) : 
       packet_count_q;
   c_dff
     #(.width(packet_count_width),
       .reset_type(reset_type))
   packet_countq
     (.clk(clk),
      .reset(reset),
      .d(packet_count_s),
      .q(packet_count_q));
   
   assign packet_count_zero = ~|packet_count_q;
   assign packet_count_zero_b = |packet_count_q;
   assign packet_count_max_b = ~&packet_count_q;
   
   wire 				   packet_valid_s;
   assign packet_valid_s
     = active ? 
       (((packet_valid_q  & ~packet_sent) | 
	 packet_count_zero_b | new_packet_rv) & 
	~start) : 
       packet_valid_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   packet_validq
     (.clk(clk),
      .reset(reset),
      .d(packet_valid_s),
      .q(packet_valid_q));
   
   assign flit_sent = packet_valid_q & (vc_alloc ? free : any_free);
   
   assign flit_ctrl_out[0] = flit_sent;
   
   wire [0:packet_length_width-1] 	   flit_count_s, flit_count_q;
   assign flit_count_s
     = active ? 
       ((start | packet_sent) ? flit_count_rv : (flit_count_q - flit_sent)) : 
       flit_count_q;
   c_dff
     #(.width(packet_length_width),
       .reset_type(reset_type))
   flit_countq
     (.clk(clk),
      .reset(reset),
      .d(flit_count_s),
      .q(flit_count_q));
   
   wire 				   flit_count_zero;
   assign flit_count_zero = ~|flit_count_q;
   
   assign packet_sent = flit_sent & flit_count_zero;
   assign flit_tail = flit_count_zero;
   
   wire [0:num_vcs_per_class-1] 	   vc_alloc_cvc_s, vc_alloc_cvc_q;
   assign vc_alloc_cvc_s
     = active ? 
       ((vc_alloc_cvc_q & {num_vcs_per_class{~start & ~packet_sent}}) | 
	({num_vcs_per_class{~vc_alloc}} & next_free_cvc)) : 
       vc_alloc_cvc_q;
   c_dff
     #(.width(num_vcs_per_class),
       .reset_type(reset_type))
   vc_alloc_cvcq
     (.clk(clk),
      .reset(reset),
      .d(vc_alloc_cvc_s),
      .q(vc_alloc_cvc_q));

   assign vc_alloc_cvc = vc_alloc_cvc_q;
   assign vc_alloc = |vc_alloc_cvc_q;
   
   wire 				   flit_head;
   
   generate
      
      if(max_payload_length > 0)
	begin
	   
	   wire flit_head_s, flit_head_q;
	   assign flit_head_s
	     = active ? 
	       ((flit_head_q & ~flit_sent) | start | packet_sent) : 
	       flit_head_q;
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_headq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_head_s),
	      .q(flit_head_q));
	   
	   assign flit_head = flit_head_q;
	   
	end
      else
	assign flit_head = 1'b1;
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc;
	   c_encoder
	     #(.num_ports(num_vcs))
	   flit_vc_enc
	     (.data_in(sel_vc),
	      .data_out(flit_vc));
	   
	   assign flit_ctrl_out[1:1+vc_idx_width-1] = flit_vc;
	   
	end
      
      if(packet_format == `PACKET_FORMAT_HEAD_TAIL)
	assign flit_ctrl_out[1+vc_idx_width+1] = flit_tail;
      
   endgenerate
   
   assign flit_ctrl_out[1+vc_idx_width+0] = flit_head;
   
   
   //---------------------------------------------------------------------------
   // generate random payload data and signature
   //---------------------------------------------------------------------------
   
   wire 				   write_flit_data_rv;
   assign write_flit_data_rv = reg_write_q & reg_sel_flit_data_rv;

   // zero-extend (or truncate) load value to full flit width
   wire [0:flit_data_width-1] 		   flit_data_new;
   c_align
     #(.data_width(reg_data_width),
       .dest_width(flit_data_width),
       .offset(0))
   flit_data_new_alg
     (.data_in(reg_data_q),
      .dest_in({flit_data_width{1'b0}}),
      .data_out(flit_data_new));
   
   wire 				   flit_received;
   assign flit_received = flit_ctrl_in[0];
   
   wire [0:flit_data_width-1] 		   flit_data_rv;
   wire [0:flit_data_width-1] 		   flit_sig;
   
   genvar 				   blk;
   
   generate
      
      for(blk = 0; blk < (flit_data_width / lfsr_width); blk = blk + 1)
	begin:blks

	   wire [0:lfsr_width-1] flit_data_rv_feedback;
	   c_fbgen
	     #(.width(lfsr_width),
	       .index(2+blk))
	   flit_data_rv_feedback_fbgen
	     (.feedback(flit_data_rv_feedback));
	   
	   wire [0:lfsr_width-1] flit_data_rv_s, flit_data_rv_q;
	   assign flit_data_rv_s
	     = {lfsr_width{write_flit_data_rv}} & 
	       flit_data_new[blk*lfsr_width:(blk+1)*lfsr_width-1];
	   c_lfsr
	     #(.width(lfsr_width),
	       .iterations(lfsr_width),
	       .reset_type(reset_type))
	   flit_data_rv_lfsr
	     (.clk(clk),
	      .reset(reset),
	      .load(write_flit_data_rv),
	      .run(flit_sent),
	      .feedback(flit_data_rv_feedback),
	      .complete(1'b1),
	      .d(flit_data_rv_s),
	      .q(flit_data_rv_q));
	   
	   assign flit_data_rv[blk*lfsr_width:(blk+1)*lfsr_width-1]
		    = flit_data_rv_q;
	   
	   wire [0:lfsr_width-1] flit_sig_s, flit_sig_q;
	   assign flit_sig_s
	     = {lfsr_width{flit_received & ~start}} & 
	       flit_data_in[blk*lfsr_width:(blk+1)*lfsr_width-1];
	   c_lfsr
	     #(.width(lfsr_width),
	       .iterations(lfsr_width),
	       .reset_type(reset_type))
	   flit_sig_lfsr
	     (.clk(clk),
	      .reset(reset),
	      .load(start),
	      .run(flit_received),
	      .feedback(flit_data_rv_feedback),
	      .complete(1'b1),
	      .d(flit_sig_s),
	      .q(flit_sig_q));
	   
	   assign flit_sig[blk*lfsr_width:(blk+1)*lfsr_width-1]
		    = flit_sig_q;
	   
	end
      
      if((flit_data_width % lfsr_width) > 0)
	begin
	   
	   wire [0:lfsr_width-1] flit_data_rv_feedback;
	   c_fbgen
	     #(.width(lfsr_width),
	       .index(2+(flit_data_width / lfsr_width)))
	   flit_data_rv_feedback_fbgen
	     (.feedback(flit_data_rv_feedback));
	   
	   wire [0:lfsr_width-1] flit_data_rv_s, flit_data_rv_q;
	   assign flit_data_rv_s[0:(flit_data_width % lfsr_width)-1]
		    = {(flit_data_width % lfsr_width){write_flit_data_rv}} & 
		      flit_data_new[(flit_data_width / lfsr_width)*lfsr_width:
				    flit_data_width-1];
	   assign flit_data_rv_s[(flit_data_width % lfsr_width):lfsr_width-1]
		    = {(lfsr_width - (flit_data_width % lfsr_width)){1'b0}};
	   c_lfsr
	     #(.width(lfsr_width),
	       .iterations(lfsr_width),
	       .reset_type(reset_type))
	   flit_data_rv_lfsr
	     (.clk(clk),
	      .reset(reset),
	      .load(write_flit_data_rv),
	      .run(flit_sent),
	      .feedback(flit_data_rv_feedback),
	      .complete(1'b1),
	      .d(flit_data_rv_s),
	      .q(flit_data_rv_q));
	   
	   assign flit_data_rv[(flit_data_width / lfsr_width)*lfsr_width:
			       flit_data_width-1]
		    = flit_data_rv_q;

	   wire [0:lfsr_width-1] flit_sig_s, flit_sig_q;
	   assign flit_sig_s[0:(flit_data_width % lfsr_width)-1]
		    = flit_data_in[(flit_data_width / lfsr_width)*lfsr_width:
				   flit_data_width-1];
	   assign flit_sig_s[(flit_data_width % lfsr_width):lfsr_width-1]
		    = {(lfsr_width - (flit_data_width % lfsr_width)){1'b0}};
	   c_lfsr
	     #(.width(lfsr_width),
	       .iterations(lfsr_width),
	       .reset_type(reset_type))
	   flit_sig_lfsr
	     (.clk(clk),
	      .reset(reset),
	      .load(start),
	      .run(flit_received),
	      .feedback(flit_data_rv_feedback),
	      .complete(1'b1),
	      .d(flit_sig_s),
	      .q(flit_sig_q));
	   
	   assign flit_sig[(flit_data_width / lfsr_width)*lfsr_width:
			   flit_data_width-1]
		    = flit_sig_q;

	end
      
   endgenerate
   
   assign flit_data_out[0:header_info_width-1]
	    = flit_head ? header_info_rv : flit_data_rv[0:header_info_width-1];
   assign flit_data_out[header_info_width:flit_data_width-1]
	    = flit_data_rv[header_info_width:flit_data_width-1];
   
   c_align
     #(.data_width(flit_data_width),
       .dest_width(reg_data_width),
       .offset(0))
   reg_read_data_flit_data_rv_alg
     (.data_in(flit_sig),
      .dest_in({reg_data_width{1'b0}}),
      .data_out(reg_read_data_flit_data_rv));
   
   
endmodule
