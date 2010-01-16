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


// flit control signal decoding logic
module rtr_flit_ctrl_dec
  (clk, reset, active, flit_ctrl, header_info, flit_done, flit_head, flit_tail);
   
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
   // connectivity within each dimension
   parameter connectivity = `CONNECTIVITY_LINE;
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length = 4;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
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
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // width required for lookahead routing information
   localparam la_route_info_width
     = port_idx_width + ((num_resource_classes > 1) ? 1 : 0);
   
   // offset of lookahead routing information in header info
   localparam la_route_info_offset = 0;
   
   // total number of bits required for storing routing information
   localparam route_info_width
     = num_resource_classes * router_addr_width + node_addr_width;
   
   // offset of routing information in header info
   localparam route_info_offset = la_route_info_offset + la_route_info_width;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // offset of payload length field (if present) in header info
   localparam payload_length_offset = route_info_offset + route_info_width;
   
   // total width of header data
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) :
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ?
       (la_route_info_width + route_info_width + payload_length_width) :
       -1;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 2 : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 1 : 
       -1;
   
   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   input active;
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl;
   
   // incoming flit data signals
   input [0:header_info_width-1] header_info;
   
   // flit was sent
   input flit_done;
   
   // flit is head flit
   output flit_head;
   wire flit_head;
   
   // flit is tail flit
   output flit_tail;
   wire flit_tail;
   
   
   //---------------------------------------------------------------------------
   // implementations for different packet formats
   //---------------------------------------------------------------------------
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     assign flit_head = flit_ctrl[0];
	     
	     case(packet_format)
	       
	       `PACKET_FORMAT_HEAD_TAIL:
		 begin
		    
		    assign flit_tail = flit_ctrl[1];
		    
		 end
	       
	       `PACKET_FORMAT_EXPLICIT_LENGTH:
		 begin
		    
		    if(max_payload_length == 0)
		      begin
			 
			 if(max_payload_length == min_payload_length)
			   assign flit_tail = flit_head;
			 
		      end
		    else if(max_payload_length == 1)
		      begin
			 
			 if(max_payload_length > min_payload_length)
			   begin
			      
			      wire [0:payload_length_width-1] payload_length;
			      assign payload_length
				= header_info[payload_length_offset:
					      payload_length_offset+
					      payload_length_width-1];
			      
			      wire no_payload;
			      assign no_payload = ~|payload_length;
			      
			      assign flit_tail
				= ~flit_head | no_payload;
			      
			   end
			 else if(max_payload_length == min_payload_length)
			   assign flit_tail = ~flit_head;
			 
		      end
		    else
		      begin
			 
			 wire [0:payload_length_width-1] payload_length;
			 assign payload_length
			   = header_info[payload_length_offset:
					 payload_length_offset+
					 payload_length_width-1];
			 
			 wire [0:flit_ctr_width-1] 	 flit_ctr_load;
			 assign flit_ctr_load = payload_length - 1'b1;
			 
			 wire [0:flit_ctr_width-1] flit_ctr_s, flit_ctr_q;
			 assign flit_ctr_s = flit_done ? 
					     (flit_head ? 
					      flit_ctr_load : 
					      (flit_ctr_q - 1'b1)) : 
					     flit_ctr_q;
			 c_dff
			   #(.width(flit_ctr_width),
			     .reset_type(reset_type))
			 flit_ctrq
			   (.clk(clk),
			    .reset(reset),
			    .active(active),
			    .d(flit_ctr_s),
			    .q(flit_ctr_q));
			 
			 wire 			   flit_ctr_zero;
			 assign flit_ctr_zero = ~|flit_ctr_q;
			 
			 if(min_payload_length == 0)
			   begin
			      
			      wire no_payload;
			      assign no_payload = ~|payload_length;
			      
			      assign flit_tail
				= flit_head ? no_payload : flit_ctr_zero;
			      
			   end
			 else
			   assign flit_tail 
			     = ~flit_head & flit_ctr_zero;
			 
		      end
		    
		 end
	       
	     endcase
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
