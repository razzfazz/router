// $Id$

/*
Copyright (c) 2007-2010, Trustees of Leland Stanford Junior University
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

//==============================================================================
// switch allocator for VC router
//==============================================================================

module vcr_sw_alloc_mac
  (clk, reset, route_ip_ivc_op, allocated_ip_ivc, flit_valid_ip_ivc, 
   free_nonspec_ip_ivc, sel_ip_ivc, gnt_ip, xbr_ctrl_op_ip);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // select implementation variant for switch allocator
   parameter allocator_type = `SW_ALLOC_TYPE_SEP_IF;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type
   parameter spec_type = `SW_ALLOC_SPEC_TYPE_REQ;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // VC has output VC allocated to it
   input [0:num_ports*num_vcs-1] 	   allocated_ip_ivc;
   
   // VC has flit available
   input [0:num_ports*num_vcs-1] 	   flit_valid_ip_ivc;
   
   // credit availability if output VC has been allocated
   input [0:num_ports*num_vcs-1] 	   free_nonspec_ip_ivc;
   
   // indicate which VC at a given port is granted
   output [0:num_ports*num_vcs-1] 	   sel_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_ip_ivc;
   
   // port grants
   output [0:num_ports-1] 		   gnt_ip;
   wire [0:num_ports-1] 		   gnt_ip;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] 	   xbr_ctrl_op_ip;
   wire [0:num_ports*num_ports-1] 	   xbr_ctrl_op_ip;
   
   wire [0:num_ports*num_vcs-1] 	   req_nonspec_ip_ivc;
   assign req_nonspec_ip_ivc
     = allocated_ip_ivc & flit_valid_ip_ivc & free_nonspec_ip_ivc;
   
   wire [0:num_ports*num_vcs-1] 	   req_spec_ip_ivc;
   assign req_spec_ip_ivc = ~allocated_ip_ivc & flit_valid_ip_ivc;
   
   wire [0:num_ports-1] 		   active_ip;
   c_mat_mult
     #(.dim1_width(num_ports),
       .dim2_width(num_vcs),
       .dim3_width(1),
       .prod_op(`BINARY_OP_AND),
       .sum_op(`BINARY_OP_OR))
   active_ip_mmult
     (.input_a(flit_valid_ip_ivc),
      .input_b({num_vcs{1'b1}}),
      .result(active_ip));
   
   wire [0:num_ports-1] 		   active_op;
   c_select_mofn
     #(.num_ports(num_ports*num_vcs),
       .width(num_ports))
   active_op_sel
     (.select(flit_valid_ip_ivc),
      .data_in(route_ip_ivc_op),
      .data_out(active_op));
   
   wire [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   wire [0:num_ports-1] 		   gnt_nonspec_ip;
   wire [0:num_ports-1] 		   gnt_spec_ip;
   wire [0:num_ports*num_ports-1] 	   gnt_op_ip;
   
   genvar 				   op;
   
   generate
      
      if(allocator_type == `SW_ALLOC_TYPE_SEP_IF)
	begin
	   vcr_sw_alloc_sep_if
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .spec_type(spec_type),
	       .reset_type(reset_type))
	   core_sep_if
	     (.clk(clk),
	      .reset(reset),
	      .active_ip(active_ip),
	      .active_op(active_op),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .sel_nonspec_ip_ivc(sel_nonspec_ip_ivc),
	      .sel_spec_ip_ivc(sel_spec_ip_ivc),
	      .gnt_nonspec_ip(gnt_nonspec_ip),
	      .gnt_spec_ip(gnt_spec_ip),
	      .gnt_op_ip(gnt_op_ip));
	end
      else if(allocator_type == `SW_ALLOC_TYPE_SEP_OF)
	begin
	   vcr_sw_alloc_sep_of
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .spec_type(spec_type),
	       .reset_type(reset_type))
	   core_sep_of
	     (.clk(clk),
	      .reset(reset),
	      .active_ip(active_ip),
	      .active_op(active_op),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .sel_nonspec_ip_ivc(sel_nonspec_ip_ivc),
	      .sel_spec_ip_ivc(sel_spec_ip_ivc),
	      .gnt_nonspec_ip(gnt_nonspec_ip),
	      .gnt_spec_ip(gnt_spec_ip),
	      .gnt_op_ip(gnt_op_ip));
	end
      else if((allocator_type >= `SW_ALLOC_TYPE_WF_BASE) &&
	      (allocator_type <= `SW_ALLOC_TYPE_WF_LIMIT))
	begin
	   vcr_sw_alloc_wf
	     #(.num_vcs(num_vcs),
	       .num_ports(num_ports),
	       .wf_alloc_type(allocator_type - `SW_ALLOC_TYPE_WF_BASE),
	       .arbiter_type(arbiter_type),
	       .spec_type(spec_type),
	       .reset_type(reset_type))
	   core_wf
	     (.clk(clk),
	      .reset(reset),
	      .active_ip(active_ip),
	      .route_ip_ivc_op(route_ip_ivc_op),
	      .req_nonspec_ip_ivc(req_nonspec_ip_ivc),
	      .req_spec_ip_ivc(req_spec_ip_ivc),
	      .sel_nonspec_ip_ivc(sel_nonspec_ip_ivc),
	      .sel_spec_ip_ivc(sel_spec_ip_ivc),
	      .gnt_nonspec_ip(gnt_nonspec_ip),
	      .gnt_spec_ip(gnt_spec_ip),
	      .gnt_op_ip(gnt_op_ip));
	end
      
   endgenerate
   
   generate
      
      if(spec_type == `SW_ALLOC_SPEC_TYPE_NONE)
	begin
	   assign gnt_ip = gnt_nonspec_ip;
	   assign sel_ip_ivc = sel_nonspec_ip_ivc;
	end
      else
	begin
	   
	   assign gnt_ip = gnt_nonspec_ip | gnt_spec_ip;
	   
	   genvar ip;

	   for(ip = 0; ip < num_ports; ip = ip + 1)
	     begin:ips
		
		wire [0:num_vcs-1] req_nonspec_ivc;
		assign req_nonspec_ivc
		  = req_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		
		wire 		   req_nonspec;
		assign req_nonspec = |req_nonspec_ivc;
		
		wire 		   gnt_nonspec;
		assign gnt_nonspec = gnt_nonspec_ip[ip];
		
		wire [0:num_vcs-1] sel_nonspec_ivc;
		assign sel_nonspec_ivc
		  = sel_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		
		wire [0:num_vcs-1] sel_spec_ivc;
		assign sel_spec_ivc
		  = sel_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		
		wire [0:num_vcs-1] sel_ivc;
		
		case(spec_type)
		  
		  `SW_ALLOC_SPEC_TYPE_REQ:
		    begin
		       assign sel_ivc
			 = req_nonspec ? sel_nonspec_ivc : sel_spec_ivc;
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_GNT:
		    begin
		       assign sel_ivc
			 = gnt_nonspec ? sel_nonspec_ivc : sel_spec_ivc;
		    end
		  
		  `SW_ALLOC_SPEC_TYPE_PRIO:
		    begin
		       assign sel_ivc = sel_nonspec_ivc | sel_spec_ivc;
		    end
		  
		endcase
		
		assign sel_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = sel_ivc;
		
	     end
	   
	end
      
   endgenerate
   
   generate
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:num_ports-1] xbr_ctrl_ip;
	   
	   wire 		active;
	   assign active = active_op[op] | (|xbr_ctrl_ip);
	   
	   wire [0:num_ports-1] xbr_ctrl_ip_s, xbr_ctrl_ip_q;
	   assign xbr_ctrl_ip_s = gnt_op_ip[op*num_ports:(op+1)*num_ports-1];
	   c_dff
	     #(.width(num_ports),
	       .reset_type(reset_type))
	   xbr_ctrl_ipq
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .d(xbr_ctrl_ip_s),
	      .q(xbr_ctrl_ip_q));
	   
	   assign xbr_ctrl_ip = xbr_ctrl_ip_q;
	   
	   assign xbr_ctrl_op_ip[op*num_ports:(op+1)*num_ports-1] = xbr_ctrl_ip;
	   
	end
      
   endgenerate
   
endmodule
