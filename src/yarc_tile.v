// $Id: vcr_top.v 1194 2009-04-01 12:27:33Z dub $

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
module yarc_tile
  (/*AUTOARG*/
   // Outputs
   flow_ctrl_out_row_bus, flit_ctrl_out_row_bus,
   flit_data_out_row_bus, flow_ctrl_out_col_bus,
   flit_ctrl_out_col_bus, flit_data_out_col_bus, flow_ctrl_out_tile,
   flit_ctrl_out_tile, flit_data_out_tile, error,
   // Inputs
   clk, reset, router_address, flit_ctrl_in_row_bus,
   flit_data_in_row_bus, flow_ctrl_in_row_bus, flit_ctrl_in_col_bus,
   flit_data_in_col_bus, flow_ctrl_in_col_bus, flit_ctrl_in_tile,
   flit_data_in_tile, flow_ctrl_in_tile
   );
   
//  (clk, reset, router_address, flit_ctrl_in_ip, flit_data_in_ip, 
//   flow_ctrl_out_ip, flit_ctrl_out_op, flit_data_out_op, flow_ctrl_in_op, 
//   error);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb 			    = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb 		    = clogb + 1;
      end
   endfunction
   
   // flit buffer entries per VC  input buffer
   parameter num_flit_buffers 	    = 128;
   parameter num_row_buffers 	    = 32;
   parameter num_col_buffers 	    = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers     = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes    = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes    = 1;
   
   // total number of packet classes
   localparam num_classes 	    = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class 	    = 1;
   
   // number of VCs
   localparam num_vcs 		    = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width 	    = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports 		    = 8;
   
   // width required to select an individual port
   localparam port_idx_width 	    = clogb(num_ports);
   
   // number of dimensions in network
   parameter num_dimensions 	    = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim    = 8;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim  = 2;
   
   // select packet format
   parameter packet_format 	    = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length     = 10;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length     = 1;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width 	    = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width     = num_dimensions * dim_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width  = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
				 (1 + vc_idx_width + 1 + 1) : 
				 (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
				 (1 + vc_idx_width + 1) : 
				 -1;
   
   // width of flit payload data
   parameter flit_data_width = 32;
   
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
   parameter track_vcs_at_output = 0;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width
     = 1 + vc_idx_width + 1 + 1;
   
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
   
   // number of entries in flit buffer
   localparam fbf_depth = num_vcs*num_flit_buffers;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
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
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;


   
   // control signals for each incoming flit
   //input [0:num_ports*flit_ctrl_width-1] flit_ctrl_in_ip;
   input [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_in_row_bus;
   
   // flit data for each incoming flit
   //input [0:num_ports*flit_data_width-1] flit_data_in_ip;
   input [0:(num_ports-1)*flit_data_width-1] flit_data_in_row_bus;

   // incoming flow control signals
   input [0:(num_ports)*flow_ctrl_width-1] flow_ctrl_in_row_bus;
   //input [0:num_ports*flow_ctrl_width-1] flow_ctrl_in_op;
   
   // outgoing flow control signals
   //output [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip;
   output [0:(num_ports)flow_ctrl_width-1] flow_ctrl_out_row_bus;
   //??wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip;
   
   // control signals for each outgoing flit
   //output [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op;
   output [0:(num_ports)*flit_ctrl_width-1] flit_ctrl_out_row_bus;
   //??wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op;
   
   // flit data for each outgoing flit
   //output [0:num_ports*flit_data_width-1] flit_data_out_op;
   output [0:(num_ports)*flit_data_width-1] flit_data_out_row_bus;
   //>>wire [0:num_ports*flit_data_width-1] flit_data_out_op;
   






      // control signals for each incoming flit
   //input [0:num_ports*flit_ctrl_width-1] flit_ctrl_in_ip;
   input [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_in_col_bus;
   
   // flit data for each incoming flit
   //input [0:num_ports*flit_data_width-1] flit_data_in_ip;
   input [0:(num_ports-1)*flit_data_width-1] flit_data_in_col_bus;
   
   // outgoing flow control signals
   //output [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip;
   output [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_out_col_bus;
   //??wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip;
   
   // control signals for each outgoing flit
   //output [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op;
   output [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_out_col_bus;
   //??wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op;
   
   // flit data for each outgoing flit
   //output [0:num_ports*flit_data_width-1] flit_data_out_op;
   output [0:(num_ports-1)*flit_data_width-1] flit_data_out_col_bus;
   //>>wire [0:num_ports*flit_data_width-1] flit_data_out_op;
   
   // incoming flow control signals
   input [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_in_col_bus;
   //input [0:num_ports*flow_ctrl_width-1] flow_ctrl_in_op;


   
   
   //actual input port
   input [0:flit_ctrl_width-1] flit_ctrl_in_tile;
   input [0:flit_data_width-1] flit_data_in_tile;
   input [0:flow_ctrl_width-1] flow_ctrl_in_tile;
   output [0:flow_ctrl_width-1] flow_ctrl_out_tile;
   output [0:flit_ctrl_width-1] flit_ctrl_out_tile;
   output [0:flit_data_width-1] flit_data_out_tile;
   
   // internal error condition detected
   output error;
   wire   error;
   
   
   //---------------------------------------------------------------------------
   // input ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	elig_op_ovc;
   wire [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   wire [0:num_ports*num_vcs*port_idx_width-1] 	    route_port_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    inc_rc_ip_ivc;
   
   wire [0:num_ports*num_vcs-1] 		    vc_req_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	    vc_gnt_ip_ivc_ovc;
   
   wire [0:num_ports*num_vcs-1] 		    sw_req_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_req_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_spec_ip_ivc;
   wire [0:num_ports*num_ports-1] 		    sw_gnt_ip_op;
   
   wire [0:num_ports*int_flit_ctrl_width-1] 	    xbc_data_in_ip;
   wire [0:num_ports*flit_data_width-1] 	    xbd_data_in_ip;
   
   wire [0:num_ports-1] 			    ipc_error_ip;
   
   generate
      
      genvar 					    ip;
      
      for (ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   
	   //-------------------------------------------------------------------
	   // input controller
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_ctrl_width-1] flit_ctrl_in;
	   assign flit_ctrl_in
	     = flit_ctrl_in_ip[ip*flit_ctrl_width:(ip+1)*flit_ctrl_width-1];
	   
	   wire [0:flit_data_width-1] flit_data_in;
	   assign flit_data_in
	     = flit_data_in_ip[ip*flit_data_width:(ip+1)*flit_data_width-1];
	   
	   wire [0:num_vcs-1] 	      vc_gnt_ivc;
	   assign vc_gnt_ivc = vc_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
	   assign vc_gnt_ivc_ovc
	     = vc_gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:(ip+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_nonspec_ivc;
	   assign sw_gnt_nonspec_ivc
	     = sw_gnt_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_spec_ivc;
	   assign sw_gnt_spec_ivc
	     = sw_gnt_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs*port_idx_width-1] route_port_ivc;
	   wire [0:num_vcs-1] 		     inc_rc_ivc;
	   wire [0:num_vcs-1] 		     vc_req_ivc;
	   wire [0:num_vcs-1] 		     sw_req_nonspec_ivc;
	   wire [0:num_vcs-1] 		     sw_req_spec_ivc;
	   wire [0:int_flit_ctrl_width-1]    int_flit_ctrl_out;
	   wire [0:flit_data_width-1] 	     flit_data_out;
	   wire [0:flow_ctrl_width-1] 	     flow_ctrl_out;
	   wire [0:fbf_addr_width-1] 	     fbf_write_addr;
	   wire 			     fbf_write_enable;
	   wire [0:flit_data_width-1] 	     fbf_write_data;
	   wire [0:fbf_addr_width-1] 	     fbf_read_addr;
	   wire 			     fbf_read_enable;
	   wire [0:flit_data_width-1] 	     fbf_read_data;
	   wire 			     ipc_error;
	   vcr_ip_ctrl_mac
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
	       .track_vcs_at_output(track_vcs_at_output),
	       .routing_function_type(routing_function_type),
	       .dimension_order(dimension_order),
	       .credit_handling_type(credit_handling_type),
	       .header_fifo_type(header_fifo_type),
	       .sw_spec_enable(sw_spec_enable),
	       .perf_ctr_enable(perf_ctr_enable),
	       .perf_ctr_width(perf_ctr_width),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .port_id(ip),
	       .reset_type(reset_type))
	   ipc
	     (.error(ipc_error),
	      /*AUTOINST*/
	      // Outputs
	      .route_port_ivc		(route_port_ivc[0:num_vcs*port_idx_width-1]),
	      .inc_rc_ivc		(inc_rc_ivc[0:num_vcs-1]),
	      .vc_req_ivc		(vc_req_ivc[0:num_vcs-1]),
	      .sw_req_nonspec_ivc	(sw_req_nonspec_ivc[0:num_vcs-1]),
	      .sw_req_spec_ivc		(sw_req_spec_ivc[0:num_vcs-1]),
	      .int_flit_ctrl_out	(int_flit_ctrl_out[0:int_flit_ctrl_width-1]),
	      .flit_data_out		(flit_data_out[0:flit_data_width-1]),
	      .flow_ctrl_out		(flow_ctrl_out[0:flow_ctrl_width-1]),
	      .fbf_write_addr		(fbf_write_addr[0:fbf_addr_width-1]),
	      .fbf_write_enable		(fbf_write_enable),
	      .fbf_write_data		(fbf_write_data[0:flit_data_width-1]),
	      .fbf_read_addr		(fbf_read_addr[0:fbf_addr_width-1]),
	      .fbf_read_enable		(fbf_read_enable),
	      // Inputs
	      .clk			(clk),
	      .reset			(reset),
	      .router_address		(router_address[0:router_addr_width-1]),
	      .flit_ctrl_in		(flit_ctrl_in[0:flit_ctrl_width-1]),
	      .flit_data_in		(flit_data_in[0:flit_data_width-1]),
	      .int_flow_ctrl_op_ovc	(int_flow_ctrl_op_ovc[0:num_ports*num_vcs*int_flow_ctrl_width-1]),
	      .vc_gnt_ivc		(vc_gnt_ivc[0:num_vcs-1]),
	      .vc_gnt_ivc_ovc		(vc_gnt_ivc_ovc[0:num_vcs*num_vcs-1]),
	      .sw_gnt_nonspec_ivc	(sw_gnt_nonspec_ivc[0:num_vcs-1]),
	      .sw_gnt_spec_ivc		(sw_gnt_spec_ivc[0:num_vcs-1]),
	      .fbf_read_data		(fbf_read_data[0:flit_data_width-1]));
	   
	   c_regfile_mac
	     #(.width(flit_data_width),
	       .depth(fbf_depth),
	       .regfile_type(fbf_regfile_type))
	   fbf
	     (.write_enable(fbf_write_enable),
	      .write_address(fbf_write_addr),
	      .write_data(fbf_write_data),
	      .read_enable(fbf_read_enable),
	      .read_address(fbf_read_addr),
	      .read_data(fbf_read_data),
	      /*AUTOINST*/
	      // Inputs
	      .clk			(clk));
	   
	   assign route_port_ip_ivc[ip*num_vcs*port_idx_width:
				    (ip+1)*num_vcs*port_idx_width-1]
		    = route_port_ivc;
	   assign inc_rc_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = inc_rc_ivc;
	   assign vc_req_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = vc_req_ivc;
	   assign sw_req_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_req_nonspec_ivc;
	   assign sw_req_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_req_spec_ivc;
	   assign xbc_data_in_ip[ip*int_flit_ctrl_width:
				 (ip+1)*int_flit_ctrl_width-1]
		    = int_flit_ctrl_out;
	   assign xbd_data_in_ip[ip*flit_data_width:(ip+1)*flit_data_width-1]
		    = flit_data_out;
	   assign flow_ctrl_out_ip[ip*flow_ctrl_width:
				   (ip+1)*flow_ctrl_width-1]
		    = flow_ctrl_out;
	   assign ipc_error_ip[ip] = ipc_error;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // virtual channel allocator
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	  vc_gnt_op_ovc;
   wire [0:num_ports*num_vcs*num_ports-1] vc_gnt_op_ovc_ip;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_gnt_op_ovc_ivc;
   
   vcr_vc_alloc_mac
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .arbiter_type(vc_arbiter_type),
       .allocator_type(vc_allocator_type),
       .reset_type(reset_type))
   vca
     (.req_ip_ivc(vc_req_ip_ivc),
      .gnt_ip_ivc(vc_gnt_ip_ivc),
      .gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
      .gnt_op_ovc(vc_gnt_op_ovc),
      .gnt_op_ovc_ip(vc_gnt_op_ovc_ip),
      .gnt_op_ovc_ivc(vc_gnt_op_ovc_ivc),
      /*AUTOINST*/
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .route_port_ip_ivc		(route_port_ip_ivc[0:num_ports*num_vcs*port_idx_width-1]),
      .inc_rc_ip_ivc			(inc_rc_ip_ivc[0:num_ports*num_vcs-1]),
      .elig_op_ovc			(elig_op_ovc[0:num_ports*num_vcs-1]));
   
   
   //---------------------------------------------------------------------------
   // switch allocator
   //---------------------------------------------------------------------------
   
   vcr_sw_alloc_mac
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .allocator_type(sw_allocator_type),
       .arbiter_type(sw_arbiter_type),
       .spec_level(sw_spec_level),
       .reset_type(reset_type))
   swa
     (.req_nonspec_ip_ivc(sw_req_nonspec_ip_ivc),
      .req_spec_ip_ivc(sw_req_spec_ip_ivc),
      .gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
      .gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc),
      .gnt_ip_op(sw_gnt_ip_op),
      /*AUTOINST*/
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .route_port_ip_ivc		(route_port_ip_ivc[0:num_ports*num_vcs*port_idx_width-1]));
   
   
   //---------------------------------------------------------------------------
   // crossbars
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	  xbc_ctrl_ip_op;
   assign xbc_ctrl_ip_op = sw_gnt_ip_op;
   
   wire [0:num_ports*int_flit_ctrl_width-1] xbc_data_out_op;
   wire [0:num_ports*num_ports-1] 	    xbc_ctrl_op_ip;
   c_crossbar_mac
     #(.num_in_ports(num_ports),
       .num_out_ports(num_ports),
       .width(int_flit_ctrl_width),
       .crossbar_type(xbc_crossbar_type),
       .reset_type(reset_type))
   xbc
     (.ctrl_in_ip_op(xbc_ctrl_ip_op),
      .ctrl_out_op_ip(xbc_ctrl_op_ip),
      .data_in_ip(xbc_data_in_ip),
      .data_out_op(xbc_data_out_op),
      /*AUTOINST*/
      // Inputs
      .clk				(clk),
      .reset				(reset));
   
   wire [0:num_ports*num_ports-1] 	    xbd_ctrl_ip_op;
   assign xbd_ctrl_ip_op = sw_gnt_ip_op;
   
   wire [0:num_ports*flit_data_width-1]     xbd_data_out_op;
   wire [0:num_ports*num_ports-1] 	    xbd_ctrl_op_ip;
   c_crossbar_mac
     #(.num_in_ports(num_ports),
       .num_out_ports(num_ports),
       .width(flit_data_width),
       .crossbar_type(xbd_crossbar_type),
       .reset_type(reset_type))
   xbd
     (.ctrl_in_ip_op(xbd_ctrl_ip_op),
      .ctrl_out_op_ip(xbd_ctrl_op_ip),
      .data_in_ip(xbd_data_in_ip),
      .data_out_op(xbd_data_out_op),
      /*AUTOINST*/
      // Inputs
      .clk				(clk),
      .reset				(reset));
   
   
   //---------------------------------------------------------------------------
   // output ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] 	  opc_error_op;
   
   generate
      
      genvar 			  op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:int_flit_ctrl_width-1] int_flit_ctrl_in;
	   assign int_flit_ctrl_in
	     = xbc_data_out_op[op*int_flit_ctrl_width:
			       (op+1)*int_flit_ctrl_width-1];
	   
	   wire [0:flit_data_width-1] flit_data_in;
	   assign flit_data_in
	     = xbd_data_out_op[op*flit_data_width:(op+1)*flit_data_width-1];
	   
	   wire [0:flow_ctrl_width-1] flow_ctrl_in;
	   assign flow_ctrl_in
	     = flow_ctrl_in_op[op*flow_ctrl_width:(op+1)*flow_ctrl_width-1];
	   
	   wire [0:num_vcs-1] 	      vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
	   assign vc_gnt_ovc_ip = vc_gnt_op_ovc_ip[op*num_vcs*num_ports:
						   (op+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_vcs*num_vcs-1] 	vc_gnt_ovc_ivc;
	   assign vc_gnt_ovc_ivc = vc_gnt_op_ovc_ivc[op*num_vcs*num_vcs:
						     (op+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_ports-1] 	xbc_ctrl_ip;
	   assign xbc_ctrl_ip = xbc_ctrl_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire [0:flit_ctrl_width-1] 	flit_ctrl_out;
	   wire [0:flit_data_width-1] 	flit_data_out;
	   wire [0:num_vcs-1] 		elig_ovc;
	   wire [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
	   wire 				  opc_error;
	   vcr_op_ctrl_mac
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_ports(num_ports),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .num_dimensions(num_dimensions),
	       .packet_format(packet_format),
	       .max_payload_length(max_payload_length),
	       .min_payload_length(min_payload_length),
	       .flit_data_width(flit_data_width),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .track_vcs_at_output(track_vcs_at_output),
	       .credit_handling_type(credit_handling_type),
	       .cred_level_width(2),
	       .reset_type(reset_type))
	   opc
	     (.xbr_ctrl_ip(xbc_ctrl_ip),
	      .error(opc_error),
	      /*AUTOINST*/
	      // Outputs
	      .flit_ctrl_out		(flit_ctrl_out[0:flit_ctrl_width-1]),
	      .flit_data_out		(flit_data_out[0:flit_data_width-1]),
	      .elig_ovc			(elig_ovc[0:num_vcs-1]),
	      .int_flow_ctrl_ovc	(int_flow_ctrl_ovc[0:num_vcs*int_flow_ctrl_width-1]),
	      // Inputs
	      .clk			(clk),
	      .reset			(reset),
	      .flow_ctrl_in		(flow_ctrl_in[0:flow_ctrl_width-1]),
	      .vc_gnt_ovc		(vc_gnt_ovc[0:num_vcs-1]),
	      .vc_gnt_ovc_ip		(vc_gnt_ovc_ip[0:num_vcs*num_ports-1]),
	      .vc_gnt_ovc_ivc		(vc_gnt_ovc_ivc[0:num_vcs*num_vcs-1]),
	      .int_flit_ctrl_in		(int_flit_ctrl_in[0:int_flit_ctrl_width-1]),
	      .flit_data_in		(flit_data_in[0:flit_data_width-1]));
	   
	   assign flit_ctrl_out_op[op*flit_ctrl_width:(op+1)*flit_ctrl_width-1]
		    = flit_ctrl_out;
	   assign flit_data_out_op[op*flit_data_width:(op+1)*flit_data_width-1]
		    = flit_data_out;
	   
	   assign elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = elig_ovc;
	   assign int_flow_ctrl_op_ovc[op*num_vcs*int_flow_ctrl_width:
				       (op+1)*num_vcs*int_flow_ctrl_width-1]
		    = int_flow_ctrl_ovc;
	   
	   assign opc_error_op[op] = opc_error;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // error reporting
   //---------------------------------------------------------------------------
   
   wire [0:2*num_ports-1] 			  errors_in;
   assign errors_in = {ipc_error_ip, opc_error_op};
   
   wire [0:2*num_ports-1] 			  errors_out;
   c_checker
     #(.num_errors(2*num_ports),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (
      /*AUTOINST*/
      // Outputs
      .errors_out			(errors_out[0:num_errors-1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .errors_in			(errors_in[0:num_errors-1]));
   
   assign error = |errors_out;
   
endmodule
