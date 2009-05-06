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
   flow_ctrl_out_row_bus, flit_data_out_row_bus,
   flit_ctrl_out_row_bus, flit_ctrl_out_col_bus,
   flit_data_out_col_bus, flow_ctrl_out_col_bus, flow_ctrl_out_tile,
   flit_ctrl_out_tile, flit_data_out_tile, error,
   // Inputs
   clk, reset, router_address, flit_ctrl_in_row_bus,
   flit_data_in_row_bus, flow_ctrl_in_row_bus, flow_ctrl_in_col_bus,
   flit_ctrl_in_col_bus, flit_data_in_col_bus, flit_ctrl_in_tile,
   flit_data_in_tile, flow_ctrl_in_tile
   );
   
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
   parameter perf_ctr_enable = 0;
   
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


   //row bus inputs
   input [0:num_vcs*(num_ports-1)*flit_ctrl_width-1] flit_ctrl_in_row_bus;
   input [0:num_vcs*(num_ports-1)*flit_data_width-1] flit_data_in_row_bus;
   output [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_out_row_bus;

   
   //row bus outputs 
   //** only output your own bus
   input [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_in_row_bus;
   output [0:num_vcs*flit_data_width-1] flit_data_out_row_bus;
   output [0:num_vcs*flit_ctrl_width-1] flit_ctrl_out_row_bus;

   //col bus output
   input [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_in_col_bus;
   output [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_out_col_bus;
   output [0:(num_ports-1)*flit_data_width-1] flit_data_out_col_bus;


   //col bus input
   input [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_in_col_bus;
   input [0:(num_ports-1)*flit_data_width-1] flit_data_in_col_bus;
   output [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_out_col_bus;


   
   
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
   



   //flit_ctrl_in_row_bus and data are wrong!!!!
   row_bus_driver
     #(/*AUTOINSTPARAM*/
       // Parameters
       .num_flit_buffers		(num_flit_buffers),
       .num_row_buffers			(num_row_buffers),
       .num_col_buffers			(num_col_buffers),
       .num_header_buffers		(num_header_buffers),
       .num_traffic_classes		(num_traffic_classes),
       .num_routing_classes		(num_routing_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_ports			(num_ports),
       .num_dimensions			(num_dimensions),
       .num_routers_per_dim		(num_routers_per_dim),
       .num_neighbors_per_dim		(num_neighbors_per_dim),
       .packet_format			(packet_format),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .perf_ctr_enable			(perf_ctr_enable),
       .perf_ctr_width			(perf_ctr_width),
       .checker_enable			(checker_enable),
       .checker_capture_mode		(checker_capture_mode),
       .track_vcs_at_output		(track_vcs_at_output),
       .routing_function_type		(routing_function_type),
       .dimension_order			(dimension_order),
       .credit_handling_type		(credit_handling_type),
       .header_fifo_type		(header_fifo_type),
       .fbf_regfile_type		(fbf_regfile_type),
       .vc_allocator_type		(vc_allocator_type),
       .vc_arbiter_type			(vc_arbiter_type),
       .sw_allocator_type		(sw_allocator_type),
       .sw_arbiter_type			(sw_arbiter_type),
       .sw_spec_level			(sw_spec_level),
       .xbc_crossbar_type		(xbc_crossbar_type),
       .xbd_crossbar_type		(xbd_crossbar_type),
       .reset_type			(reset_type))
     tile_input     
     (
      // Outputs
      .flit_ctrl_out_row_bus		(flit_ctrl_out_row_bus[0:num_vcs*flit_ctrl_width-1]),
      .flit_data_out_row_bus		(flit_data_out_row_bus[0:num_vcs*flit_data_width-1]),
      .flow_ctrl_out_tile		(flow_ctrl_out_tile[0:flow_ctrl_width-1]),
      // Inputs
      .router_address			(router_address[0:router_addr_width-1]),
      .clk				(clk),
      .reset				(reset),
      .flow_ctrl_in_row_bus		(flow_ctrl_in_row_bus[0:(num_ports-1)*flow_ctrl_width-1]),
      .flit_ctrl_in_tile		(flit_ctrl_in_tile[0:flit_ctrl_width-1]),
      .flit_data_in_tile		(flit_data_in_tile[0:flit_data_width-1]));
   

   
endmodule
