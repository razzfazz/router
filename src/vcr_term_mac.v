// $Id: vcr_top.v 1212 2009-04-23 19:52:00Z dub $

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

// network terminal (combined packet source / sink) for VC router
module vcr_term_mac
  (clk, reset, address, flit_ctrl_out, flit_data_out, flow_ctrl_in, 
   flit_ctrl_in, flit_data_in, flow_ctrl_out);
   
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
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of nodes per router (a.k.a. consentration factor)
   localparam num_nodes_per_router
     = num_ports - num_dimensions * num_neighbors_per_dim;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
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
   
   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
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
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select width (and thus period) for CFSRs
   parameter cfsr_width = 20;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
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
   
   // internal error condition detected
   output error;
   wire 		      error;
   
   
   //---------------------------------------------------------------------------
   // address decoding
   //---------------------------------------------------------------------------
   
   wire 		      load_ctrl;
   wire 		      load_arrival_threshold;
   wire 		      load_arrival_rv;
   
   
   //---------------------------------------------------------------------------
   // control register
   //---------------------------------------------------------------------------
   
   wire 		      load_ctrl;
   
   wire [0:ctrl_width-1]      ctrl_s, ctrl_q;
   assign ctrl_s = load_ctrl ? 
		   load_value[0:ctrl_width-1] : 
		   ctrl_q;
   c_dff
     #(.width(ctrl_width),
       .reset_type(reset_type),
       .reset_value(reset_value))
   ctrlq
     (.clk(clk),
      .reset(reset),
      .d(ctrl_s),
      .q(ctrl_q));
   
   wire 		      run;
   assign run = ctrl_q[0];
   
   
   //---------------------------------------------------------------------------
   // packet arrival times
   //---------------------------------------------------------------------------
   
   wire [0:cfsr_width-1] arrival_cfsr_s, arrival_cfsr_q;
   assign arrival_cfsr_s = load_value[0:cfsr_width-1];
   c_cfsr
     #(.width(cfsr_width),
       .reset_type(reset_type))
   arrival_cfsr
     (.clk(clk),
      .reset(reset),
      .load(load_arrival_cfsr),
      .run(run),
      .feedback(arrival_cfsr_feedback),
      .d(arrival_cfsr_s),
      .q(arrival_cfsr_q));
   
   wire [0:arrival_rv_width-1] arrival_rv;
   assign arrival_rv = arrival_cfsr_q[0:arrival_rv_width-1];
   
   wire [0:arrival_rv_width-1] arrival_threshold_s, arrival_threshold_q;
   assign arrival_threshold_s = load_arrival_threshold ? 
				load_value[0:arrival_rv_width-1] : 
				arrival_threshold_q;
   c_dff
     #(.width(arrival_rv_width),
       .reset_type(reset_type),
       .reset_value({arrival_rv_width{1'b0}}))
   arrival_thresholdq
     (.clk(clk),
      .reset(reset),
      .d(arrival_threshold_s),
      .q(arrival_threshold_q));
   
   wire 		       new_packet_rv;
   assign new_packet_rv = (arrival_rv < arrival_threshold_q);
   
   
   //---------------------------------------------------------------------------
   // VC ID
   //---------------------------------------------------------------------------
   
   wire [0:cfsr_width-1]       vc_idx_cfsr_s, vc_idx_cfsr_q;
   assign vc_idx_cfsr_s = load_value[0:cfsr_width-1];
   c_cfsr
     #(.width(cfsr_width),
       .reset_type(reset_type))
   vc_idx_cfsr
     (.clk(clk),
      .reset(reset),
      .load(load_vc_idx_cfsr),
      .run(packet_sent),
      .feedback(vc_idx_cfsr_feedback),
      .d(vc_idx_cfsr_s),
      .q(vc_idx_cfsr_q));
   
   wire [0:vc_idx_width-1] 	 vc_idx_rv;
   assign vc_idx_rv = vc_idx_rv_q[0:vc_idx_width-1];
   
   
   //---------------------------------------------------------------------------
   // packet length
   //---------------------------------------------------------------------------
   
   generate
      
      // implementation for the case where the number of distinct possible 
      // payload lengths is a power of two
      if(max_payload_length-min_payload_length+1 == (1 << payload_length_width))
	begin
	   
	   wire [0:cfsr_width-1]  payload_length_cfsr_s, payload_length_cfsr_q;
	   assign payload_length_cfsr_s = load_value[0:cfsr_width-1];
	   c_cfsr
	     #(.width(cfsr_width),
	       .reset_type(reset_type))
	   payload_length_cfsr
	     (.clk(clk),
	      .reset(reset),
	      .load(load_payload_length_cfsr),
	      .run(packet_sent),
	      .d(payload_length_rv_s),
	      .q(payload_length_rv_q));
	   
	   wire [0:packet_length_width-1] packet_length_rv;
	   assign packet_length_rv
	     = payload_length_rv_q[0:payload_length_width-1] + 
	       min_payload_length;

	end
      
      // synopsys translate_off
      else
	begin
	   initial
	   begin
	      $display("ERROR: The traffic generator module doesn't " \
		       "currently support the specified combination of " \
		       "minimum and maximum payload size; the number of " \
		       "possible payload length values must be a power of " \
		       "two.");
	      $stop;
	   end
	end
      // synopsys translate_on
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // destination addresses
   //---------------------------------------------------------------------------
   
   wire [0:route_info_width-1] 	  route_info_rv_s, route_info_rv_q;
   assign route_info_rv_s = load_valuep0:route_info_rv_width-1];
   c_cfsr
     #(.width(route_info_rv_width),
       .reset_type(reset_type),
       .reset_value(route_info_rv_reset_value))
   route_info_rv_cfsr
     (.clk(clk),
      .reset(reset),
      .load(load_route_info_rv),
      .run(new_packet),
      .d(route_info_rv_s),
      .q(route_info_rv_q));
   
   generate
      
      genvar 					    rc;
      
      for(rc = 0; rc < num_resource_classes; rc = rc + 1)
	begin:rcs

	   if(rc < (num_resource_classes - 1))
	     begin
		
		wire [0:router_addr_width-1] addr_offset_rv_s, addr_offset_rv_q;
		assign addr_offset_rv_s
		  = load_value[rc*router_addr_width:(rc+1)*router_addr_width-1];
		c_lfsr
		  #(.width(router_addr_width),
		    .reset_type(reset_type),
		    .reset_value(addr_offset_rv_reset_value[rc*
							    router_addr_width:
							    (rc+1)*
							    router_addr_width
							    -1]))
		addr_offset_rv_lfsr
		  (.clk(clk),
		   .reset(reset),
		   .load(load_addr_offset_rv),
		   .run(new_packet),
		   .d(addr_offset_rv_s),
		   .q(addr_offset_rv_q));
		
		wire [0:router_addr_width-1] dest_addr_rv;
		assign dest_addr_rv
		  = route_info_rv[(rc+1)*router_addr_width:
				  (rc+2)*router_addr_width-1] +
		    addr_offset_rv_q;
		
		assign route_info_rv[rc*router_addr_width:
				     (rc+1)*router_addr_width-1]
			 = dest_addr_rv;
		
	     end
	   else
	     begin
		
		wire [0:addr_width-1] addr_offset_rv_s, addr_offset_rv_q;
		assign addr_offset_rv_s
		  = load_value[rc*router_addr_width:
			       rc*router_addr_width+addr_width-1];
		c_lfsr
		  #(.width(router_addr_width),
		    .reset_type(reset_type),
		    .reset_value(addr_offset_rv_reset_value[rc*
							    router_addr_width:
							    (rc+1)*
							    router_addr_width
							    -1]))
		addr_offset_rv_lfsr
		  (.clk(clk),
		   .reset(reset),
		   .load(load_addr_offset_rv),
		   .run(new_packet),
		   .d(addr_offset_rv_s),
		   .q(addr_offset_rv_q));
		
		wire [0:router_addr_width-1] dest_addr_rv;
		assign dest_addr_rv
		  = route_info_rv[(rc+1)*router_addr_width:
				  (rc+2)*router_addr_width-1] +
		    addr_offset_rv_q;
		
		assign route_info_rv[rc*router_addr_width:
				     (rc+1)*router_addr_width-1]
			 = dest_addr_rv;
		
		
	     end
	   
	end
      
      
   endgenerate
   
endmodule
