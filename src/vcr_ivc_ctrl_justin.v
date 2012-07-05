// $Id: vcr_ivc_ctrl.v 4280 2012-02-01 20:13:42Z dub $

/*
 Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

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

//==============================================================================
// input VC controller
//==============================================================================

module vcr_ivc_ctrl_justin
  (/*autoarg*/
   // Outputs
   route_op, route_orc, next_lar_info, flit_valid, flit_head,
   flit_tail, flit_sel_ovc, flit_data, empty, full, allocated,
   free_nonspec, free_spec, errors, expired, cancel_vc, drop_event,
   // Inputs
   clk, reset, router_address, flit_valid_in, flit_head_in,
   flit_tail_in, flit_data_in, int_flow_ctrl_op_ovc, vc_gnt,
   vc_gnt_ocvc, sw_gnt, flit_sent_prev, flit_tail_prev
   );
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
   
   // flit buffer entries per VC
   parameter num_flits_per_vc = 8;
   
   // width of credit hold register
   // (note: this parameter is only used for INT_FLOW_CTRL_TYPE_PUSH)
   localparam cred_hold_width = clogb(num_flits_per_vc);
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // width required to select individual resource class
   localparam resource_class_idx_width = clogb(num_resource_classes);
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs available for each class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 1;
   
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
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 64;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // width required for lookahead routing information
   localparam lar_info_width = port_idx_width + resource_class_idx_width;
   
   // select routing function type
   parameter routing_type = `ROUTING_TYPE_PHASED_DOR;
   
   // total number of bits required for storing routing information
   localparam dest_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   
   // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
   
   // select order of dimension traversal
   parameter dim_order = `DIM_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter int_flow_ctrl_type = `INT_FLOW_CTRL_TYPE_PUSH;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_LEVEL) ? 2 :
       (int_flow_ctrl_type == `INT_FLOW_CTRL_TYPE_PUSH) ? 1 :
       -1;
   
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask 			 = `ELIG_MASK_NONE;
   
   // enable speculative switch allocation
   parameter sw_alloc_spec 		 = 1;
   
   // select implementation variant for flit buffer register file
   parameter fb_regfile_type 		 = `REGFILE_TYPE_FF_2D;
   
   // use explicit pipeline register between flit buffer and crossbar?
   parameter explicit_pipeline_register  = 0;
   
   // gate flit buffer write port if bypass succeeds
   // (requires explicit pipeline register; may increase cycle time)
   parameter gate_buffer_write 		 = 0;
   
   // ID of current input VC
   parameter vc_id 			 = 0;
   
   // message class to which this VC belongs
   localparam message_class
     = (vc_id / (num_resource_classes*num_vcs_per_class)) % num_message_classes;
   
   // resource class to which this VC belongs
   localparam resource_class
     = (vc_id / num_vcs_per_class) % num_resource_classes;
   
   // required address size for a single VC's buffer
   localparam fb_addr_width 		 = clogb(num_flits_per_vc);
   
   // ID of current input port
   parameter port_id 			 = 0;
   

   // total number of bits required for storing time-to-wait information
   parameter time_to_wait_width 	 = 8;

   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       route_info_width + time_to_wait_width: 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       route_info_width + time_to_wait_width: 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (route_info_width + payload_length_width) : 
       -1;
   
   // width of TTW counter - increase this to make TTW more coarse
   localparam counter_width 		 = 10;
   
   parameter max_reservation_size 	 = 16; //packets
   localparam reservation_size_width 	 = clogb(max_reservation_size);
   
   parameter spec_buffer_capacity 	 = 4;
   localparam spec_buffer_width 	 = clogb(spec_buffer_capacity);
   
   parameter reset_type 		 = `RESET_TYPE_ASYNC;
   
`include "srp_format.v"

 
   
   
   localparam [0:port_idx_width-1] default_port_enc= port_id;
   //u-turn port for nacks
   wire [0:num_ports-1] default_port;
   c_decode
     #(// Parameters
       .num_ports			(num_ports))
   default_port_dec
     (// Outputs
      .data_out				(default_port),
      // Inputs
      .data_in				(default_port_enc));
   


   

   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // incoming flit valid
   input 			 flit_valid_in;
   
   // incoming flit is head flit
   input 			 flit_head_in;
   
   // incoming flit is tail
   input 			 flit_tail_in;
   
   // payload data for incoming flitflit_valid
   input [0:flit_data_width-1] 	 flit_data_in;
   
   // internal flow control signalling from output controller to input 
   // controllers
   input [0:num_ports*num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   // destination port (1-hot)
   output [0:num_ports-1] 			     route_op;
   wire [0:num_ports-1] 			     route_op;
   //orginal destiantion
   wire [0:num_ports-1] 			     real_route_op;
   
   // select next resource class
   output [0:num_resource_classes-1] 		     route_orc;
   wire [0:num_resource_classes-1] 		     route_orc;
   
   // VC allocation successful
   input 					     vc_gnt;
   
   // granted output VC
   input [0:num_vcs_per_class-1] 		     vc_gnt_ocvc;
   
   // switch allocator grants
   input 					     sw_gnt;
   
   // did this VC send a flit in the previous cycle?
   input 					     flit_sent_prev;
   
   // if we sent a flit in the previous cycle, was it a tail flit?
   input 					     flit_tail_prev;
   
   // updated lookahead routing info
   // (NOTE: only valid if the current flit is a head flit)
   output [0:lar_info_width-1] 			     next_lar_info;
   wire [0:lar_info_width-1] 			     next_lar_info;
   
   // outgoing flit is available
   output 					     flit_valid;
   wire 					     flit_valid;
   wire real_flit_valid; //internally visible flit_valid
   
   // outgoing flit is head flit
   output 					     flit_head;
   wire 					     flit_head;
   
   // outgoing flit is tail flit
   output 					     flit_tail;
   wire 					     flit_tail;
   wire real_flit_tail; //internally visible tail flit
   
   // destination VC for outgoing flit
   output [0:num_vcs-1] 			     flit_sel_ovc;
   wire [0:num_vcs-1] 				     flit_sel_ovc;
   
   // payload data for outgoing flit
   output [0:flit_data_width-1] 		     flit_data;
   wire [0:flit_data_width-1] 			     flit_data;
   
   // flit buffer does not have any valid entries
   output 					     empty;
   wire 					     empty;
   
   // flit buffer is full
   output 					     full;
   wire 					     full;
   
   // has an output VC been assigned to this input VC?
   output 					     allocated;
   wire 					     allocated;
   wire real_allocated;
   
   
   // credit availability if VC has been assigned
   output 					     free_nonspec;
   wire 					     free_nonspec;
   
   // credit availability if no VC has been assigned yet
   output 					     free_spec;
   wire 					     free_spec;
   
   // internal error condition detected
   output [0:5] 				     errors;
   wire [0:5] 					     errors;

   // causes cross message class vc allocation
   output  expired;
   output [0:num_ports-1] cancel_vc;
   

   //signal credit return
   output drop_event;
   
   reg [0:5] state;
   localparam VC_EMPTY 	= 6'd1;
   localparam VC_WAIT 	= 6'd2;
   localparam SW_WAIT 	= 6'd3;
   localparam SW_HOLD 	= 6'd4;
   localparam VC_NACK 	= 6'd5;
   localparam VC_DROP 	= 6'd6;
   
   
   // time stamp input and output
   wire [0:time_to_wait_width-1] time_to_wait_in;
   wire [0:time_to_wait_width-1] time_to_wait_out;
   //spec source buffer and source
   wire [0:dest_info_width-1] spec_source;
   wire [0:spec_buffer_width-1] spec_buffer_id;
   

   //flit buffer control signals
   wire 					     fbc_empty;

   
   wire 			 header_expired;
   wire                          sw_expired  = header_expired&real_allocated&(state==SW_WAIT);
   


   
   //
   wire drop_body 			     = (state==VC_DROP) & ~fbc_empty;
   assign drop_event 			     = drop_body;
   assign expired 			     = header_expired;

   assign cancel_vc 			     = sw_expired 	    ?
		     real_route_op:
		     {num_ports{1'b0}};
   
   
   


   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   //under vc_drop, forces body flits to be invisibile to the ouside
   assign flit_valid  = (flit_valid_in | ~fbc_empty) & !drop_body;
   assign real_flit_valid  = (flit_valid_in | ~fbc_empty);
   
   wire 					     pop_active;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign pop_active = real_flit_valid | flit_sent_prev;
      else
	assign pop_active = real_flit_valid;
   endgenerate
   
   wire 					     flit_sent;
   wire 					     packet_done;
   assign packet_done = flit_sent & flit_tail;
   
   wire 					     vc_allocated_s, 
						     vc_allocated_q;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign vc_allocated_s
 		    = (vc_allocated_q&~sw_expired & ~(flit_sent_prev & flit_tail_prev)) | vc_gnt;
      else
	assign vc_allocated_s  = ((vc_allocated_q&~|cancel_vc) | vc_gnt) & ~packet_done;
   endgenerate
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocatedq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(vc_allocated_s),
      .q(vc_allocated_q));


   //TODO how does this affect the outside, when vc is cancelled
   assign real_allocated  = vc_allocated_q;
   assign allocated 	  = vc_allocated_q &~sw_expired;
   
   wire [0:num_vcs_per_class-1] 		     vc_allocated_ocvc;
   wire [0:num_vcs_per_class-1] 		     vc_allocated_next_ocvc;
   wire [0:num_vcs_per_class-1] 		     allocated_ocvc;
   
   generate
      
      //if(num_vcs_per_class 		  == 1)
      //begin
      assign vc_allocated_next_ocvc  = 1'b1;
      assign vc_allocated_ocvc 	  = 1'b1;
      /*
	end
       if(num_vcs_per_class > 1)
       begin
       
       assign vc_allocated_next_ocvc
       = vc_allocated_q ? vc_allocated_ocvc : vc_gnt_ocvc;
       
       wire [0:num_vcs_per_class-1] vc_allocated_ocvc_s;
       wire [0:num_vcs_per_class-1] vc_allocated_ocvc_q;
       assign vc_allocated_ocvc_s = vc_allocated_next_ocvc;
       c_dff
       #(.width(num_vcs_per_class),
       .reset_type(reset_type))
       vc_allocated_ocvcq
       (.clk(clk),
       .reset(reset),
       .active(pop_active),
       .d(vc_allocated_ocvc_s),
       .q(vc_allocated_ocvc_q));
       
       assign vc_allocated_ocvc = vc_allocated_ocvc_q;
       
	end
       */
      /*
       if(sw_alloc_spec)
       begin
       if(elig_mask == `ELIG_MASK_NONE)
       assign flit_sent
       = sw_gnt & ((vc_gnt & free_spec) | vc_allocated_q);
       else
       assign flit_sent = sw_gnt & (vc_gnt | vc_allocated_q);
       
       assign allocated_ocvc = vc_allocated_next_ocvc;
	end
       else
       begin*/
      assign flit_sent = sw_gnt;      
      assign allocated_ocvc = vc_allocated_ocvc;
      //end
   endgenerate


   
   wire [0:num_resource_classes*num_vcs_per_class-1] allocated_orc_ocvc;
   c_mat_mult
     #(.dim1_width(num_resource_classes),
       .dim2_width(1),
       .dim3_width(num_vcs_per_class),
       .prod_op(`BINARY_OP_AND),
       .sum_op(`BINARY_OP_OR))
   allocated_orc_ocvc_mmult
     (.input_a(route_orc),
      .input_b(allocated_ocvc),
      .result(allocated_orc_ocvc));


   //hard coded for 1vc/class SRP
   assign flit_sel_ovc 	= {1'b0,header_expired,1'b0,~header_expired};
   
   
   //---------------------------------------------------------------------------
   // flit buffer control
   //---------------------------------------------------------------------------
   
   wire 					     push_active;
   assign push_active = flit_valid_in;
   
   wire 					     fbc_push;
   assign fbc_push = flit_valid_in;
   
   wire 					     fbc_pop;
   assign fbc_pop = flit_sent | drop_body;
   
   wire [0:fb_addr_width-1] 			     fbc_push_addr;
   wire [0:fb_addr_width-1] 			     fbc_pop_addr;
   wire 					     fbc_almost_empty;
   wire 					     fbc_almost_full;
   wire 					     fbc_full;
   wire [0:1] 					     fbc_errors;
   c_fifo_ctrl
     #(.depth(num_flits_per_vc),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push_active(push_active),
      .pop_active(pop_active),
      .push(fbc_push),
      .pop(fbc_pop),
      .push_addr(fbc_push_addr),
      .pop_addr(fbc_pop_addr),
      .almost_empty(fbc_almost_empty),
      .empty(fbc_empty),
      .almost_full(fbc_almost_full),
      .full(fbc_full),
      .errors(fbc_errors));
   
   assign empty = fbc_empty;
   assign full = fbc_full;
   
   wire 					     error_fbc_underflow;
   assign error_fbc_underflow = fbc_errors[0];
   
   wire 					     error_fbc_overflow;
   assign error_fbc_overflow = fbc_errors[1];
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire 					     fbf_write_enable;
   wire [0:fb_addr_width-1] 			     fbf_read_addr;
   
   generate
      
      if(explicit_pipeline_register)
	begin
	   
	   if(gate_buffer_write)
	     assign fbf_write_enable
               = flit_valid_in & ~(fbc_empty & (flit_sent|drop_body));
	   else
	     assign fbf_write_enable = flit_valid_in;
	   
	   assign fbf_read_addr = fbc_pop_addr;
	   
	end
      else
	begin
	   
	   assign fbf_write_enable = flit_valid_in;
	   
	   wire [0:fb_addr_width-1] fbf_read_addr_s, fbf_read_addr_q;
	   assign fbf_read_addr_s = fbc_pop_addr;
	   c_dff
	     #(.width(fb_addr_width),
               .reset_type(reset_type))
	   fbf_read_addrq
	     (.clk(clk),
              .reset(1'b0),
              .active(pop_active),
              .d(fbf_read_addr_s),
              .q(fbf_read_addr_q));
	   
	   assign fbf_read_addr = fbf_read_addr_q;
	   
	end
      
   endgenerate
   
   wire [0:flit_data_width-1] 	     fbf_write_data;
   assign fbf_write_data = flit_data_in;
   
   wire [0:flit_data_width-1] 	     fbf_read_data;
   wire [0:flit_data_width-1] 	     fbf_peek_data;

   generate

      if(elig_mask == `ELIG_MASK_USED)
	begin
	   
	   c_regfile
		    #(.depth(num_flits_per_vc),
		      .width(flit_data_width),
		      .regfile_type(fb_regfile_type))
	   fbf
		    (.clk(clk),
		     .write_active(push_active),
		     .write_enable(fbf_write_enable),
		     .write_address(fbc_push_addr),
		     .write_data(fbf_write_data),
		     .read_address(fbf_read_addr),
		     .read_data(fbf_read_data));
	   
	   assign fbf_peek_data = {flit_data_width{1'b0}};
	   
	end
      else
	begin
	   
	   wire [0:fb_addr_width-1] fbf_peek_addr;
	   c_incr
	     #(.width(fb_addr_width),
               .max_value(num_flits_per_vc - 1))
	   fbf_peek_addr_incr
	     (.data_in(fbc_pop_addr),
              .data_out(fbf_peek_addr));
	   
	   c_regfile
	     #(.depth(num_flits_per_vc),
               .width(flit_data_width),
               .num_read_ports(2),
               .regfile_type(fb_regfile_type))
	   fbf
	     (.clk(clk),
              .write_active(push_active),
              .write_enable(fbf_write_enable),
              .write_address(fbc_push_addr),
              .write_data(fbf_write_data),
              .read_address({fbf_read_addr, fbf_peek_addr}),
              .read_data({fbf_read_data, fbf_peek_data}));

	end
   endgenerate
   
   wire [0:flit_data_width-1] fbf_flit_data;
   assign fbf_flit_data = fbf_read_data;
   
   wire [0:header_info_width-1] peek_header_info;
   assign peek_header_info = fbf_peek_data[0:header_info_width-1];
   
   wire [0:route_info_width-1] 	peek_route_info;
   assign peek_route_info = peek_header_info[0:route_info_width-1];
   

   
   //---------------------------------------------------------------------------
   // generate head and tail indicators
   //---------------------------------------------------------------------------
   
   wire 			fb_flit_tail;
   
   generate
      
      if(elig_mask == `ELIG_MASK_USED)
	begin
	   
	   wire has_tail_s, has_tail_q;
	   assign has_tail_s = (has_tail_q & ~(flit_valid_in & flit_head_in)) | 
			       (flit_valid_in & flit_tail_in);
	   c_dff
	     #(.width(1),
               .reset_type(reset_type))
	   has_tailq
	     (.clk(clk),
              .reset(reset),
              .active(push_active),
              .d(has_tail_s),
              .q(has_tail_q));
	   
	   assign fb_flit_tail = fbc_almost_empty & has_tail_q;
	   
	end
      else
	begin
	   
	   wire [0:num_flits_per_vc-1] push_mask;
	   c_decode
	     #(.num_ports(num_flits_per_vc))
	   push_addr_dec
	     (.data_in(fbc_push_addr),
              .data_out(push_mask));
	   
	   wire [0:num_flits_per_vc-1] flit_tail_s, flit_tail_q;
	   assign flit_tail_s
	     = fbf_write_enable ? 
               ({num_flits_per_vc{flit_tail_in}} & push_mask) | 
               (flit_tail_q & ~push_mask) :
               flit_tail_q;
	   c_dff
	     #(.width(num_flits_per_vc),
               .reset_type(reset_type))
	   flit_tailq
	     (.clk(clk),
              .reset(1'b0),
              .active(push_active),
              .d(flit_tail_s),
              .q(flit_tail_q));
	   
	   assign fb_flit_tail 	= flit_tail_q[fbc_pop_addr];
	   
	end
      
   endgenerate
   
   //under vc_nack, forces the head flit to also be body flit
   assign flit_tail 		= (fbc_empty ? flit_tail_in : fb_flit_tail)|header_expired;
   assign real_flit_tail 	= (fbc_empty ? flit_tail_in : fb_flit_tail);
   wire 			     htr_flit_head_s, htr_flit_head_q;
   
   assign htr_flit_head_s = flit_sent ? flit_tail : htr_flit_head_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type),
       .reset_value(1'b1))
   htr_flit_headq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(htr_flit_head_s),
      .q(htr_flit_head_q));
   
   assign flit_head = fbc_empty ? flit_head_in : htr_flit_head_q;
   
   
   //---------------------------------------------------------------------------
   // head register
   //---------------------------------------------------------------------------
   
   wire 			     hdr_valid_s, hdr_valid_q;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_valid_s
 			    = (hdr_valid_q & ~(flit_sent_prev & flit_tail_prev)) | (flit_valid_in);
      
      else
	assign hdr_valid_s
 	  = (flit_sent| drop_body) ?
	    (fbc_empty ? 
	     ~flit_tail_in : 
	     (~fb_flit_tail | ~fbc_almost_empty | flit_valid_in)) : 
	    (hdr_valid_q | flit_valid_in);
   endgenerate
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   hdf_validq
     (.clk(clk),
      .reset(reset),
      .active(pop_active),
      .d(hdr_valid_s),
      .q(hdr_valid_q));
   
   wire [0:header_info_width-1]      header_info_in;
   assign header_info_in = flit_data_in[0:header_info_width-1];
   
   wire [0:route_info_width-1] 	     route_info_in;
   assign route_info_in = header_info_in[0:route_info_width-1];
   
   wire [0:lar_info_width-1]    lar_info_in;
   assign lar_info_in = route_info_in[0:lar_info_width-1];
   
   wire [0:dest_info_width-1] 	     dest_info_in;
   assign dest_info_in = route_info_in[lar_info_width+:dest_info_width];
   
   wire [0:dest_info_width-1] 	     src_info_in;
   assign src_info_in = flit_data_in[spec_src_start+:dest_info_width];
   
   
   wire 			     hdr_active;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_active = ~hdr_valid_q & flit_valid_in;
      else
	// NOTE: If this ends up being timing-critical, we can simply eliminate 
	// the fb_flit_tail term at the expense of slightly worse gating under 
	// load.
	// For relatively short packets, this is probably a good tradeoff.
	assign hdr_active
	  = (~hdr_valid_q & flit_valid_in) | (~fbc_empty & fb_flit_tail);
   endgenerate
   
   wire 			     two_plus_flits;
   assign two_plus_flits = ~fbc_empty & ~fbc_almost_empty;
   
   wire [0:lar_info_width-1] 	     hdr_lar_info_s, hdr_lar_info_q;
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_lar_info_s = hdr_valid_q ? hdr_lar_info_q : lar_info_in;
      else
	begin
	   
	   wire [0:lar_info_width-1] peek_lar_info;
	   assign peek_lar_info = peek_route_info[0:lar_info_width-1];
	   
	   assign hdr_lar_info_s
	     = (~hdr_valid_q | packet_done | (drop_body & flit_tail) ) ? 
               (two_plus_flits ? peek_lar_info : lar_info_in) : 
               hdr_lar_info_q;
	   
	end
   endgenerate
   c_dff
     #(.width(lar_info_width),
       .reset_type(reset_type))
   hdr_lar_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_lar_info_s),
      .q(hdr_lar_info_q));
   


   // included hdr_src_info in case header is expired (replace dest_info with src_info)
   wire [0:dest_info_width-1] 	     hdr_src_info_s, hdr_src_info_q;

   
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_src_info_s = hdr_valid_q ? hdr_src_info_q : src_info_in;
      else
	begin
	   
	   wire [0:dest_info_width-1] peek_src_info;
	   assign peek_src_info
	     = fbf_peek_data[spec_src_start+:dest_info_width];
	   
	   assign hdr_src_info_s
	     = (~hdr_valid_q | packet_done | (drop_body & flit_tail)) ?
               (two_plus_flits ? peek_src_info : src_info_in) :
               hdr_src_info_q;
	   
	end
   endgenerate
   c_dff
     #(.width(dest_info_width),
       .reset_type(reset_type))
   hdr_src_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_src_info_s),
      .q(hdr_src_info_q));





   wire [0:dest_info_width-1] 	     hdr_dest_info_s, hdr_dest_info_q; 	     
   
   generate
      if(elig_mask == `ELIG_MASK_USED)
	assign hdr_dest_info_s = hdr_valid_q ? hdr_dest_info_q : dest_info_in;
      else
	begin
	   
	   wire [0:dest_info_width-1] peek_dest_info;
	   assign peek_dest_info
	     = peek_route_info[lar_info_width:lar_info_width+dest_info_width-1];
	   
	   assign hdr_dest_info_s
	     = (~hdr_valid_q | packet_done | (drop_body & flit_tail)) ?
               (two_plus_flits ? peek_dest_info : dest_info_in) :
               hdr_dest_info_q;
	   
	end
   endgenerate
   c_dff
     #(.width(dest_info_width),
       .reset_type(reset_type))
   hdr_dest_infoq
     (.clk(clk),
      .reset(1'b0),
      .active(hdr_active),
      .d(hdr_dest_info_s),
      .q(hdr_dest_info_q));
   
   wire 			     error_no_header;
   assign error_no_header
     = ~hdr_valid_q & (~fbc_empty | (flit_valid_in & ~flit_head_in));
   
   
   //---------------------------------------------------------------------------
   // decode lookahead routing information
   //---------------------------------------------------------------------------
   
   wire [0:port_idx_width-1] 			     route_port_in;
   assign route_port_in     = lar_info_in[0:port_idx_width-1];

   // TODO: change route_port_in based on whether or not the header is expired




   
   
   
   wire [0:num_ports-1] 			     route_in_op;
   c_decode
     #(.num_ports(num_ports))
   route_in_op_dec
     (.data_in(route_port_in),
      .data_out(route_in_op));
   
   wire [0:port_idx_width-1] 			     hdr_route_port;
   assign hdr_route_port = hdr_lar_info_q[0:port_idx_width-1];
   
   wire [0:num_ports-1] 			     hdr_route_op;
   c_decode
     #(.num_ports(num_ports))
   hdr_route_op_dec
     (.data_in(hdr_route_port),
      .data_out(hdr_route_op));

   assign real_route_op  = (hdr_valid_q ? hdr_route_op : route_in_op);
   wire [0:num_ports-1] 			     route_unmasked_op;
   assign route_unmasked_op = header_expired?default_port:real_route_op;
   
   wire [0:num_resource_classes-1] 		     route_unmasked_orc;

   /*
    generate
    if(num_resource_classes == 1)
    */
   assign route_unmasked_orc  = 1'b1;
   /*
    else if(num_resource_classes > 1)
    begin
    
    wire [0:resource_class_idx_width-1] route_rcsel_in;
    assign route_rcsel_in
    = lar_info_in[port_idx_width:
    port_idx_width+resource_class_idx_width-1];
    
    wire [0:num_resource_classes-1]     route_in_orc;
    c_decode
    #(.num_ports(num_resource_classes))
    route_in_orc_dec
    (.data_in(route_rcsel_in),
    .data_out(route_in_orc));
    
    wire [0:resource_class_idx_width-1] hdr_route_rcsel;
    assign hdr_route_rcsel
    = hdr_lar_info_q[port_idx_width:
    port_idx_width+resource_class_idx_width-1];
    
    wire [0:num_resource_classes-1]     hdr_route_orc;
    c_decode
    #(.num_ports(num_resource_classes))
    hdr_route_orc_dec
    (.data_in(hdr_route_rcsel),
    .data_out(hdr_route_orc));
    
    assign route_unmasked_orc
    = hdr_valid_q ? hdr_route_orc : route_in_orc;
    
	end
    
   endgenerate
    */
   
   wire 				       header_valid;
   assign header_valid 	= hdr_valid_q | flit_valid_in;
   assign route_op 	= route_unmasked_op;
   assign route_orc = route_unmasked_orc;
   
   //---------------------------------------------------------------------------
   // update lookahead routing information for next hop
   //---------------------------------------------------------------------------
   wire [0:dest_info_width-1] 		       dest_info, original_dest_info;
   wire [0:dest_info_width-1] 		       src_info;

   assign original_dest_info  = hdr_valid_q ? hdr_dest_info_q : dest_info_in;
   assign src_info 	      = hdr_valid_q ? hdr_src_info_q : src_info_in;
   
   assign dest_info 	      = header_expired ? src_info: original_dest_info;

   //CAUTION, assuming number of resource classes is 1
   wire [0:lar_info_width-1] 	       lar_info;
   assign lar_info =header_expired?default_port_enc:(hdr_valid_q ? hdr_lar_info_q : lar_info_in);
   

   wire [0:router_addr_width-1] 	       next_router_address;

   rtr_next_hop_addr
     #(.num_resource_classes(num_resource_classes),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type))
   nha
     (.router_address(router_address),
      .dest_info(dest_info),
      .lar_info(lar_info),
      .next_router_address(next_router_address));
   
   wire [0:num_message_classes-1] 	       sel_mc;
   c_align
     #(.in_width(1),
       .out_width(num_message_classes),
       .offset(message_class))
   sel_mc_agn
     (.data_in(1'b1),
      .dest_in({num_message_classes{1'b0}}),
      .data_out(sel_mc));
   
   wire [0:num_ports-1] 		       next_route_op;
   wire [0:num_resource_classes-1] 	       next_route_orc;
   rtr_routing_logic
     #(.num_message_classes(num_message_classes),
       .num_resource_classes(num_resource_classes),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order))
   rtl
     (.router_address(next_router_address),
      .sel_mc(sel_mc),
      .sel_irc(route_orc),
      .dest_info(dest_info),
      .route_op(next_route_op),
      .route_orc(next_route_orc));
   
   wire [0:port_idx_width-1] 		       next_route_port;
   c_encode
     #(.num_ports(num_ports))
   next_route_port_enc
     (.data_in(next_route_op),
      .data_out(next_route_port));
   
   assign next_lar_info[0:port_idx_width-1] = next_route_port;
   
   generate
      
      if(num_resource_classes > 1)
	begin
	   
	   wire [0:resource_class_idx_width-1] next_route_rcsel;
	   c_encode
	     #(.num_ports(num_resource_classes))
	   next_route_rcsel_enc
	     (.data_in(next_route_orc),
              .data_out(next_route_rcsel));
	   
	   assign next_lar_info[port_idx_width:
				port_idx_width+resource_class_idx_width-1]
	     = next_route_rcsel;
	   
	end
      
   endgenerate


   
   //---------------------------------------------------------------------------
   // credit tracking
   //---------------------------------------------------------------------------
   
   wire 				       cred_track_active;
   assign cred_track_active = flit_valid | vc_allocated_q;
   
   wire [0:num_vcs*int_flow_ctrl_width-1]      int_flow_ctrl_ovc;
   c_select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs*int_flow_ctrl_width))
   int_flow_ctrl_ovc_sel
     (.select(route_op),
      .data_in(int_flow_ctrl_op_ovc),
      .data_out(int_flow_ctrl_ovc));
   
   wire [0:num_resource_classes*num_vcs_per_class*
	 int_flow_ctrl_width-1] 	       int_flow_ctrl_orc_ocvc;

   //assume SRP vc only handles message class one and three, credit selected by expired   
   assign int_flow_ctrl_orc_ocvc  = header_expired?
				    int_flow_ctrl_ovc[1*
						      num_resource_classes*
						      num_vcs_per_class*
						      int_flow_ctrl_width:
						      (1+1)*
						      num_resource_classes*
						      num_vcs_per_class*
						      int_flow_ctrl_width-1]:
				    int_flow_ctrl_ovc[message_class*
						      num_resource_classes*
						      num_vcs_per_class*
						      int_flow_ctrl_width:
						      (message_class+1)*
						      num_resource_classes*
						      num_vcs_per_class*
						      int_flow_ctrl_width-1];
   
   wire [0:num_vcs_per_class*int_flow_ctrl_width-1] int_flow_ctrl_ocvc;
   wire 					    error_ct_overflow;
   
   generate
      
      if(num_resource_classes == 1)
	assign int_flow_ctrl_ocvc = int_flow_ctrl_orc_ocvc;
      else if(num_resource_classes > 1)
	begin
	   c_select_1ofn
	     #(.num_ports(num_resource_classes),
               .width(num_vcs_per_class*int_flow_ctrl_width))
	   int_flow_ctrl_ocvc_sel
	     (.select(route_orc),
              .data_in(int_flow_ctrl_orc_ocvc),
              .data_out(int_flow_ctrl_ocvc));
	end
      
      case(int_flow_ctrl_type)
	
	// the current number of credits available are transmitted from the 
	// output controllers as a multi-level signal (0, 1, 2 or 3+ credits
	// currently available)
	`INT_FLOW_CTRL_TYPE_LEVEL:
	  begin
	     
	     wire [0:num_vcs_per_class-1]   next_free_ocvc;
	     wire [0:num_vcs_per_class-1]   free_spec_ocvc;
	     
	     genvar 			    ocvc;
	     
	     for(ocvc = 0; ocvc < num_vcs_per_class; ocvc = ocvc + 1)
               begin:ocvcs
		  
		  wire [0:1] int_flow_ctrl;
		  assign int_flow_ctrl
		    = int_flow_ctrl_ocvc[ocvc*2:(ocvc+1)*2-1];
		  
		  wire 	     two_or_more_credits;
		  assign two_or_more_credits
		    = int_flow_ctrl[0] & (int_flow_ctrl[1] | ~flit_sent_prev);
		  
		  wire 	     one_or_more_credits;
		  assign one_or_more_credits
		    = int_flow_ctrl[0] | (int_flow_ctrl[1] & ~flit_sent_prev);
		  
		  wire 	     next_free;
		  assign next_free
		    = (flit_sent|drop_body) ? two_or_more_credits : one_or_more_credits;
		  
		  assign next_free_ocvc[ocvc] = next_free;
		  
		  // NOTE: When sending the first flit in each packet, we must 
		  // have won VC allocation. Consequently, the destination 
		  // output VC must have been eligible and thus not assigned to 
		  // any input VC, so we know that nobody sent a flit to it in 
		  // the previous cycle.
		  
		  wire 	     free_spec;
		  assign free_spec = |int_flow_ctrl;
		  
		  assign free_spec_ocvc[ocvc] = free_spec;
		  
               end
	     
	     wire 	     free_nonspec_s, free_nonspec_q;
	     assign free_nonspec_s = |(next_free_ocvc & vc_allocated_next_ocvc);
	     c_dff
               #(.width(1),
		 .reset_value(1'b1),
		 .reset_type(reset_type))
	     free_nonspecq
               (.clk(clk),
		.reset(reset),
		.active(cred_track_active),
		.d(free_nonspec_s),
		.q(free_nonspec_q));
	     
	     assign free_nonspec = free_nonspec_q;
	     
	     if(num_vcs_per_class == 1)
               assign free_spec = free_spec_ocvc;
	     else if(num_vcs_per_class > 1)
               assign free_spec = |(free_spec_ocvc & vc_gnt_ocvc);
	     
	     assign error_ct_overflow = 1'b0;
	     
	  end
	
	// credits are forwarded from the output controllers individually as 
	// pulses, accumulated at the input controllers, and used whenever a
	// flit is sent to the crossbar
	`INT_FLOW_CTRL_TYPE_PUSH:
	  begin
	     
	     wire [0:num_vcs_per_class-1] cred_ocvc;
	     assign cred_ocvc = int_flow_ctrl_ocvc;
	     
	     wire 			  cred_allocated;
	     assign cred_allocated = |(cred_ocvc & vc_allocated_ocvc);
	     
	     wire 			  cred_unallocated;
	     
	     if(num_vcs_per_class == 1)
               assign cred_unallocated = cred_ocvc;
	     else
               assign cred_unallocated = |(cred_ocvc & vc_gnt_ocvc);
	     
	     wire [0:cred_hold_width-1]   cred_hold_q;
	     
	     wire 			  has_cred_s, has_cred_q;
	     if(elig_mask == `ELIG_MASK_NONE)
               assign has_cred_s
			   = vc_allocated_q ?
			   ((has_cred_q & ~sw_gnt) | (|cred_hold_q) | cred_allocated) :
			   (~sw_gnt & cred_unallocated);
	     else
               assign has_cred_s 
		 = vc_allocated_q ? 
		   ((has_cred_q & ~sw_gnt) | (|cred_hold_q) | cred_allocated) :
		   (~sw_gnt | cred_unallocated);
	     c_dff
               #(.width(1),
		 .reset_type(reset_type))
	     has_credq
               (.clk(clk),
		.reset(reset),
		.active(cred_track_active),
		.d(has_cred_s),
		.q(has_cred_q));
	     
	     assign free_nonspec = has_cred_q;
	     
	     assign free_spec = cred_unallocated;
	     
	     wire 			  incr_cred_hold;
	     assign incr_cred_hold = cred_allocated & has_cred_q & ~sw_gnt;
	     
	     wire 			  decr_cred_hold;
	     assign decr_cred_hold = ~cred_allocated & |cred_hold_q & sw_gnt;
	     
	     wire [0:cred_hold_width-1]   cred_hold_new;
	     if(elig_mask == `ELIG_MASK_NONE)
               assign cred_hold_new = {cred_hold_width{1'b0}};
	     else
               assign cred_hold_new = cred_unallocated & ~sw_gnt;
	     
	     wire [0:cred_hold_width-1]   cred_hold_s;
	     assign cred_hold_s
               = vc_allocated_q ?
		 (cred_hold_q + incr_cred_hold - decr_cred_hold) :
		 cred_hold_new;
	     c_dff
               #(.width(cred_hold_width),
		 .reset_type(reset_type))
	     cred_holdq
               (.clk(clk),
		.reset(reset),
		.active(cred_track_active),
		.d(cred_hold_s),
		.q(cred_hold_q));
	     
	     assign error_ct_overflow
               = vc_allocated_q && (cred_hold_q == num_flits_per_vc-1) &&
		 incr_cred_hold;
	     
	  end
      endcase
   endgenerate
   
   //---------------------------------------------------------------------------
   // TTW counter
   //---------------------------------------------------------------------------
   
   wire [0:counter_width-1] ttw_counter_d;
   wire [0:counter_width-1] ttw_counter_q;
   
   assign ttw_counter_d = ttw_counter_q + 1'b1;
   
   c_dff
     #(.width(counter_width),
       .reset_type(reset_type))
   counter
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .d(ttw_counter_d),
      .q(ttw_counter_q));
   
   
   
   //---------------------------------------------------------------------------
   // timestamp buffer control
   //---------------------------------------------------------------------------
   wire 					     tbc_empty;
   
   
   wire 					     tbc_push_active;
   assign tbc_push_active = flit_valid_in & flit_head_in;
   
   wire 					     tbc_push;
   assign tbc_push = flit_valid_in & flit_head_in;
   
   wire 					     tbc_pop;
   assign tbc_pop = flit_sent & flit_head;
   
   
   // pop active for flit queue was an input
   wire tbc_pop_active;
   assign tbc_pop_active = flit_sent & flit_head;
   
   wire [0:fb_addr_width-1] 			     tbc_push_addr;
   wire [0:fb_addr_width-1] 			     tbc_pop_addr;
   wire 					     tbc_almost_empty;
   wire 					     tbc_almost_full;
   wire 					     tbc_full;
   wire [0:1] 					     tbc_errors;
   c_fifo_ctrl
     #(.depth(num_flits_per_vc),
       .reset_type(reset_type))
   tbc
     (.clk(clk),
      .reset(reset),
      .push_active(tbc_push_active),
      .pop_active(tbc_pop_active),
      .push(tbc_push),
      .pop(tbc_pop),
      .push_addr(tbc_push_addr),
      .pop_addr(tbc_pop_addr),
      .almost_empty(tbc_almost_empty),
      .empty(tbc_empty),
      .almost_full(tbc_almost_full),
      .full(tbc_full),
      .errors(tbc_errors));
   
   //assign tb_empty = tbc_empty;
   //assign tb_full = tbc_full;
   
   wire 					     error_tbc_underflow;
   assign error_tbc_underflow = tbc_errors[0];
   
   wire 					     error_tbc_overflow;
   assign error_tbc_overflow = tbc_errors[1];
   
   
   //---------------------------------------------------------------------------
   // time stamp buffer
   //---------------------------------------------------------------------------
   
   wire 					     tbf_write_enable;
   wire [0:fb_addr_width-1] 			     tbf_read_addr;
   
   generate
      
      if(explicit_pipeline_register)
	begin
           if(gate_buffer_write)
             assign tbf_write_enable
               = flit_head_in & flit_valid_in & ~(fbc_empty & flit_sent);
           else
             assign tbf_write_enable = flit_valid_in & flit_head_in;
           assign tbf_read_addr = tbc_pop_addr;
        end
      else
	begin
           assign tbf_write_enable = flit_head_in & flit_valid_in;
           wire [0:fb_addr_width-1] tbf_read_addr_s, tbf_read_addr_q;
           assign tbf_read_addr_s = tbc_pop_addr;
           c_dff
             #(.width(fb_addr_width),
               .reset_type(reset_type))
           tbf_read_addrqs
             (.clk(clk),
              .reset(reset),
              .active(tbc_pop_active),
              .d(tbf_read_addr_s),
              .q(tbf_read_addr_q));
           assign tbf_read_addr = tbf_read_addr_q;
	end
   endgenerate
   
   
   wire [0:time_to_wait_width-1] coarse_counter;
   assign coarse_counter = ttw_counter_q[0:time_to_wait_width-1]; 
   
   wire [0:time_to_wait_width-1] 	     tbf_write_data;
   assign tbf_write_data = coarse_counter;
   
   wire [0:time_to_wait_width-1] 	     tbf_read_data;
   wire [0:time_to_wait_width-1] 	     tbf_peek_data;
   
   generate
      
      if(elig_mask == `ELIG_MASK_USED)
	begin
           
           c_regfile
		    #(.depth(num_flits_per_vc),
		      .width(time_to_wait_width),
		      .regfile_type(fb_regfile_type))  // may need to change this
           tbf
		    (.clk(clk),
		     .write_active(tbc_push_active),
		     .write_enable(tbf_write_enable),
		     .write_address(tbc_push_addr),
		     .write_data(tbf_write_data),
		     .read_address(tbf_read_addr),
		     .read_data(tbf_read_data));
           
           assign tbf_peek_data = {8{1'b0}};
           
	end
      else
	begin
           
           wire [0:fb_addr_width-1] tbf_peek_addr;
           c_incr
             #(.width(fb_addr_width),
               .max_value(num_flits_per_vc - 1))
           tbf_peek_addr_incr
             (.data_in(tbc_pop_addr),
              .data_out(tbf_peek_addr));
           
           c_regfile
             #(.depth(num_flits_per_vc),
               .width(time_to_wait_width),
               .num_read_ports(2),
               .regfile_type(fb_regfile_type))  // may need to change this
           tbf
             (.clk(clk),
              .write_active(tbc_push_active),
              .write_enable(tbf_write_enable),
              .write_address(tbc_push_addr),
              .write_data(tbf_write_data),
              .read_address({tbf_read_addr, tbf_peek_addr}),
              .read_data({tbf_read_data, tbf_peek_data}));
	   
	end
   endgenerate
   

   
   //---------------------------------------------------------------------------
   // check if header is expired
   //---------------------------------------------------------------------------

   wire [0:flit_data_width-1] flit_data_old;
   wire flit_head_valid;
   wire flit_head_q;

   generate
      if(explicit_pipeline_register)
	assign flit_head_valid 	= ~tbc_empty & flit_head;
      else
	assign flit_head_valid 	= ~tbc_empty & flit_head_q;
   endgenerate
   
   assign time_to_wait_in 	= flit_data_old[spec_ttw_start+:time_to_wait_width];
   assign spec_buffer_id 	= flit_data_old[spec_id_start+:spec_buffer_width];
   assign spec_source		=flit_data_old[spec_src_start+:dest_info_width];
   
   //[header_info_width - time_to_wait_width:
   //header_info_width-1];
   
   wire [0:time_to_wait_width-1] time_diff;
   
   wire [0:time_to_wait_width-1] time_to_wait_in_q;
   
   assign time_diff 		      = coarse_counter - tbf_read_data;
   
   
   assign time_to_wait_out 	      = header_expired ? 8'b0 : flit_head_valid ? (time_to_wait_in - time_diff) : time_to_wait_in;

   
   assign header_expired 	      = ((time_diff >= time_to_wait_in) & flit_head_valid) | (state==VC_NACK);
 
   
   
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   dff_ttw_in
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .d(flit_head),
      .q(flit_head_q));
   
   
   
   //---------------------------------------------------------------------------
   // generate output data
   //---------------------------------------------------------------------------
   generate      
      if(explicit_pipeline_register) begin
	 assign flit_data_old  = empty ? flit_data_in : fbf_flit_data;
      end else begin
	 assign flit_data_old  = fbf_flit_data;
      end                          
   endgenerate

   //CAUTION hardcoded single flit NACK
   
   wire [0:flit_data_width-1] nack_packet= {next_lar_info,		    
					    spec_source,
					    {payload_length_width{1'b0}},
					    2'b10,
					    spec_buffer_id,
					    flit_data_old[nack_data_start:flit_data_width-1]};
   
   
   assign flit_data =header_expired?
		     nack_packet:
		     (flit_head_valid ?
		      {flit_data_old[0:spec_ttw_start-1],
		       time_to_wait_out,
		       flit_data_old[spec_id_start:flit_data_width-1]}:
	 	      flit_data_old);
   assign tbf_write_enable = flit_head_in & flit_valid_in;
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   always @(posedge clk)
     begin
	if(error_no_header)
	  $display("ERROR: Stray flit received in module %m.");
	
	if(error_ct_overflow)
	  $display("ERROR: Credit tracker overflow in module %m.");
	if(drop_body&fbc_empty)
	  $display("ERROR: dropping from empty buffer %m.");
     end
   
   // synopsys translate_on
   assign errors[0]  = error_fbc_underflow;
   assign errors[1]  = error_fbc_overflow;
   assign errors[2]  = error_no_header;
   assign errors[3]  = error_ct_overflow;
   assign errors[4]  = 1'b0; //error_invalid_port;
   assign errors[5]  = 1'b0; //error_invalid_class;

   
   

   //SRP FSM
   //thsi only works with explicit reg right now
   always@(posedge clk, posedge reset)
     begin
	if(reset)
	  state     <=VC_WAIT;
	else
	  begin
	     case(state)
	       VC_EMPTY: //is this state necessary?
		 state <=VC_WAIT;
	       VC_WAIT:
		 if(header_expired)
		   state <=VC_NACK;
		 else if(vc_gnt)
		   state <=SW_WAIT;
		 else
		   state <=VC_WAIT;
	       SW_WAIT:
		 if(sw_expired)
		   state <=VC_NACK;
		 else if(sw_gnt & ~flit_tail)
		   state <=SW_HOLD;
		 else if(sw_gnt & flit_tail)
		   state <=VC_WAIT;
		 else
		   state <=SW_WAIT;
	       SW_HOLD:
		 if(sw_gnt & flit_tail)
		   state <=VC_WAIT;
	       	 else
		   state <=SW_HOLD;
	       VC_NACK:
		 if(sw_gnt & ~real_flit_tail)
		   state <=VC_DROP; //multi-flit
		 else if(sw_gnt & real_flit_tail)
		   state <=VC_WAIT; //single flit
	       	 else
		   state <=VC_NACK;
	       VC_DROP:
		 if(real_flit_tail & drop_body)
		   state <=VC_WAIT;
		 else  
		   state <=VC_DROP;
	       default:
		 state <=VC_WAIT;
	     endcase // case (state)
	  end // else: !if(reset)	
     end // always@ (posedge clk, posedge reset)
   /*
    always @(posedge clk)
    begin
    if(state==VC_DROP)
    $display("ERROR: Stray flit in module %m.");
     end
    */
endmodule