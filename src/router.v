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

// top-level module for router
module router
  (clk, reset, router_address, flit_valid_in_ip, flit_vc_in_ip, flit_head_in_ip,
   flit_tail_in_ip, flit_data_in_ip, cred_valid_out_ip, cred_vc_out_ip,
   flit_valid_out_op, flit_vc_out_op, flit_head_out_op, flit_tail_out_op,
   flit_data_out_op, cred_valid_in_op, cred_vc_in_op, error);
   
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
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // flit width
   parameter data_width = 64;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (credit_handling_type == `CREDIT_HANDLING_TYPE_LEVEL) ?
       2 :
       (credit_handling_type == `CREDIT_HANDLING_TYPE_PUSH) ?
       1 :
       -1;
   
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
   
   localparam sw_spec_enable = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // width of each crossbar port for control crossbar
   localparam xbc_width = 1 + 2 + vc_idx_width;
   
   // width of each crossbar port for data crossbar
   localparam xbd_width = data_width;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // valid flit data available at input port(s)
   input [0:num_ports-1] flit_valid_in_ip;
   
   // which VC(s) is/are incoming flit(s) travelling on
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports*vc_idx_width-1] flit_vc_in_ip;
   
   // incoming flit(s) is/are head(s)
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports-1] flit_head_in_ip;
   
   // incoming flit(s) is/are tail(s)
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports-1] flit_tail_in_ip;
   
   // flit data for each incoming flit
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports*data_width-1] flit_data_in_ip;
   
   // outgoing credit(s) valid
   output [0:num_ports-1] cred_valid_out_ip;
   wire [0:num_ports-1] cred_valid_out_ip;
   
   // VC indicators for outgoing credit(s)
   // (note: only valid when corresponding bit in cred_valid_out_ip is high)
   output [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   wire [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   // valid flit data available at output port(s)
   output [0:num_ports-1] flit_valid_out_op;
   wire [0:num_ports-1] 	     flit_valid_out_op;
   
   // which VC(s) is/are outgoing flit(s) travelling on
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   wire [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   
   // outgoing flit(s) is/are head(s)
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports-1] flit_head_out_op;
   wire [0:num_ports-1] 	     flit_head_out_op;
   
   // outgoing flit(s) is/are tail(s)
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports-1] flit_tail_out_op;
   wire [0:num_ports-1] 	     flit_tail_out_op;
   
   // flit data for each outgoing flit
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports*data_width-1] flit_data_out_op;
   wire [0:num_ports*data_width-1]   flit_data_out_op;
   
   // incoming credit(s) available
   input [0:num_ports-1] cred_valid_in_op;
   
   // VC indicators for incoming flit(s)
   // (note: only valid when corresponding bit in cred_valid_in_op is high)
   input [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   // internal error condition detected
   output error;
   wire 			     error;
   
   
   //---------------------------------------------------------------------------
   // input ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1]      elig_op_ovc;
   wire [0:num_ports*num_vcs*int_flow_ctrl_width-1] flow_ctrl_op_ovc;
   
   wire [0:num_ports*num_vcs*num_ports-1] 	    route_ip_ivc_op;

   wire [0:num_ports*num_vcs-1] 		    vc_req_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	    vc_req_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	    vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs-1] 		    sw_req_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_req_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_spec_ip_ivc;
   wire [0:num_ports*num_ports-1] 		    sw_gnt_ip_op;
   
   wire [0:num_ports*xbc_width-1] 		    xbc_data_in_ip;
   wire [0:num_ports*xbd_width-1] 		    xbd_data_in_ip;
   
   wire [0:num_ports-1] 			    ipc_error_ip;
   
   generate
      
      genvar 					    ip;
      
      for (ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   
	   //-------------------------------------------------------------------
	   // input controller
	   //-------------------------------------------------------------------
	   
	   wire flit_valid_in;
	   assign flit_valid_in = flit_valid_in_ip[ip];
	   
	   wire [0:vc_idx_width-1] flit_vc_in;
	   assign flit_vc_in = flit_vc_in_ip[ip*vc_idx_width:
					     (ip+1)*vc_idx_width-1];
	   
	   wire 		   flit_head_in;
	   assign flit_head_in = flit_head_in_ip[ip];
	   
	   wire 		   flit_tail_in;
	   assign flit_tail_in = flit_tail_in_ip[ip];
	   
	   wire [0:data_width-1]   flit_data_in;
	   assign flit_data_in = flit_data_in_ip[ip*data_width:
						 (ip+1)*data_width-1];
	   
	   wire [0:num_vcs-1] 	   vc_gnt_ivc;
	   assign vc_gnt_ivc = vc_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
	   assign vc_gnt_ivc_ovc = vc_gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:
						     (ip+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_nonspec_ivc;
	   assign sw_gnt_nonspec_ivc
	     = sw_gnt_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_spec_ivc;
	   assign sw_gnt_spec_ivc
	     = sw_gnt_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   wire [0:num_vcs-1] 		vc_req_ivc;
	   wire [0:num_vcs*num_vcs-1] 	vc_req_ivc_ovc;
	   wire [0:num_vcs-1] 		sw_req_nonspec_ivc;
	   wire [0:num_vcs-1] 		sw_req_spec_ivc;
	   wire 			flit_valid_out;
	   wire [0:vc_idx_width-1] 	flit_vc_out;
	   wire 			flit_head_out;
	   wire 			flit_tail_out;
	   wire [0:data_width-1] 	flit_data_out;
	   wire 			cred_valid_out;
	   wire [0:vc_idx_width-1] 	cred_vc_out;
	   wire 			ipc_error;
	   ip_ctrl
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_ports(num_ports),
	       .num_dimensions(num_dimensions),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .data_width(data_width),
	       .track_vcs_at_output(track_vcs_at_output),
	       .routing_function_type(routing_function_type),
	       .dimension_order(dimension_order),
	       .credit_handling_type(credit_handling_type),
	       .header_fifo_type(header_fifo_type),
	       .fbf_regfile_type(fbf_regfile_type),
	       .sw_spec_enable(sw_spec_enable),
	       .perf_ctr_enable(perf_ctr_enable),
	       .perf_ctr_width(perf_ctr_width),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .port_id(ip),
	       .reset_type(reset_type))
	   ipc
	     (.clk(clk),
	      .reset(reset),
	      .router_address(router_address),
	      .flit_valid_in(flit_valid_in),
	      .flit_vc_in(flit_vc_in),
	      .flit_head_in(flit_head_in),
	      .flit_tail_in(flit_tail_in),
	      .flit_data_in(flit_data_in),
	      .flow_ctrl_op_ovc(flow_ctrl_op_ovc),
	      .route_ivc_op(route_ivc_op),
	      .vc_req_ivc(vc_req_ivc),
	      .vc_req_ivc_ovc(vc_req_ivc_ovc),
	      .vc_gnt_ivc(vc_gnt_ivc),
	      .vc_gnt_ivc_ovc(vc_gnt_ivc_ovc),
	      .sw_req_nonspec_ivc(sw_req_nonspec_ivc),
	      .sw_req_spec_ivc(sw_req_spec_ivc),
	      .sw_gnt_nonspec_ivc(sw_gnt_nonspec_ivc),
	      .sw_gnt_spec_ivc(sw_gnt_spec_ivc),
	      .flit_valid_out(flit_valid_out),
	      .flit_vc_out(flit_vc_out),
	      .flit_head_out(flit_head_out),
	      .flit_tail_out(flit_tail_out),
	      .flit_data_out(flit_data_out),
	      .cred_valid_out(cred_valid_out),
	      .cred_vc_out(cred_vc_out),
	      .error(ipc_error));
	   
	   assign route_ip_ivc_op[ip*num_vcs*num_ports:
				  (ip+1)*num_vcs*num_ports-1] = route_ivc_op;
	   assign vc_req_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = vc_req_ivc;
	   assign vc_req_ip_ivc_ovc[ip*num_vcs*num_vcs:
				    (ip+1)*num_vcs*num_vcs-1] = vc_req_ivc_ovc;
	   assign sw_req_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_req_nonspec_ivc;
	   assign sw_req_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_req_spec_ivc;
	   assign xbc_data_in_ip[ip*xbc_width:
				 (ip+1)*xbc_width-1]
		    = {flit_valid_out, flit_head_out, flit_tail_out,
		       flit_vc_out};
	   assign xbd_data_in_ip[ip*xbd_width:
				 (ip+1)*xbd_width-1]
		    = flit_data_out;
	   assign cred_valid_out_ip[ip] = cred_valid_out;
	   assign cred_vc_out_ip[ip*vc_idx_width:
				 (ip+1)*vc_idx_width-1] = cred_vc_out;
	   assign ipc_error_ip[ip] = ipc_error;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // virtual channel allocator
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs*num_ports-1] vc_gnt_op_ovc_ip;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_gnt_op_ovc_ivc;
   
   vc_alloc
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .arbiter_type(vc_arbiter_type),
       .allocator_type(vc_allocator_type),
       .reset_type(reset_type))
   vca
     (.clk(clk),
      .reset(reset),
      .route_ip_ivc_op(route_ip_ivc_op),
      .req_ip_ivc(vc_req_ip_ivc),
      .req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
      .elig_op_ovc(elig_op_ovc),
      .gnt_ip_ivc(vc_gnt_ip_ivc),
      .gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
      .gnt_op_ovc(vc_gnt_op_ovc),
      .gnt_op_ovc_ip(vc_gnt_op_ovc_ip),
      .gnt_op_ovc_ivc(vc_gnt_op_ovc_ivc));
   
   
   //---------------------------------------------------------------------------
   // switch allocator
   //---------------------------------------------------------------------------
   
   sw_alloc
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .allocator_type(sw_allocator_type),
       .arbiter_type(sw_arbiter_type),
       .spec_level(sw_spec_level),
       .reset_type(reset_type))
   swa
     (.clk(clk),
      .reset(reset),
      .route_ip_ivc_op(route_ip_ivc_op),
      .req_nonspec_ip_ivc(sw_req_nonspec_ip_ivc),
      .req_spec_ip_ivc(sw_req_spec_ip_ivc),
      .gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
      .gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc),
      .gnt_ip_op(sw_gnt_ip_op));
   
   
   //---------------------------------------------------------------------------
   // crossbar
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	xbr_ctrl_ip_op_s, xbr_ctrl_ip_op_q;
   assign xbr_ctrl_ip_op_s = sw_gnt_ip_op;
   dff
     #(.width(num_ports*num_ports),
       .reset_type(reset_type))
   xbr_ctrl_ip_opq
     (.clk(clk),
      .reset(reset),
      .d(xbr_ctrl_ip_op_s),
      .q(xbr_ctrl_ip_op_q));
   
   wire [0:num_ports*xbc_width-1] xbc_data_out_op;
   crossbar
     #(.num_in_ports(num_ports),
       .num_out_ports(num_ports),
       .width(xbc_width),
       .crossbar_type(xbc_crossbar_type))
   xbc
     (.ctrl_ip_op(xbr_ctrl_ip_op_q),
      .data_in_ip(xbc_data_in_ip),
      .data_out_op(xbc_data_out_op));
   
   wire [0:num_ports*xbd_width-1] xbd_data_out_op;
   crossbar
     #(.num_in_ports(num_ports),
       .num_out_ports(num_ports),
       .width(xbd_width),
       .crossbar_type(xbd_crossbar_type))
   xbd
     (.ctrl_ip_op(xbr_ctrl_ip_op_q),
      .data_in_ip(xbd_data_in_ip),
      .data_out_op(xbd_data_out_op));
   
   
   //---------------------------------------------------------------------------
   // output ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] xbr_ctrl_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   xbr_ctrl_op_ip_intl
     (.data_in(xbr_ctrl_ip_op_q),
      .data_out(xbr_ctrl_op_ip));
   
   wire [0:num_ports-1] 	  opc_error_op;
   
   generate
      
      genvar 			  op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:xbc_width-1] xbc_data_out;
	   assign xbc_data_out
	     = xbc_data_out_op[op*xbc_width:(op+1)*xbc_width-1];
	   
	   wire 		flit_valid;
	   assign flit_valid = xbc_data_out[0];
	   
	   wire 		flit_head;
	   assign flit_head = xbc_data_out[1];
	   
	   wire 		flit_tail;
	   assign flit_tail = xbc_data_out[2];
	   
	   wire [0:vc_idx_width-1] flit_vc;
	   assign flit_vc = xbc_data_out[3:3+vc_idx_width-1];
	   
	   wire [0:data_width-1]   xbd_data_out;
	   assign xbd_data_out
	     = xbd_data_out_op[op*data_width:(op+1)*data_width-1];
	   
	   wire [0:data_width-1]     flit_data;
	   assign flit_data = xbd_data_out;
	   
	   wire 		     cred_valid_s, cred_valid_q;
	   assign cred_valid_s = cred_valid_in_op[op];
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   cred_validq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_valid_s),
	      .q(cred_valid_q));
	   
	   wire 		     cred_valid_in;
	   assign cred_valid_in = cred_valid_q;
	   
	   wire [0:vc_idx_width-1]   cred_vc_s, cred_vc_q;
	   assign cred_vc_s = cred_vc_in_op[op*vc_idx_width:
					    (op+1)*vc_idx_width-1];
	   dff
	     #(.width(vc_idx_width),
	       .reset_type(reset_type))
	   cred_vcq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_vc_s),
	      .q(cred_vc_q));
	   
	   wire [0:vc_idx_width-1]   cred_vc_in;
	   assign cred_vc_in = cred_vc_q;
	   
	   wire [0:num_vcs-1] 	     vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
	   assign vc_gnt_ovc_ip = vc_gnt_op_ovc_ip[op*num_vcs*num_ports:
						   (op+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_vcs*num_vcs-1] 	vc_gnt_ovc_ivc;
	   assign vc_gnt_ovc_ivc = vc_gnt_op_ovc_ivc[op*num_vcs*num_vcs:
						     (op+1)*num_vcs*num_vcs-1];

	   wire [0:num_ports-1] 		  xbr_ctrl_ip;
	   assign xbr_ctrl_ip = xbr_ctrl_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire [0:vc_idx_width-1] 	flit_vc_out;
	   wire [0:num_vcs-1] 		elig_ovc;
	   wire [0:num_vcs*int_flow_ctrl_width-1] flow_ctrl_ovc;
	   wire 				  opc_error;
	   op_ctrl
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .track_vcs_at_output(track_vcs_at_output),
	       .credit_handling_type(credit_handling_type),
	       .cred_level_width(2),
	       .reset_type(reset_type))
	   opc
	     (.clk(clk),
	      .reset(reset),
	      .cred_valid_in(cred_valid_in),
	      .cred_vc_in(cred_vc_in),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .vc_gnt_ovc_ip(vc_gnt_ovc_ip),
	      .vc_gnt_ovc_ivc(vc_gnt_ovc_ivc),
	      .flit_valid_in(flit_valid),
	      .flit_vc_in(flit_vc),
	      .flit_vc_out(flit_vc_out),
	      .flit_tail_in(flit_tail),
	      .flit_ip_in(xbr_ctrl_ip),
	      .elig_ovc(elig_ovc),
	      .flow_ctrl_ovc(flow_ctrl_ovc),
	      .error(opc_error));
	   
	   assign elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = elig_ovc;
	   assign flow_ctrl_op_ovc[op*num_vcs*int_flow_ctrl_width:
				   (op+1)*num_vcs*int_flow_ctrl_width-1]
		    = flow_ctrl_ovc;
	   
	   wire 				  xbr_ctrl;
	   assign xbr_ctrl = |xbr_ctrl_ip;
	   
	   wire 				  flit_valid_s, flit_valid_q;
	   assign flit_valid_s = flit_valid;
	   dff
	     #(.width(1),
	      .reset_type(reset_type))
	     flit_validq
	       (.clk(clk),
		.reset(reset),
		.d(flit_valid_s),
		.q(flit_valid_q));
	   
	   assign flit_valid_out_op[op] 
		    = flit_valid_q;
	   
	   wire [0:vc_idx_width-1] 		  flit_vc_s, flit_vc_q;
	   
	   if(track_vcs_at_output)
	     assign flit_vc_s = xbr_ctrl ? flit_vc_out : flit_vc_q;
	   else
	     assign flit_vc_s = xbr_ctrl ? flit_vc : flit_vc_q;
	   
	   dff
	     #(.width(vc_idx_width),
	       .reset_type(reset_type))
	   flit_vcq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_vc_s),
	      .q(flit_vc_q));
	   
	   assign flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1]
		    = flit_vc_q;
	   
	   wire 				  flit_head_s, flit_head_q;
	   assign flit_head_s = xbr_ctrl ? flit_head : flit_head_q;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_headq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_head_s),
	      .q(flit_head_q));
	   
	   assign flit_head_out_op[op]
		    = flit_head_q;
	   
	   wire 				  flit_tail_s, flit_tail_q;
	   assign flit_tail_s = xbr_ctrl ? flit_tail : flit_tail_q;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_tailq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_tail_s),
	      .q(flit_tail_q));
	   
	   assign flit_tail_out_op[op]
		    = flit_tail_q;
	   
	   wire [0:data_width-1] 		  flit_data_s, flit_data_q;
	   assign flit_data_s = xbr_ctrl ? flit_data : flit_data_q;
	   dff
	     #(.width(data_width),
	       .reset_type(reset_type))
	   flit_dataq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_data_s),
	      .q(flit_data_q));
	   
	   assign flit_data_out_op[op*data_width:(op+1)*data_width-1]
		    = flit_data_q;
	   
	   assign opc_error_op[op] = opc_error;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error reporting
   //---------------------------------------------------------------------------
   
   wire [0:2*num_ports-1] 			  errors_in;
   assign errors_in = {ipc_error_ip, opc_error_op};
   
   wire [0:2*num_ports-1] 			  errors_out;
   checker
     #(.num_errors(2*num_ports),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out;
   
endmodule
