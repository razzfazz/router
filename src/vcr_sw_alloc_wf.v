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
// switch allocator variant using wavefront allocation
//==============================================================================

module vcr_sw_alloc_wf
  (clk, reset, active_ip, route_ip_ivc_op, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   sel_nonspec_ip_ivc, sel_spec_ip_ivc, gnt_nonspec_ip, gnt_spec_ip, gnt_op_ip);
   
`include "c_functions.v"
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which wavefront allocator variant to use
   parameter wf_alloc_type = `WF_ALLOC_TYPE_REP;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation type
   parameter spec_type = `SW_ALLOC_SPEC_TYPE_REQ;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // clock enable signals
   input [0:num_ports-1] active_ip;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_nonspec_ip_ivc;
   
   // speculative switch requests
   input [0:num_ports*num_vcs-1] 	   req_spec_ip_ivc;
   
   // indicate which VC at a given port is granted non-speculatively
   output [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_nonspec_ip_ivc;
   
   // indicate which VC at a given port is granted speculatively
   output [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	   sel_spec_ip_ivc;
   
   // non-speculative grants
   output [0:num_ports-1] 		   gnt_nonspec_ip;
   wire [0:num_ports-1] 		   gnt_nonspec_ip;
   
   // speculative grants
   output [0:num_ports-1] 		   gnt_spec_ip;
   wire [0:num_ports-1] 		   gnt_spec_ip;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] 	   gnt_op_ip;
   wire [0:num_ports*num_ports-1] 	   gnt_op_ip;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	   req_wf_nonspec_ip_op;
   wire [0:num_ports*num_ports-1] 	   gnt_wf_nonspec_ip_op;
   
   wire [0:num_ports*num_ports-1] 	   req_wf_spec_ip_op;
   wire [0:num_ports*num_ports-1] 	   gnt_wf_spec_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				   ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   wire active;
	   assign active = active_ip[ip];
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   assign route_ivc_op
	     = route_ip_ivc_op[ip*num_vcs*num_ports:(ip+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_ports*num_vcs-1] route_op_ivc;
	   c_interleave
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   route_op_ivc_intl
	     (.data_in(route_ivc_op),
	      .data_out(route_op_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // combine requests from all VCs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] req_nonspec_ivc;
	   assign req_nonspec_ivc
	     = req_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_ports-1] 	req_wf_nonspec_op;
	   c_select_mofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_wf_nonspec_op_sel
	     (.select(req_nonspec_ivc),
	      .data_in(route_ivc_op),
	      .data_out(req_wf_nonspec_op));
	   
	   assign req_wf_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
		    = req_wf_nonspec_op;
	   
	   wire [0:num_vcs-1] 		req_spec_ivc;
	   assign req_spec_ivc
	     = req_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_ports-1] 	req_wf_spec_op;
	   
	   if(spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	     begin
		
		c_select_mofn
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req_wf_spec_op_sel
		  (.select(req_spec_ivc),
		   .data_in(route_ivc_op),
		   .data_out(req_wf_spec_op));
		
	     end
	   else
	     assign req_wf_spec_op = {num_ports{1'b0}};
	   
	   assign req_wf_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
	     = req_wf_spec_op;
	   
	   
	   //-------------------------------------------------------------------
	   // pre-select winning VC for each output
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	gnt_wf_nonspec_op;
	   assign gnt_wf_nonspec_op
	     = gnt_wf_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_ports-1] 	gnt_wf_spec_op;
	   assign gnt_wf_spec_op
	     = gnt_wf_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_ports*num_vcs-1] gnt_in_nonspec_op_ivc;
	   wire [0:num_ports*num_vcs-1] gnt_in_spec_op_ivc;
	   
	   genvar 			op;
	   
	   for(op = 0; op < num_ports; op = op + 1)
	     begin:ops
		
		wire [0:num_vcs-1] route_ivc;
		assign route_ivc = route_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		
		wire 		   update_arb_nonspec;
		assign update_arb_nonspec = gnt_wf_nonspec_op[op];
		
		wire [0:num_vcs-1] req_in_nonspec_ivc;
		assign req_in_nonspec_ivc = route_ivc & req_nonspec_ivc;
		
		wire [0:num_vcs-1] gnt_in_nonspec_ivc;
		
		if(spec_type != `SW_ALLOC_SPEC_TYPE_PRIO)
		  begin
		     
		     c_arbiter
		       #(.num_ports(num_vcs),
			 .reset_type(reset_type),
			 .arbiter_type(arbiter_type))
		     gnt_in_nonspec_ivc_arb
		       (.clk(clk),
			.reset(reset),
			.active(active),
			.update(update_arb_nonspec),
			.req(req_in_nonspec_ivc),
			.gnt(gnt_in_nonspec_ivc));
		     
		  end
		
		assign gnt_in_nonspec_op_ivc[op*num_vcs:(op+1)*num_vcs-1]
		  = gnt_in_nonspec_ivc;
		
		wire [0:num_vcs-1] gnt_in_spec_ivc;
		
		if(spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
		  begin
		     
		     wire update_arb_spec;
		     assign update_arb_spec = gnt_wf_spec_op[op];
		     
		     wire [0:num_vcs-1] req_in_spec_ivc;
		     assign req_in_spec_ivc = route_ivc & req_spec_ivc;
		     
		     if(spec_type == `SW_ALLOC_SPEC_TYPE_PRIO)
		       begin
			  
			  wire update_arb;
			  assign update_arb
			    = update_arb_nonspec | update_arb_spec;
			  
			  c_arbiter
			    #(.num_ports(num_vcs),
			      .num_priorities(2),
			      .reset_type(reset_type),
			      .arbiter_type(arbiter_type))
			  gnt_in_ivc_arb
			    (.clk(clk),
			     .reset(reset),
			     .active(active),
			     .update(update_arb),
			     .req({req_in_nonspec_ivc, req_in_spec_ivc}),
			     .gnt({gnt_in_nonspec_ivc, gnt_in_spec_ivc}));
			  
		       end
		     else
		       begin
			  
			  c_arbiter
			    #(.num_ports(num_vcs),
			      .reset_type(reset_type),
			      .arbiter_type(arbiter_type))
			  gnt_in_spec_ivc_arb
			    (.clk(clk),
			     .reset(reset),
			     .active(active),
			     .update(update_arb_spec),
			     .req(req_in_spec_ivc),
			     .gnt(gnt_in_spec_ivc));
			  
		       end
		     
		  end
		else
		  assign gnt_in_spec_ivc = {num_vcs{1'b0}};
		
		assign gnt_in_spec_op_ivc[op*num_vcs:(op+1)*num_vcs-1]
		  = gnt_in_spec_ivc;
		
	     end
	   
	   wire [0:num_vcs*num_ports-1] gnt_in_nonspec_ivc_op;
	   c_interleave
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt_in_nonspec_ivc_op_intl
	     (.data_in(gnt_in_nonspec_op_ivc),
	      .data_out(gnt_in_nonspec_ivc_op));
	   
	   wire [0:num_vcs*num_ports-1] gnt_in_spec_ivc_op;
	   c_interleave
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt_in_spec_ivc_op_intl
	     (.data_in(gnt_in_spec_op_ivc),
	      .data_out(gnt_in_spec_ivc_op));
	   
	   
	   //-------------------------------------------------------------------
	   // use output-side grants to select winning VC
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] sel_nonspec_ivc_op;
	   assign sel_nonspec_ivc_op
	     = {num_vcs{gnt_wf_nonspec_op}} & gnt_in_nonspec_ivc_op;
	   
	   wire [0:num_vcs-1] 		sel_nonspec_ivc;
	   c_mat_mult
	     #(.dim1_width(num_vcs),
	       .dim2_width(num_ports),
	       .dim3_width(1),
	       .prod_op(`BINARY_OP_AND),
	       .sum_op(`BINARY_OP_OR))
	   sel_nonspec_ivc_mmult
	     (.input_a(sel_nonspec_ivc_op),
	      .input_b({num_ports{1'b1}}),
	      .result(sel_nonspec_ivc));
	   
	   wire 			gnt_nonspec;
	   assign gnt_nonspec = |gnt_wf_nonspec_op;
	   
	   wire [0:num_vcs-1] 		sel_spec_ivc;
	   wire 			gnt_spec;
	   
	   if(spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	     begin
		
		wire [0:num_vcs*num_ports-1] sel_spec_ivc_op;
		assign sel_spec_ivc_op
		  = {num_vcs{gnt_wf_spec_op}} & gnt_in_spec_ivc_op;
		
		c_mat_mult
		  #(.dim1_width(num_vcs),
		    .dim2_width(num_ports),
		    .dim3_width(1),
		    .prod_op(`BINARY_OP_AND),
		    .sum_op(`BINARY_OP_OR))
		sel_spec_ivc_mmult
		  (.input_a(sel_spec_ivc_op),
		   .input_b({num_ports{1'b1}}),
		   .result(sel_spec_ivc));
		
		assign gnt_spec = |gnt_wf_spec_op;
		
	     end
	   else
	     begin
		assign sel_spec_ivc = {num_vcs{1'b0}};
		assign gnt_spec = 1'b0;
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // combine global grants
	   //-------------------------------------------------------------------
	   
	   assign sel_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sel_nonspec_ivc;
	   assign gnt_nonspec_ip[ip] = gnt_nonspec;
	   assign sel_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sel_spec_ivc;
	   assign gnt_spec_ip[ip] = gnt_spec;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // mask speculative requests that conflict with non-speculative ones
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] unused_by_nonspec_ip;
   wire [0:num_ports-1] unused_by_nonspec_op;
   
   generate
      
      case(spec_type)
	
	`SW_ALLOC_SPEC_TYPE_NONE, `SW_ALLOC_SPEC_TYPE_PRIO:
	  begin
	     
	     assign unused_by_nonspec_ip = {num_ports{1'b0}};
	     assign unused_by_nonspec_op = {num_ports{1'b0}};
	     
	  end
	
	`SW_ALLOC_SPEC_TYPE_REQ:
	  begin
	     
	     c_mat_mult
	       #(.dim1_width(num_ports),
		 .dim2_width(num_ports),
		 .dim3_width(1),
		 .prod_op(`BINARY_OP_AND),
		 .sum_op(`BINARY_OP_NOR))
	     unused_by_nonspec_ip_mmult
	       (.input_a(req_wf_nonspec_ip_op),
		.input_b({num_ports{1'b1}}),
		.result(unused_by_nonspec_ip));
	     
	     c_binary_op
	       #(.width(num_ports),
		 .num_ports(num_ports),
		 .op(`BINARY_OP_NOR))
	     unused_by_nonspec_op_nor
	       (.data_in(req_wf_nonspec_ip_op),
		.data_out(unused_by_nonspec_op));
	     
	  end
	
	`SW_ALLOC_SPEC_TYPE_GNT:
	  begin
	     
	     c_mat_mult
	       #(.dim1_width(num_ports),
		 .dim2_width(num_ports),
		 .dim3_width(1),
		 .prod_op(`BINARY_OP_AND),
		 .sum_op(`BINARY_OP_NOR))
	     unused_by_nonspec_ip_mmult
	       (.input_a(gnt_wf_nonspec_ip_op),
		.input_b({num_ports{1'b1}}),
		.result(unused_by_nonspec_ip));
	     
	     c_binary_op
	       #(.width(num_ports),
		 .num_ports(num_ports),
		 .op(`BINARY_OP_NOR))
	     unused_by_nonspec_op_nor
	       (.data_in(gnt_wf_nonspec_ip_op),
		.data_out(unused_by_nonspec_op));
	     
	  end
   
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output stage (match first-stage requests to output ports)
   //---------------------------------------------------------------------------
   
   wire 				    active;
   assign active = |active_ip;
   
   // if there are any requests at all in a cycle, at least one of them will
   // eventually be granted, so update priorities
   wire 			  update_alloc_nonspec;
   assign update_alloc_nonspec = |req_nonspec_ip_ivc;
   
   generate
      
      if(spec_type != `SW_ALLOC_SPEC_TYPE_PRIO)
	begin
	   
	   c_wf_alloc
	     #(.num_ports(num_ports),
	       .wf_alloc_type(wf_alloc_type),
	       .reset_type(reset_type))
	   gnt_wf_nonspec_ip_op_alloc
	     (.clk(clk),
	      .reset(reset),
	      .active(active),
	      .update(update_alloc_nonspec),
	      .req(req_wf_nonspec_ip_op),
	      .gnt(gnt_wf_nonspec_ip_op));
	   
	end
      
      if(spec_type != `SW_ALLOC_SPEC_TYPE_NONE)
	begin
	   
	   wire update_alloc_spec;

	   if(spec_type == `SW_ALLOC_SPEC_TYPE_PRIO)
	     begin
		
		assign update_alloc_spec = |req_spec_ip_ivc;
		
		wire update_alloc;
		assign update_alloc = update_alloc_nonspec | update_alloc_spec;
		
		c_wf_alloc
		  #(.num_ports(num_ports),
		    .num_priorities(2),
		    .wf_alloc_type(wf_alloc_type),
		    .reset_type(reset_type))
		gnt_wf_ip_op_alloc
		  (.clk(clk),
		   .reset(reset),
		   .active(active),
		   .update(update_alloc),
		   .req({req_wf_nonspec_ip_op, req_wf_spec_ip_op}),
		   .gnt({gnt_wf_nonspec_ip_op, gnt_wf_spec_ip_op}));
		
	     end
	   else
	     begin
		
		wire [0:num_ports*num_ports-1] spec_mask_ip_op;
		c_mat_mult
		  #(.dim1_width(num_ports),
		    .dim2_width(1),
		    .dim3_width(num_ports),
		    .prod_op(`BINARY_OP_AND),
		    .sum_op(`BINARY_OP_OR))
		spec_mask_ip_op_mmult
		  (.input_a(unused_by_nonspec_ip),
		   .input_b(unused_by_nonspec_op),
		   .result(spec_mask_ip_op));
		
		// only update priorities if there is no conflicting non-
		// speculative request
		assign update_alloc_spec
		  = |(req_wf_spec_ip_op & spec_mask_ip_op);
		
		wire [0:num_ports*num_ports-1] req_wf_spec_int_ip_op;
		assign req_wf_spec_int_ip_op = req_wf_spec_ip_op;
		
		wire [0:num_ports*num_ports-1] gnt_wf_spec_int_ip_op;
		c_wf_alloc
		  #(.num_ports(num_ports),
		    .wf_alloc_type(wf_alloc_type),
		    .reset_type(reset_type))
		gnt_wf_spec_int_ip_op_alloc
		  (.clk(clk),
		   .reset(reset),
		   .active(active),
		   .update(update_alloc_spec),
		   .req(req_wf_spec_int_ip_op),
		   .gnt(gnt_wf_spec_int_ip_op));
		
		assign gnt_wf_spec_ip_op
		  = gnt_wf_spec_int_ip_op & spec_mask_ip_op;
		
	     end
	   
	end
      else
	assign gnt_wf_spec_ip_op = {num_ports*num_ports{1'b0}};
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grants
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] gnt_ip_op;
   assign gnt_ip_op = gnt_wf_nonspec_ip_op | gnt_wf_spec_ip_op;
   
   c_interleave
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_op_ip_intl
     (.data_in(gnt_ip_op),
      .data_out(gnt_op_ip));
   
endmodule
