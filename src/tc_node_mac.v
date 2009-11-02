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

// network pseudo-node (combined packet source / sink)
module tc_node_mac
  (clk, reset, router_address, port_id, flit_ctrl_out, flit_data_out, 
   flow_ctrl_in, flit_ctrl_in, flit_data_in, flow_ctrl_out, cfg_addr_prefixes, 
   cfg_req, cfg_write, cfg_addr, cfg_write_data, cfg_read_data, cfg_done, 
   error);
   
// register address declarations
`define CFG_ADDR_CTRL            0
`define CFG_ADDR_STATUS          1
`define CFG_ADDR_FLIT_SIG        2
`define CFG_ADDR_LFSR_SEED       3
`define CFG_ADDR_NUM_PACKETS     4
`define CFG_ADDR_ARRIVAL_THRESH  5
`define CFG_ADDR_PLENGTH_THRESHS 6
`define CFG_ADDR_PLENGTH_VALS    7
`define CFG_ADDR_MC_THRESHS      8
`define CFG_ADDR_RC_THRESHS      9
`define CFG_ADDR_ERROR           10
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
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
   parameter flit_data_width = 64;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // include error checking logic
   parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width = 1 + vc_idx_width + 1 + 1;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_DOR;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select set of feedback polynomials used for LFSRs
   parameter lfsr_index = 0;
   
   // number of bits in address that are considered base address
   parameter cfg_addr_prefix_width = 10;
   
   // width of register selector part of control register address
   parameter cfg_addr_suffix_width = 6;
   
   // width of configuration bus addresses
   localparam cfg_addr_width = cfg_addr_prefix_width + cfg_addr_suffix_width;
   
   // number of distinct base addresses to which this node replies
   parameter num_cfg_addr_prefixes = 2;
   
   // width of control register data
   parameter cfg_data_width = 32;
   
   // smallest multiple of cfg_data_width that is >= flit_data_width
   localparam flit_sig_exp_width
     = ((flit_data_width+cfg_data_width-1)/cfg_data_width)*cfg_data_width;
   
   // width of run cycle counter
   parameter num_packets_width = 20;
   
   // width of arrival rate LFSR
   parameter arrival_rv_width = 20;
   
   // width of message class selection LFSR
   parameter mc_idx_rv_width = 1;
   
   // width of message class threshold register
   localparam mc_threshs_width = (num_message_classes - 1) * mc_idx_rv_width;
   
   // width of resource class selection LFSR
   parameter rc_idx_rv_width = 1;
   
   // width of resource class threshold register
   localparam rc_threshs_width = (num_resource_classes - 1) * rc_idx_rv_width;
   
   // width of payload length selection LFSR
   parameter plength_idx_rv_width = 1;
   
   // number of selectable payload lengths
   parameter num_plength_vals = 2;
   
   // width of packet length threshold register
   localparam plength_threshs_width
     = (num_plength_vals - 1) * plength_idx_rv_width;
   
   // width of packet length value register
   localparam plength_vals_width = num_plength_vals * payload_length_width;
   
   // select width (and thus period) for LFSRs
   localparam packet_rvs_width
     = mc_idx_rv_width + rc_idx_rv_width + route_info_width + 
       plength_idx_rv_width;
   
   // width of register that holds the number of outstanding packets
   parameter packet_count_width = 8;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current node's address
   input [0:router_addr_width-1] router_address;
   
   // router port to which this node is attached
   input [0:port_idx_width-1] port_id;
   
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
   
   // address prefixes assigned to this node
   input [0:num_cfg_addr_prefixes*cfg_addr_prefix_width-1] cfg_addr_prefixes;
   
   // config register access pending
   input cfg_req;
   
   // config register access is write access
   input cfg_write;
   
   // select config register to access
   input [0:cfg_addr_width-1] cfg_addr;
   
   // data to be written to selected config register for write accesses
   input [0:cfg_data_width-1] cfg_write_data;
   
   // contents of selected config register for read accesses
   output [0:cfg_data_width-1] cfg_read_data;
   wire [0:cfg_data_width-1] cfg_read_data;
   
   // config register access complete
   output cfg_done;
   wire 		     cfg_done;
   
   // internal error condition detected
   output error;
   wire 		     error;
   
   
   //---------------------------------------------------------------------------
   // configuration register interface
   //---------------------------------------------------------------------------
   
   wire 		     cfg_req_s, cfg_req_q;
   assign cfg_req_s = cfg_req;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cfg_reqq
     (.clk(clk),
      .reset(reset),
      .d(cfg_req_s),
      .q(cfg_req_q));
   
   wire 		     cfg_enable;
   
   wire 		     cfg_active_s, cfg_active_q;
   assign cfg_active_s = cfg_enable ? cfg_req_q : cfg_active_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cfg_activeq
     (.clk(clk),
      .reset(reset),
      .d(cfg_active_s),
      .q(cfg_active_q));

   wire 		     cfg_write_s, cfg_write_q;
   assign cfg_write_s = cfg_enable ? cfg_write : cfg_write_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cfg_writeq
     (.clk(clk),
      .reset(reset),
      .d(cfg_write_s),
      .q(cfg_write_q));
   
   wire 		     cfg_do_write;
   assign cfg_do_write = cfg_active_q & cfg_write_q;
   
   wire [0:cfg_addr_prefix_width-1] cfg_addr_prefix;
   assign cfg_addr_prefix = cfg_addr[0:cfg_addr_prefix_width-1];
   
   wire [0:cfg_addr_prefix_width-1] cfg_addr_prefix_s, cfg_addr_prefix_q;
   assign cfg_addr_prefix_s = cfg_enable ? cfg_addr_prefix : cfg_addr_prefix_q;
   c_dff
     #(.width(cfg_addr_prefix_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   cfg_addr_prefixq
     (.clk(clk),
      .reset(reset),
      .d(cfg_addr_prefix_s),
      .q(cfg_addr_prefix_q));
   
   wire [0:num_cfg_addr_prefixes-1] cfg_prefix_match;
   
   genvar 			    prefix;
   
   generate
      
      for(prefix = 0; prefix < num_cfg_addr_prefixes; prefix = prefix + 1)
	begin:prefixes
	   
	   assign cfg_prefix_match[prefix]
		    = (cfg_addr_prefix_q == 
		       cfg_addr_prefixes[prefix*cfg_addr_prefix_width:
					 (prefix+1)*cfg_addr_prefix_width-1]);
	   
	end
      
   endgenerate
   
   wire 		     cfg_sel_node;
   assign cfg_sel_node = |cfg_prefix_match;
   
   wire [0:cfg_addr_suffix_width-1] cfg_addr_suffix;
   assign cfg_addr_suffix = cfg_addr[cfg_addr_prefix_width:cfg_addr_width-1];
   
   wire [0:cfg_addr_suffix_width-1] cfg_addr_suffix_s, cfg_addr_suffix_q;
   assign cfg_addr_suffix_s = cfg_enable ? cfg_addr_suffix : cfg_addr_suffix_q;
   c_dff
     #(.width(cfg_addr_suffix_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   cfg_addr_suffixq
     (.clk(clk),
      .reset(reset),
      .d(cfg_addr_suffix_s),
      .q(cfg_addr_suffix_q));
   
   wire 			    cfg_sel_ctrl;
   assign cfg_sel_ctrl
     =  cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_CTRL);
   
   wire 			    cfg_sel_status;
   assign cfg_sel_status
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_STATUS);
   
   wire 			    cfg_sel_flit_sig;
   assign cfg_sel_flit_sig
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_FLIT_SIG);
   
   wire 			    cfg_sel_lfsr_seed;
   assign cfg_sel_lfsr_seed
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_LFSR_SEED);
   
   wire 			    cfg_sel_num_packets;
   assign cfg_sel_num_packets
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_NUM_PACKETS);
   
   wire 			    cfg_sel_arrival_thresh;
   assign cfg_sel_arrival_thresh
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_ARRIVAL_THRESH);
   
   wire 			    cfg_sel_plength_threshs;
   assign cfg_sel_plength_threshs
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_PLENGTH_THRESHS);
   
   wire 			    cfg_sel_plength_vals;
   assign cfg_sel_plength_vals
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_PLENGTH_VALS);
   
   wire 			    cfg_sel_mc_threshs;
   assign cfg_sel_mc_threshs
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_MC_THRESHS);
   
   wire 			    cfg_sel_rc_threshs;
   assign cfg_sel_rc_threshs
     = cfg_sel_node && (cfg_addr_suffix_q == `CFG_ADDR_RC_THRESHS);
   
   wire [0:cfg_data_width-1] 	    cfg_read_data_status;
   wire [0:cfg_data_width-1] 	    cfg_read_data_flit_sig;
   wire [0:cfg_data_width-1] 	    cfg_read_data_num_packets;
   
   wire [0:cfg_data_width-1] 	    cfg_read_data_muxed;
   c_select_mofn
     #(.num_ports(3),
       .width(cfg_data_width))
   cfg_read_data_muxed_sel
     (.select({cfg_sel_status, 
	       cfg_sel_flit_sig, 
	       cfg_sel_num_packets}),
      .data_in({cfg_read_data_status, 
		cfg_read_data_flit_sig, 
		cfg_read_data_num_packets}),
      .data_out(cfg_read_data_muxed));
   
   wire [0:cfg_data_width-1] 	    cfg_data_s, cfg_data_q;
   assign cfg_data_s = cfg_enable ? 
		       (cfg_req_q ? cfg_write_data : cfg_read_data_muxed) : 
		       cfg_data_q;
   c_dff
     #(.width(cfg_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   cfg_dataq
     (.clk(clk),
      .reset(reset),
      .d(cfg_data_s),
      .q(cfg_data_q));
   
   assign cfg_read_data = cfg_data_q;
   
   wire 			    cfg_done_s, cfg_done_q;
   assign cfg_done_s = cfg_enable ? (cfg_active_q & cfg_sel_node) : cfg_done_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cfg_doneq
     (.clk(clk),
      .reset(reset),
      .d(cfg_done_s),
      .q(cfg_done_q));
   
   assign cfg_done = cfg_done_q;
   
   assign cfg_enable = cfg_req_q | cfg_active_q | cfg_done_q;
   
   
   //---------------------------------------------------------------------------
   // run control register
   // ====================
   // Setting bit 0 of this register to 1'b1 wakes up the terminal and starts 
   // the experiment; setting it to 1'b0 stops it and puts the terminal into 
   // idle mode.
   // If bit 1 of this register is set, the traffic generator is operated in
   // loopback mode; i.e., its outputs are fed back into its inputs.
   //---------------------------------------------------------------------------
   
   wire 			    write_ctrl;
   assign write_ctrl = cfg_do_write & cfg_sel_ctrl;
   
   wire 			    active_s, active_q;
   assign active_s
     = cfg_active_q ? (write_ctrl ? cfg_data_q[0] : active_q) : active_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   activeq
     (.clk(clk),
      .reset(reset),
      .d(active_s),
      .q(active_q));
   
   wire 			    loopback_s, loopback_q;
   assign loopback_s
     = cfg_active_q ? (write_ctrl ? cfg_data_q[1] : loopback_q) : loopback_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   loopbackq
     (.clk(clk),
      .reset(reset),
      .d(loopback_s),
      .q(loopback_q));
   
   wire [0:flit_ctrl_width-1] 	    flit_ctrl_muxed;
   assign flit_ctrl_muxed = loopback_q ? flit_ctrl_out : flit_ctrl_in;
   
   wire [0:flit_data_width-1] 	    flit_data_muxed;
   assign flit_data_muxed = loopback_q ? flit_data_out : flit_data_in;

   wire [0:flow_ctrl_width-1] 	    flow_ctrl_muxed;
   assign flow_ctrl_muxed = loopback_q ? flow_ctrl_out : flow_ctrl_in;
   
   wire 			    start_s, start_q;
   assign start_s = cfg_enable ? (write_ctrl & cfg_data_q[0]) : start_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   startq
     (.clk(clk),
      .reset(reset),
      .d(start_s),
      .q(start_q));
   
   
   //---------------------------------------------------------------------------
   // status register
   // ===============
   // Bit 0 of this register is non-zero for as long as there are packets 
   // and/or flits left to send.
   // Bit 1 of this register is the summary error bit, i.e., the output of the 
   // error reporting logic.
   //---------------------------------------------------------------------------
   
   wire 			    packet_count_zero;
   wire 			    gen_packets;
   wire 			    packet_valid_q;
   wire [0:num_vcs-1] 		    empty_ovc;
   
   wire 			    last_credit_received;
   assign last_credit_received
     = (~gen_packets & packet_count_zero & ~packet_valid_q & &empty_ovc);
   
   wire 			    running_s, running_q;
   assign running_s = active_q ? 
		      ((running_q & ~last_credit_received) | start_q) : 
		      running_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   runningq
     (.clk(clk),
      .reset(reset),
      .d(running_s),
      .q(running_q));
   
   c_align
     #(.data_width(2),
       .dest_width(cfg_data_width))
   cfg_read_data_status_alg
     (.data_in({running_q, error}),
      .dest_in({cfg_data_width{1'b0}}),
      .data_out(cfg_read_data_status));
   
   
   //---------------------------------------------------------------------------
   // packet count register
   // =====================
   // specify how many packets to generate during the experiment
   // (special value of -1 corresponds to an infinite number of packets)
   //---------------------------------------------------------------------------
   
   wire [0:num_packets_width-1]     num_packets_loadval;
   c_align
     #(.data_width(cfg_data_width),
       .dest_width(num_packets_width))
   num_packets_loadval_alg
     (.data_in(cfg_data_q),
      .dest_in({num_packets_width{1'b0}}),
      .data_out(num_packets_loadval));
   
   wire 			    num_packets_zero;
   wire [0:num_packets_width-1]     num_packets_q;
   wire 			    inf_packets_q;
   wire 			    new_packet_rv;
   
   wire [0:num_packets_width-1]     num_packets_next;
   assign num_packets_next = (~active_q | inf_packets_q | num_packets_zero) ? 
			     num_packets_q : 
			     (num_packets_q - new_packet_rv);
   
   wire 			    write_num_packets;
   assign write_num_packets = cfg_do_write & cfg_sel_num_packets;
   
   wire [0:num_packets_width-1]     num_packets_s;
   assign num_packets_s
     = (cfg_active_q | active_q) ? 
       (write_num_packets ? num_packets_loadval : num_packets_next) : 
       num_packets_q;
   c_dff
     #(.width(num_packets_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   num_packetsq
     (.clk(clk),
      .reset(reset),
      .d(num_packets_s),
      .q(num_packets_q));

   assign num_packets_zero = ~|num_packets_q;
   
   c_align
     #(.data_width(num_packets_width),
       .dest_width(cfg_data_width))
   cfg_read_data_num_packets_alg
     (.data_in(num_packets_q),
      .dest_in({cfg_data_width{1'b0}}),
      .data_out(cfg_read_data_num_packets));
   
   wire 			    inf_packets_loadval;
   assign inf_packets_loadval = &num_packets_loadval;
   
   wire 			    inf_packets_s;
   assign inf_packets_s
     = cfg_active_q ? 
       (write_num_packets ? inf_packets_loadval : inf_packets_q) : 
       inf_packets_q;
   c_dff
     #(.width(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   inf_packetsq
     (.clk(clk),
      .reset(reset),
      .d(inf_packets_s),
      .q(inf_packets_q));
   
   assign gen_packets = ~num_packets_zero | inf_packets_q;
   
   
   //---------------------------------------------------------------------------
   // generate packet arrival times
   //---------------------------------------------------------------------------
   
   wire [0:arrival_rv_width-1] 	    arrival_rv_feedback;
   c_fbgen
     #(.width(arrival_rv_width),
       .index(4*lfsr_index+0))
   arrival_rv_feedback_fbgen
     (.feedback(arrival_rv_feedback));
   
   wire [0:arrival_rv_width-1] 	    arrival_rv_loadval;
   c_align
     #(.data_width(cfg_data_width),
       .dest_width(arrival_rv_width))
   arrival_rv_loadval_alg
     (.data_in(cfg_data_q),
      .dest_in({arrival_rv_width{1'b0}}),
      .data_out(arrival_rv_loadval));
   
   wire 			    write_lfsr_seed;
   assign write_lfsr_seed = cfg_do_write & cfg_sel_lfsr_seed;
   
   wire 			    update_arrival_rv;
   assign update_arrival_rv = active_q & gen_packets;
   
   wire [0:arrival_rv_width-1] 	    arrival_rv_s, arrival_rv_q;
   assign arrival_rv_s
     = {arrival_rv_width{write_lfsr_seed}} & arrival_rv_loadval;
   c_lfsr
     #(.width(arrival_rv_width),
       .iterations(arrival_rv_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   arrival_rv_lfsr
     (.clk(clk),
      .reset(reset),
      .load(write_lfsr_seed),
      .run(update_arrival_rv),
      .feedback(arrival_rv_feedback),
      .complete(1'b1),
      .d(arrival_rv_s),
      .q(arrival_rv_q));
   
   wire [0:arrival_rv_width-1] 	    arrival_thresh_loadval;
   c_align
     #(.data_width(cfg_data_width),
       .dest_width(arrival_rv_width))
   arrival_thresh_loadval_alg
     (.data_in(cfg_data_q),
      .dest_in({arrival_rv_width{1'b0}}),
      .data_out(arrival_thresh_loadval));
   
   wire 			    write_arrival_thresh;
   assign write_arrival_thresh = cfg_do_write & cfg_sel_arrival_thresh;
   
   wire [0:arrival_rv_width-1] 	    arrival_thresh_s, arrival_thresh_q;
   assign arrival_thresh_s
     = cfg_active_q ? 
       (write_arrival_thresh ? arrival_thresh_loadval : arrival_thresh_q) : 
       arrival_thresh_q;
   c_dff
     #(.width(arrival_rv_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   arrival_threshq
     (.clk(clk),
      .reset(reset),
      .d(arrival_thresh_s),
      .q(arrival_thresh_q));
   
   assign new_packet_rv = (arrival_rv_q <= arrival_thresh_q);
   
   
   //---------------------------------------------------------------------------
   // shared LFSR for per-packet random values
   //---------------------------------------------------------------------------
   
   wire [0:packet_rvs_width-1] 	    packet_rvs_feedback;
   c_fbgen
     #(.width(packet_rvs_width),
       .index(4*lfsr_index+1))
   packet_rvs_feedback_fbgen
     (.feedback(packet_rvs_feedback));
   
   wire [0:packet_rvs_width-1] 	    packet_rvs_loadval;
   c_align
     #(.data_width(cfg_data_width),
       .dest_width(packet_rvs_width))
   packet_rvs_loadval_alg
     (.data_in(cfg_data_q),
      .dest_in({packet_rvs_width{1'b0}}),
      .data_out(packet_rvs_loadval));
   
   wire 			    packet_sent;
   
   wire 			    update_packet_rvs;
   assign update_packet_rvs = active_q & packet_sent;
   
   wire [0:packet_rvs_width-1] 	    packet_rvs_s, packet_rvs_q;
   assign packet_rvs_s
     = {packet_rvs_width{write_lfsr_seed}} & packet_rvs_loadval;
   c_lfsr
     #(.width(packet_rvs_width),
       .iterations(packet_rvs_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   packet_rvs_lfsr
     (.clk(clk),
      .reset(reset),
      .load(write_lfsr_seed),
      .run(update_packet_rvs),
      .feedback(packet_rvs_feedback),
      .complete(1'b1),
      .d(packet_rvs_s),
      .q(packet_rvs_q));
   
   
   //---------------------------------------------------------------------------
   // determine random message and resource class
   //---------------------------------------------------------------------------
   
   wire [0:num_message_classes-1]   sel_mc_rv;
   wire [0:num_resource_classes-1]  sel_rc_rv;
   
   wire [0:num_packet_classes-1]    sel_opc_rv;
   c_mat_mult
     #(.dim1_width(num_message_classes),
       .dim2_width(1),
       .dim3_width(num_resource_classes))
   sel_opc_rv_mmult
     (.input_a(sel_mc_rv),
      .input_b(sel_rc_rv),
      .result(sel_opc_rv));
   
   wire 			    vc_alloc_q;
   wire [0:num_vcs_per_class-1]     vc_alloc_ocvc_q;
   wire [0:num_vcs_per_class-1]     next_elig_ocvc;
   
   wire [0:num_vcs_per_class-1]     sel_ocvc;
   assign sel_ocvc = vc_alloc_q ? vc_alloc_ocvc_q : next_elig_ocvc;
   
   wire [0:num_vcs-1] 		    sel_ovc;
   c_mat_mult
     #(.dim1_width(num_packet_classes),
       .dim2_width(1),
       .dim3_width(num_vcs_per_class))
   sel_ovc_mmult
     (.input_a(sel_opc_rv),
      .input_b(sel_ocvc),
      .result(sel_ovc));
   
   wire [0:num_vcs-1] 		    elig_ovc;
   wire [0:num_packet_classes-1]    elig_opc;
   wire [0:num_resource_classes-1]  elig_orc;
   wire 			    elig;
   
   wire [0:num_vcs-1] 		    next_elig_ovc;
   wire [0:num_resource_classes*num_vcs_per_class-1] next_elig_orc_ocvc;
   
   wire [0:num_vcs-1] 				     free_ovc;
   wire [0:num_resource_classes*num_vcs_per_class-1] free_orc_ocvc;
   wire [0:num_vcs_per_class-1] 		     free_ocvc;
   wire 					     free;
   
   generate
      
      if(num_message_classes > 1)
	begin
	   
	   // synopsys translate_off
	   if(mc_threshs_width > cfg_data_width)
	     begin
		initial
		begin
		   $display({"ERROR: The value of the cfg_data_width ", 
			     "parameter is too small to accomodate the ", 
			     "specified number of message class selection ", 
			     "thresholds."});
		   $stop;
		end
	     end
	   // synopsys translate_on
	   
	   wire [0:mc_threshs_width-1] mc_threshs_loadval;
	   c_align
	     #(.data_width(cfg_data_width),
	       .dest_width(mc_threshs_width))
	   mc_threshs_loadval_alg
	     (.data_in(cfg_data_q),
	      .dest_in({mc_threshs_width{1'b0}}),
	      .data_out(mc_threshs_loadval));
	   
	   wire write_mc_threshs;
	   assign write_mc_threshs = cfg_do_write & cfg_sel_mc_threshs;
	   
	   wire [0:mc_threshs_width-1] mc_threshs_s, mc_threshs_q;
	   assign mc_threshs_s = cfg_active_q ? 
				 (write_mc_threshs ? 
				  mc_threshs_loadval :
				  mc_threshs_q) : 
				 mc_threshs_q;
	   c_dff
	     #(.width(mc_threshs_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   mc_threshsq
	     (.clk(clk),
	      .reset(reset),
	      .d(mc_threshs_s),
	      .q(mc_threshs_q));
	   
	   wire [0:mc_idx_rv_width-1] mc_idx_rv;
	   assign mc_idx_rv = packet_rvs_q[0:mc_idx_rv_width-1];
	   
	   wire [0:num_message_classes-1] sel_mc_rv_unmasked;
	   
	   genvar 			  mc;
	   
	   for(mc = 0; mc < (num_message_classes - 1); mc = mc + 1)
	     begin:mcs
		
		assign sel_mc_rv_unmasked[mc]
			 = (mc_idx_rv <
			    mc_threshs_q[mc*mc_idx_rv_width:
					 (mc+1)*mc_idx_rv_width-1]);
		
	     end
	   
	   assign sel_mc_rv_unmasked[num_message_classes-1] = 1'b1;
	   
	   c_fp_arbiter
	     #(.num_ports(num_message_classes))
	   sel_mc_rv_arb
	     (.req(sel_mc_rv_unmasked),
	      .gnt(sel_mc_rv));
	   
	   c_select_1ofn
	     #(.num_ports(num_message_classes),
	       .width(num_resource_classes))
	   elig_orc_sel
	     (.select(sel_mc_rv),
	      .data_in(elig_opc),
	      .data_out(elig_orc));
	   
	   c_select_1ofn
	     #(.num_ports(num_message_classes),
	       .width(num_resource_classes*num_vcs_per_class))
	   next_elig_orc_ocvc_sel
	     (.select(sel_mc_rv),
	      .data_in(next_elig_ovc),
	      .data_out(next_elig_orc_ocvc));
	   
	   c_select_1ofn
	     #(.num_ports(num_message_classes),
	       .width(num_resource_classes*num_vcs_per_class))
	   free_orc_ocvc_sel
	     (.select(sel_mc_rv),
	      .data_in(free_ovc),
	      .data_out(free_orc_ocvc));
	   
	end
      else
	begin
	   assign sel_mc_rv = 1'b1;
	   assign elig_orc = elig_opc;
	   assign next_elig_orc_ocvc = next_elig_ovc;
	   assign free_orc_ocvc = free_ovc;
	end
      
      if(num_resource_classes > 1)
	begin
	   
	   // synopsys translate_off
	   if(rc_threshs_width > cfg_data_width)
	     begin
		initial
		begin
		   $display({"ERROR: The value of the cfg_data_width ", 
			     "parameter is too small to accomodate the ", 
			     "specified number of resource class selection ", 
			     "thresholds."});
		   $stop;
		end
	     end
	   // synopsys translate_on
	   
	   wire [0:rc_threshs_width-1] rc_threshs_loadval;
	   c_align
	     #(.data_width(cfg_data_width),
	       .dest_width(rc_threshs_width))
	   rc_threshs_loadval_alg
	     (.data_in(cfg_data_q),
	      .dest_in({rc_threshs_width{1'b0}}),
	      .data_out(rc_threshs_loadval));
	   
	   wire write_rc_threshs;
	   assign write_rc_threshs = cfg_do_write & cfg_sel_rc_threshs;
	   
	   wire [0:rc_threshs_width-1] rc_threshs_s, rc_threshs_q;
	   assign rc_threshs_s = cfg_active_q ? 
				 (write_rc_threshs ? 
				  rc_threshs_loadval :
				  rc_threshs_q) : 
				 rc_threshs_q;
	   c_dff
	     #(.width(rc_threshs_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   rc_threshsq
	     (.clk(clk),
	      .reset(reset),
	      .d(rc_threshs_s),
	      .q(rc_threshs_q));
	   
	   wire [0:rc_idx_rv_width-1] rc_idx_rv;
	   assign rc_idx_rv
	     = packet_rvs_q[mc_idx_rv_width:
			    (mc_idx_rv_width+rc_idx_rv_width)-1];
	   
	   wire [0:num_resource_classes-1] sel_rc_rv_unmasked;
	   
	   genvar 			   rc;
	   
	   for(rc = 0; rc < (num_resource_classes - 1); rc = rc + 1)
	     begin:rcs
		
		assign sel_rc_rv_unmasked[rc]
			 = (rc_idx_rv <
			    rc_threshs_q[rc*rc_idx_rv_width:
					 (rc+1)*rc_idx_rv_width-1]);
		
	     end
	   
	   assign sel_rc_rv_unmasked[num_resource_classes-1] = 1'b1;
	   
	   c_fp_arbiter
	     #(.num_ports(num_resource_classes))
	   sel_rc_rv_arb
	     (.req(sel_rc_rv_unmasked),
	      .gnt(sel_rc_rv));
	   
	   c_select_1ofn
	     #(.num_ports(num_resource_classes),
	       .width(1))
	   elig_sel
	     (.select(sel_rc_rv),
	      .data_in(elig_orc),
	      .data_out(elig));
	   
	   c_select_1ofn
	     #(.num_ports(num_resource_classes),
	       .width(num_vcs_per_class))
	   next_elig_ocvc_sel
	     (.select(sel_rc_rv),
	      .data_in(next_elig_orc_ocvc),
	      .data_out(next_elig_ocvc));
	   
	   c_select_1ofn
	     #(.num_ports(num_resource_classes),
	       .width(num_vcs_per_class))
	   free_ocvc_sel
	     (.select(sel_rc_rv),
	      .data_in(free_orc_ocvc),
	      .data_out(free_ocvc));
	   
	end
      else
	begin
	   assign sel_rc_rv = 1'b1;
	   assign elig = elig_orc;
	   assign next_elig_ocvc = next_elig_orc_ocvc;
	   assign free_ocvc = free_orc_ocvc;
	end
      
      if(num_vcs_per_class > 1)
	begin
	   
	   c_select_1ofn
	     #(.width(1),
	       .num_ports(num_vcs_per_class))
	   free_sel
	     (.select(sel_ocvc),
	      .data_in(free_ocvc),
	      .data_out(free));
	   
	   genvar opc;
	   
	   for(opc = 0; opc < num_packet_classes; opc = opc + 1)
	     begin:opcs
		
		wire [0:num_vcs_per_class-1] elig_ocvc;
		assign elig_ocvc = elig_ovc[opc*num_vcs_per_class:
					    (opc+1)*num_vcs_per_class-1];
		
		assign elig_opc[opc] = |elig_ocvc;
		
		wire [0:num_vcs_per_class-1] req_ocvc;
		assign req_ocvc = elig_ocvc;
		
		wire [0:num_vcs_per_class-1] gnt_ocvc;
		c_fp_arbiter
		  #(.num_ports(num_vcs_per_class))
		gnt_ocvc_arb
		  (.req(req_ocvc),
		   .gnt(gnt_ocvc));
		
		wire [0:num_vcs_per_class-1] next_elig_ocvc;
		assign next_elig_ocvc = gnt_ocvc;
		
		assign next_elig_ovc[opc*num_vcs_per_class:
				     (opc+1)*num_vcs_per_class-1]
			 = next_elig_ocvc;
		
	     end
	   
	end
      else
	begin
	   assign elig_opc = elig_ovc;
	   assign next_elig_ovc = elig_ovc;
	   assign free = free_ocvc;
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // input staging for flow control signals
   //---------------------------------------------------------------------------
   
   wire [0:flow_ctrl_width-1] flow_ctrl_in_s, flow_ctrl_in_q;
   assign flow_ctrl_in_s = flow_ctrl_muxed;
   
   wire 		      cred_valid_in_s, cred_valid_in_q;
   assign cred_valid_in_s = flow_ctrl_in_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_valid_inq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_in_s),
      .q(cred_valid_in_q));
   
   assign flow_ctrl_in_q[0] = cred_valid_in_q;
   
   generate
      
      if(flow_ctrl_width > 1)
	begin
	   
	   c_dff
	     #(.width(flow_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flow_ctrl_inq
	     (.clk(clk),
	      .reset(reset),
	      .d(flow_ctrl_in_s[1:flow_ctrl_width-1]),
	      .q(flow_ctrl_in_q[1:flow_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // VC state tracking
   //---------------------------------------------------------------------------
   
   wire packet_to_self;
   wire [0:int_flit_ctrl_width-1] int_flit_ctrl;
   
   wire [0:num_vcs*4-1] 	  ovcc_errors_ovc;
   
   genvar 			  ovc;
   
   generate
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire next_elig;
	   assign next_elig = next_elig_ovc[ovc];
	   
	   wire sel;
	   assign sel = sel_opc_rv[ovc / num_vcs_per_class];
	   
	   wire vc_gnt;
	   assign vc_gnt
	     = packet_valid_q & ~packet_to_self & ~vc_alloc_q & sel & next_elig;
	   
	   wire match;
	   wire elig;
	   wire empty;
	   wire [0:1] int_flow_ctrl;
	   wire [0:3] ovcc_errors;
	   
	   vcr_ovc_ctrl
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
	       .vc_id(ovc),
	       .track_vcs_at_output(0),
	       .int_flow_ctrl_type(`INT_FLOW_CTRL_TYPE_LEVEL),
	       .cred_level_width(2),
	       .reset_type(reset_type))
	   ovcc
	     (.clk(clk),
	      .reset(reset),
	      .flow_ctrl(flow_ctrl_in_q),
	      .vc_gnt(vc_gnt),
	      .vc_gnt_ip({num_ports{1'b0}}),
	      .vc_gnt_ivc({num_vcs{1'b0}}),
	      .sw_gnt(1'b1),
	      .sw_gnt_ip({num_ports{1'b0}}),
	      .int_flit_ctrl(int_flit_ctrl),
	      .match(match),
	      .elig(elig),
	      .empty(empty),
	      .int_flow_ctrl(int_flow_ctrl),
	      .errors(ovcc_errors));
	   
	   wire free;
	   assign free = int_flit_ctrl[0] ? int_flow_ctrl[0] : int_flow_ctrl[1];
	   
	   assign elig_ovc[ovc] = elig;
	   assign empty_ovc[ovc] = empty;
	   assign free_ovc[ovc] = free;
	   assign ovcc_errors_ovc[ovc*4:(ovc+1)*4-1] = ovcc_errors;
	   
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
		    = packet_rvs_q[mc_idx_rv_width+rc_idx_rv_width+
				   (num_resource_classes-1)*router_addr_width+
				   dim*dim_addr_width:
				   mc_idx_rv_width+rc_idx_rv_width+
				   (num_resource_classes-1)*router_addr_width+
				   (dim+1)*dim_addr_width-1] % 
		      num_routers_per_dim;
	   
	end
      
      if(num_nodes_per_router > 1)
	   assign dest_addr_rv[router_addr_width:addr_width-1]
		    = packet_rvs_q[mc_idx_rv_width+rc_idx_rv_width+
				   num_resource_classes*router_addr_width:
				   mc_idx_rv_width+rc_idx_rv_width+
				   num_resource_classes*router_addr_width+
				   node_addr_width-1] % 
		      num_nodes_per_router;
      
      
      //------------------------------------------------------------------------
      // generate random intermediate addresses
      //------------------------------------------------------------------------
      
      if(num_resource_classes > 1)
	begin:intm_addr_gen
	   
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
			      = packet_rvs_q[mc_idx_rv_width+rc_idx_rv_width+
					     rc*router_addr_width+
					     dim*dim_addr_width:
					     mc_idx_rv_width+rc_idx_rv_width+
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
   
   assign packet_to_self = (route_port_rv == port_id) && !inc_rc_rv;
   
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
	   
	   // synopsys translate_off
	   if(plength_threshs_width > cfg_data_width)
	     begin
		initial
		begin
		   $display({"ERROR: The value of the cfg_data_width ", 
			     "parameter is too small to accomodate the ", 
			     "specified number of packet length selection ", 
			     "thresholds."});
		   $stop;
		end
	     end
	   if(plength_vals_width > cfg_data_width)
	     begin
		initial
		begin
		   $display({"ERROR: The value of the cfg_data_width ", 
			     "parameter is too small to accomodate the ", 
			     "specified number of packet length values."});
		   $stop;
		end
	     end
	   // synopsys translate_on

	   wire [0:plength_vals_width-1] plength_vals_loadval;
	   c_align
	     #(.data_width(cfg_data_width),
	       .dest_width(plength_vals_width))
	   plength_vals_loadval_alg
	     (.data_in(cfg_data_q),
	      .dest_in({(plength_vals_width){1'b0}}),
	      .data_out(plength_vals_loadval));
	   
	   wire 			   write_plength_vals;
	   assign write_plength_vals = cfg_do_write & cfg_sel_plength_vals;
	   
	   wire [0:plength_vals_width-1] plength_vals_s, plength_vals_q;
	   assign plength_vals_s
	     = cfg_active_q ? 
	       (write_plength_vals ? plength_vals_loadval : plength_vals_q) : 
	       plength_vals_q;
	   c_dff
	     #(.width(plength_vals_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   plength_valsq
	     (.clk(clk),
	      .reset(reset),
	      .d(plength_vals_s),
	      .q(plength_vals_q));
	   
	   wire [0:payload_length_width-1] plength_rv;
	   
	   if(num_plength_vals > 1)
	     begin
		
		wire [0:plength_threshs_width-1] plength_threshs_loadval;
		c_align
		  #(.data_width(cfg_data_width),
		    .dest_width(plength_threshs_width))
		plength_threshs_loadval_alg
		  (.data_in(cfg_data_q),
		   .dest_in({plength_threshs_width{1'b0}}),
		   .data_out(plength_threshs_loadval));
		
		wire write_plength_threshs;
		assign write_plength_threshs
		  = cfg_do_write & cfg_sel_plength_threshs;
		
		wire [0:plength_threshs_width-1] plength_threshs_s, 
						 plength_threshs_q;
		assign plength_threshs_s = cfg_active_q ? 
					   (write_plength_threshs ? 
					    plength_threshs_loadval :
					    plength_threshs_q) : 
					   plength_threshs_q;
		c_dff
		  #(.width(plength_threshs_width),
		    .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
		plength_threshsq
		  (.clk(clk),
		   .reset(reset),
		   .d(plength_threshs_s),
		   .q(plength_threshs_q));
		
		wire [0:plength_idx_rv_width-1]  plength_idx_rv;
		assign plength_idx_rv
		  = packet_rvs_q[mc_idx_rv_width+rc_idx_rv_width+
				 route_info_width:
				 mc_idx_rv_width+rc_idx_rv_width+
				 route_info_width+plength_idx_rv_width-1];
		
		wire [0:num_plength_vals-1] plength_select_unmasked;
		
		genvar 				 val;
		
		for(val = 0; val < (num_plength_vals - 1); val = val + 1)
		  begin:vals
		     
		     assign plength_select_unmasked[val]
			      = (plength_idx_rv <
				 plength_threshs_q[val*
						   plength_idx_rv_width:
						   (val+1)*
						   plength_idx_rv_width-1]);
		     
		  end
		
		assign plength_select_unmasked[num_plength_vals-1] = 1'b1;
		
		wire [0:num_plength_vals-1] 	 plength_select;
		c_fp_arbiter
		  #(.num_ports(num_plength_vals))
		plength_select_arb
		  (.req(plength_select_unmasked),
		   .gnt(plength_select));
		
		c_select_1ofn
		  #(.num_ports(num_plength_vals),
		    .width(payload_length_width))
		plength_rv_sel
		  (.select(plength_select),
		   .data_in(plength_vals_q),
		   .data_out(plength_rv));
		
	     end
	   else
	     assign plength_rv = plength_vals_q;
	   
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
   
   wire 				   add_packet;
   assign add_packet = gen_packets & new_packet_rv;
   
   wire 				   packet_count_zero_b;
   
   wire 				   packet_count_decr;
   assign packet_count_decr
     = (~packet_valid_q | packet_sent) & (packet_count_zero_b | add_packet);
   
   wire 				   packet_count_max_b;
   
   wire 				   packet_count_incr;
   assign packet_count_incr
     = (packet_count_max_b | ~packet_valid_q | packet_sent) & add_packet;
   
   wire [0:packet_count_width-1] 	   packet_count_s, packet_count_q;
   assign packet_count_s
     = active_q ?
       ({packet_count_width{~start_q}} &
	(packet_count_q + packet_count_incr - packet_count_decr)) : 
       packet_count_q;
   c_dff
     #(.width(packet_count_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
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
     = active_q ? 
       (((packet_valid_q  & ~packet_sent) | packet_count_zero_b | add_packet) & 
	~start_q) : 
       packet_valid_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   packet_validq
     (.clk(clk),
      .reset(reset),
      .d(packet_valid_s),
      .q(packet_valid_q));
   
   wire 				   flit_sent;
   assign flit_sent
     = packet_valid_q & (vc_alloc_q ? free : elig) & ~packet_to_self;
   
   wire 				   flit_sent_s, flit_sent_q;
   assign flit_sent_s = active_q ? flit_sent : flit_sent_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   flit_sentq
     (.clk(clk),
      .reset(reset),
      .d(flit_sent_s),
      .q(flit_sent_q));
   
   assign flit_ctrl_out[0] = flit_sent_q;
   assign int_flit_ctrl[0] = flit_sent_q;
   
   wire [0:packet_length_width-1] 	   flit_count;
   
   wire [0:packet_length_width-1] 	   flit_count_s, flit_count_q;
   assign flit_count_s = active_q ? (flit_count - flit_sent) : flit_count_q;
   c_dff
     #(.width(packet_length_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_countq
     (.clk(clk),
      .reset(reset),
      .d(flit_count_s),
      .q(flit_count_q));
   
   wire 				   flit_head;
   
   assign flit_count = flit_head ? flit_count_rv : flit_count_q;
   
   wire 				   flit_count_zero;
   assign flit_count_zero = ~|flit_count;
   
   assign packet_sent
     = (flit_sent & flit_count_zero) | (packet_valid_q & packet_to_self);
   
   wire 				   flit_tail;
   assign flit_tail = flit_count_zero;
   
   wire 				   flit_tail_s, flit_tail_q;
   assign flit_tail_s = active_q ? flit_tail : flit_tail_q;
   c_dff
     #(.width(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_tailq
     (.clk(clk),
      .reset(reset),
      .d(flit_tail_s),
      .q(flit_tail_q));
      
   wire 				   vc_alloc_s;
   assign vc_alloc_s
     = active_q ? 
       ((vc_alloc_q | (packet_valid_q & elig)) & ~start_q & ~packet_sent) : 
       vc_alloc_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocq
     (.clk(clk),
      .reset(reset),
      .d(vc_alloc_s),
      .q(vc_alloc_q));
   
   generate
      
      if(num_vcs_per_class > 1)
	begin
	   
	   wire [0:num_vcs_per_class-1] 	   vc_alloc_ocvc_s;
	   assign vc_alloc_ocvc_s
	     = active_q ? 
	       (vc_alloc_q ? vc_alloc_ocvc_q : next_elig_ocvc) : 
	       vc_alloc_ocvc_q;
	   c_dff
	     #(.width(num_vcs_per_class),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   vc_alloc_ocvcq
	     (.clk(clk),
	      .reset(reset),
	      .d(vc_alloc_ocvc_s),
	      .q(vc_alloc_ocvc_q));
	   
	end
      else
	assign vc_alloc_ocvc_q = 1'b1;
      
   endgenerate
   
   wire 				   flit_head_q;
      
   generate
      
      if(max_payload_length > 0)
	begin
	   
	   wire flit_head_gen_s, flit_head_gen_q;
	   assign flit_head_gen_s
	     = active_q ? 
	       ((flit_head_gen_q & ~flit_sent) | start_q | packet_sent) : 
	       flit_head_gen_q;
	   c_dff
	     #(.width(1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flit_head_genq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_head_gen_s),
	      .q(flit_head_gen_q));
	   
	   assign flit_head = flit_head_gen_q;
	   
	   wire flit_head_s;
	   assign flit_head_s = active_q ? flit_head : flit_head_q;
	   c_dff
	     #(.width(1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flit_headq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_head_s),
	      .q(flit_head_q));
	   
	end
      else
	begin
	   assign flit_head = 1'b1;
	   assign flit_head_q = 1'b1;
	end
      
      if(num_vcs > 1)
	begin
	   
	   wire [0:vc_idx_width-1] flit_vc;
	   c_encoder
	     #(.num_ports(num_vcs))
	   flit_vc_enc
	     (.data_in(sel_ovc),
	      .data_out(flit_vc));
	   
	   wire [0:vc_idx_width-1] flit_vc_s, flit_vc_q;
	   assign flit_vc_s = active_q ? flit_vc : flit_vc_q;
	   c_dff
	     #(.width(vc_idx_width),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flit_vcq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_vc_s),
	      .q(flit_vc_q));
	   	   
	   assign flit_ctrl_out[1:1+vc_idx_width-1] = flit_vc_q;
	   assign int_flit_ctrl[1:1+vc_idx_width-1] = flit_vc_q;
	   
	end
      
      if(packet_format == `PACKET_FORMAT_HEAD_TAIL)
	assign flit_ctrl_out[1+vc_idx_width+1] = flit_tail_q;
      
   endgenerate
   
   assign flit_ctrl_out[1+vc_idx_width+0] = flit_head_q;
   assign int_flit_ctrl[1+vc_idx_width+0] = flit_head_q;
   assign int_flit_ctrl[1+vc_idx_width+1] = flit_tail_q;
   
   
   //---------------------------------------------------------------------------
   // generate pseudo-random payload data
   //---------------------------------------------------------------------------
   
   wire [0:flit_data_width-1] 	   flit_data_rv_feedback;
   c_fbgen
     #(.width(flit_data_width),
       .index(4*lfsr_index+2))
   flit_data_rv_feedback_fbgen
     (.feedback(flit_data_rv_feedback));
   
   wire [0:flit_data_width-1] 	   flit_data_rv_loadval;
   c_align
     #(.data_width(cfg_data_width),
       .dest_width(flit_data_width))
   flit_data_rv_loadval_alg
     (.data_in(cfg_data_q),
      .dest_in({flit_data_width{1'b0}}),
      .data_out(flit_data_rv_loadval));
   
   wire 			   update_flit_data_rv;
   assign update_flit_data_rv = active_q & flit_sent_q;
   
   wire [0:flit_data_width-1] 	   flit_data_rv_s, flit_data_rv_q;
   assign flit_data_rv_s
     = {flit_data_width{write_lfsr_seed}} & flit_data_rv_loadval;
   c_lfsr
     #(.width(flit_data_width),
       .iterations(flit_data_width),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_data_rv_lfsr
     (.clk(clk),
      .reset(reset),
      .load(write_lfsr_seed),
      .run(update_flit_data_rv),
      .feedback(flit_data_rv_feedback),
      .complete(1'b1),
      .d(flit_data_rv_s),
      .q(flit_data_rv_q));
   
   // line up header info with flit data
   wire [0:header_info_width-1]    header_info_rv_s, header_info_rv_q;
   assign header_info_rv_s = active_q ? header_info_rv : header_info_rv_q;
   c_dff
     #(.width(header_info_width),
       .reset_type(`RESET_TYPE_NONE /*reset_type*/))
   header_info_rvq
     (.clk(clk),
      .reset(reset),
      .d(header_info_rv_s),
      .q(header_info_rv_q));
   
   assign flit_data_out[0:header_info_width-1]
	    = flit_head_q ? 
	      header_info_rv_q : 
	      flit_data_rv_q[0:header_info_width-1];
   assign flit_data_out[header_info_width:flit_data_width-1]
	    = flit_data_rv_q[header_info_width:flit_data_width-1];
   
   
   //---------------------------------------------------------------------------
   // flit signature register
   // =======================
   // This is a MISR that computes a signature over all flit data received
   // during the experiment.
   //---------------------------------------------------------------------------
   
   wire [0:flit_data_width-1] 	   flit_sig_feedback;
   c_fbgen
     #(.width(flit_data_width),
       .index(4*lfsr_index+3))
   flit_sig_feedback_fbgen
     (.feedback(flit_sig_feedback));
   
   wire [0:flit_data_width-1] 	   flit_sig_loadval;
   assign flit_sig_loadval = {{(flit_data_width-1){1'b0}}, 1'b1};
   
   wire 			   update_flit_sig;
   assign update_flit_sig = active_q & flit_ctrl_muxed[0];
   
   wire [0:flit_data_width-1] 	   flit_sig_s, flit_sig_q;
   assign flit_sig_s = start_q ? flit_sig_loadval : flit_data_muxed;
   c_lfsr
     #(.width(flit_data_width),
       .iterations(1),
       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
   flit_sig_lfsr
     (.clk(clk),
      .reset(reset),
      .load(start_q),
      .run(update_flit_sig),
      .feedback(flit_sig_feedback),
      .complete(1'b0),
      .d(flit_sig_s),
      .q(flit_sig_q));

   // expand the signature to a multiple of cfg_data_width, ...
   wire [0:flit_sig_exp_width-1]   flit_sig_expanded;
   c_align
     #(.data_width(flit_data_width),
       .dest_width(flit_sig_exp_width))
   flit_sig_cfg_alg
     (.data_in(flit_sig_q),
      .dest_in({flit_sig_exp_width{1'b0}}),
      .data_out(flit_sig_expanded));
   
   // ... and reduce it down to a single signature of width cfg_data_width
   c_xor_nto1
     #(.num_ports(flit_sig_exp_width / cfg_data_width),
       .width(cfg_data_width))
   cfg_read_data_flit_sig_xor
     (.data_in(flit_sig_expanded),
      .data_out(cfg_read_data_flit_sig));
   
   
   //---------------------------------------------------------------------------
   // credit return path
   //---------------------------------------------------------------------------
   
   wire [0:flow_ctrl_width-1] 	   flow_ctrl_out_s, flow_ctrl_out_q;
   assign flow_ctrl_out_s = flit_ctrl_muxed[0:flow_ctrl_width-1];
   
   wire 			   cred_valid_out_s, cred_valid_out_q;
   assign cred_valid_out_s = flow_ctrl_out_s[0];
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   cred_valid_outq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_out_s),
      .q(cred_valid_out_q));
   
   assign flow_ctrl_out_q[0] = cred_valid_out_q;
   
   generate
      
      if(flow_ctrl_width > 1)
	begin
	   
	   c_dff
	     #(.width(flow_ctrl_width-1),
	       .reset_type(/*reset_type*/ `RESET_TYPE_NONE))
	   flow_ctrl_outq
	     (.clk(clk),
	      .reset(reset),
	      .d(flow_ctrl_out_s[1:flow_ctrl_width-1]),
	      .q(flow_ctrl_out_q[1:flow_ctrl_width-1]));
	   
	end
      
   endgenerate
   
   assign flow_ctrl_out = flow_ctrl_out_q;
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   generate
      
      if(error_capture_mode != `ERROR_CAPTURE_MODE_NONE)
	begin
	   
	   // synopsys translate_off
	   
	   integer i;
	   
	   always @(posedge clk)
	     begin
		
		for(i = 0; i < num_vcs; i = i + 1)
		  begin
		     
		     if(ovcc_errors_ovc[i*4])
		       $display({"ERROR: Credit tracker underflow at ", 
				 "output port %d, VC %d."}, port_id, i);
		     
		     if(ovcc_errors_ovc[i*4+1])
		       $display({"ERROR: Credit tracker overflow at ", 
				 "output port %d, VC %d."}, port_id, i);
		     
		     if(ovcc_errors_ovc[i*4+2])
		       $display({"ERROR: Head credit tracker underflow at ", 
				 "output port %d, VC %d."}, port_id, i);
		     
		     if(ovcc_errors_ovc[i*4+3])
		       $display({"ERROR: Head credit tracker overflow at ", 
				 "output port %d, VC %d."}, port_id, i);
		     
		  end
		
	     end
	   // synopsys translate_on
	   
	   wire [0:num_vcs*4-1] errors_s, errors_q;
	   assign errors_s = ovcc_errors_ovc;
	   c_err_rpt
	     #(.num_errors(num_vcs*4),
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
