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

// switch allocator variant using wavefront allocation
module vcr_sw_alloc_wf
  (clk, reset, route_ip_ivc_op, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   gnt_nonspec_ip_ivc, gnt_spec_ip_ivc, gnt_ip_op);
   
`include "c_constants.v"
`include "vcr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which wavefront allocator variant to use
   parameter wf_allocator_type = `WF_ALLOCATOR_TYPE_REP;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level
   parameter spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*num_ports-1] route_ip_ivc_op;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs-1] req_nonspec_ip_ivc;
   
   // speculative switch requests
   input [0:num_ports*num_vcs-1] req_spec_ip_ivc;
   
   // grants corresponding to non-speculative requests (to input controller)
   output [0:num_ports*num_vcs-1] gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] gnt_nonspec_ip_ivc;
   
   // grants corresponding to speculative requests (to input controller)
   output [0:num_ports*num_vcs-1] gnt_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] gnt_spec_ip_ivc;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] gnt_ip_op;
   wire [0:num_ports*num_ports-1] gnt_ip_op;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] req_wf_nonspec_ip_op;
   wire [0:num_ports*num_ports-1] gnt_wf_nonspec_ip_op;
   
   wire [0:num_ports*num_ports-1] req_wf_spec_ip_op;
   wire [0:num_ports*num_ports-1] gnt_wf_spec_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 			  ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   assign route_ivc_op
	     = route_ip_ivc_op[ip*num_vcs*num_ports:(ip+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_ports*num_vcs-1] route_op_ivc;
	   c_interleaver
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
	   c_select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_wf_nonspec_op_sel
	     (.select(req_nonspec_ivc),
	      .data_in(route_ivc_op),
	      .data_out(req_wf_nonspec_op));
	   
	   assign req_wf_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
		    = req_wf_nonspec_op;
	   
	   
	   //-------------------------------------------------------------------
	   // pre-select winning VC for each output
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	gnt_wf_nonspec_op;
	   assign gnt_wf_nonspec_op
	     = gnt_wf_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_ports*num_vcs-1] gnt_in_nonspec_op_ivc;
	   
	   genvar 			op;
	   
	   for(op = 0; op < num_ports; op = op + 1)
	     begin:nonspec_ops
		
		wire 			update_arb_nonspec;
		assign update_arb_nonspec = gnt_wf_nonspec_op[op];
		
		wire [0:num_vcs-1] 	route_ivc;
		assign route_ivc = route_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		
		wire [0:num_vcs-1] 	req_in_nonspec_ivc;
		assign req_in_nonspec_ivc = route_ivc & req_nonspec_ivc;
		
		wire [0:num_vcs-1] 	gnt_in_nonspec_ivc;
		c_arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .arbiter_type(arbiter_type))
		gnt_in_nonspec_ivc_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb_nonspec),
		   .req(req_in_nonspec_ivc),
		   .gnt(gnt_in_nonspec_ivc));
		
		assign gnt_in_nonspec_op_ivc[op*num_vcs:(op+1)*num_vcs-1]
			 = gnt_in_nonspec_ivc;
		
	     end
	   
	   wire [0:num_vcs*num_ports-1] gnt_in_nonspec_ivc_op;
	   c_interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt_in_nonspec_ivc_op_intl
	     (.data_in(gnt_in_nonspec_op_ivc),
	      .data_out(gnt_in_nonspec_ivc_op));
	   
	   
	   //-------------------------------------------------------------------
	   // use output-side grants to select winning VC
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] gnt_nonspec_ivc_op;
	   assign gnt_nonspec_ivc_op
	     = {num_vcs{gnt_wf_nonspec_op}} & gnt_in_nonspec_ivc_op;
	   
	   wire [0:num_ports*num_vcs-1] gnt_nonspec_op_ivc;
	   c_interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   gnt_nonspec_op_ivc_intl
	     (.data_in(gnt_nonspec_ivc_op),
	      .data_out(gnt_nonspec_op_ivc));
	   
	   wire [0:num_vcs-1] 		gnt_nonspec_ivc;
	   c_or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   gnt_nonspec_ivc_or
	     (.data_in(gnt_nonspec_op_ivc),
	      .data_out(gnt_nonspec_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 		gnt_spec_ivc;
	   
	   if(spec_level != `SW_SPEC_LEVEL_NONE)
	     begin
		
		//--------------------------------------------------------------
		// combine requests from all VCs
		//--------------------------------------------------------------
		
		wire [0:num_vcs-1] req_spec_ivc;
		assign req_spec_ivc
		  = req_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		
		wire [0:num_ports-1] 	     req_wf_spec_op;
		c_select_1ofn
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req_wf_spec_op_sel
		  (.select(req_spec_ivc),
		   .data_in(route_ivc_op),
		   .data_out(req_wf_spec_op));
		
		assign req_wf_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 = req_wf_spec_op;
		
		
		//--------------------------------------------------------------
		// pre-select winning VC for each output
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 	     gnt_wf_spec_op;
		assign gnt_wf_spec_op
		  = gnt_wf_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
		
		wire [0:num_ports*num_vcs-1] gnt_in_spec_op_ivc;
		
		for(op = 0; op < num_ports; op = op + 1)
		  begin:spec_ops
		     
		     wire update_arb_spec;
		     assign update_arb_spec = gnt_wf_spec_op[op];
		     
		     wire [0:num_vcs-1] route_ivc;
		     assign route_ivc
		       = route_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		     
		     wire [0:num_vcs-1] req_in_spec_ivc;
		     assign req_in_spec_ivc = route_ivc & req_spec_ivc;
		     
		     wire [0:num_vcs-1] gnt_in_spec_ivc;
		     c_arbiter
		       #(.num_ports(num_vcs),
			 .reset_type(reset_type),
			 .arbiter_type(arbiter_type))
		     gnt_in_spec_ivc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb_spec),
			.req(req_in_spec_ivc),
			.gnt(gnt_in_spec_ivc));
		     
		     assign gnt_in_spec_op_ivc[op*num_vcs:(op+1)*num_vcs-1]
			      = gnt_in_spec_ivc;
		     
		  end
		
		wire [0:num_vcs*num_ports-1] gnt_in_spec_ivc_op;
		c_interleaver
		  #(.width(num_vcs*num_ports),
		    .num_blocks(num_ports))
		gnt_in_spec_ivc_op_intl
		  (.data_in(gnt_in_spec_op_ivc),
		   .data_out(gnt_in_spec_ivc_op));
		
		
		//--------------------------------------------------------------
		// use output-side grants to select winning VC
		//--------------------------------------------------------------
		
		wire [0:num_vcs*num_ports-1] gnt_spec_ivc_op;
		assign gnt_spec_ivc_op
		  = {num_vcs{gnt_wf_spec_op}} & gnt_in_spec_ivc_op;
		
		wire [0:num_ports*num_vcs-1] gnt_spec_op_ivc;
		c_interleaver
		  #(.width(num_vcs*num_ports),
		    .num_blocks(num_vcs))
		gnt_spec_op_ivc_intl
		  (.data_in(gnt_spec_ivc_op),
		   .data_out(gnt_spec_op_ivc));
		
		c_or_nto1
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		gnt_spec_ivc_or
		  (.data_in(gnt_spec_op_ivc),
		   .data_out(gnt_spec_ivc));
		
	     end
	   else
	     begin
		
		assign req_wf_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 ={num_ports{1'b0}};
		assign gnt_spec_ivc = {num_vcs{1'b0}};
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // combine global grants
	   //-------------------------------------------------------------------
	   
	   assign gnt_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = gnt_nonspec_ivc;
	   assign gnt_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = gnt_spec_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // mask speculative requests that conflict with non-speculative ones
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] spec_mask_ip_op;
   
   generate
      
      case(spec_level)
	
	`SW_SPEC_LEVEL_NONE:
	  begin
	     
	     assign spec_mask_ip_op = {num_ports*num_ports{1'b0}};
	     
	  end
	
	`SW_SPEC_LEVEL_ANY_NONSPEC_MASKS:
	  begin
	     
	     assign spec_mask_ip_op
	       = {num_ports*num_ports{~|req_wf_nonspec_ip_op}};
	     
	  end
	
	`SW_SPEC_LEVEL_CONFL_NONSPEC_REQ_MASKS:
	  begin
	     
	     wire [0:num_ports*num_ports-1] req_wf_nonspec_op_ip;
	     c_interleaver
	       #(.width(num_ports*num_ports),
		 .num_blocks(num_ports))
	     req_wf_nonspec_op_ip_intl
	       (.data_in(req_wf_nonspec_ip_op),
		.data_out(req_wf_nonspec_op_ip));
	     
	     wire [0:num_ports-1] 	    any_req_ip;
	     c_or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_req_ip_or
	       (.data_in(req_wf_nonspec_op_ip),
		.data_out(any_req_ip));
	     
	     wire [0:num_ports*num_ports-1] any_req_in_ip_op;
	     c_replicator
	       #(.width(num_ports),
		 .count(num_ports))
	     any_req_in_ip_op_repl
	       (.data_in(any_req_ip),
		.data_out(any_req_in_ip_op));
	     
	     wire [0:num_ports-1] 	    any_req_op;
	     c_or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_req_op_or
	       (.data_in(req_wf_nonspec_ip_op),
		.data_out(any_req_op));
	     
	     wire [0:num_ports*num_ports-1] any_req_wf_ip_op;
	     assign any_req_wf_ip_op = {num_ports{any_req_op}};
	     
	     assign spec_mask_ip_op = ~(any_req_in_ip_op | any_req_wf_ip_op);
	     
	  end
	
	`SW_SPEC_LEVEL_CONFL_NONSPEC_GNT_MASKS:
	  begin
	     
	     wire [0:num_ports*num_ports-1] gnt_wf_nonspec_op_ip;
	     c_interleaver
	       #(.width(num_ports*num_ports),
		 .num_blocks(num_ports))
	     gnt_wf_nonspec_op_ip_intl
	       (.data_in(gnt_wf_nonspec_ip_op),
		.data_out(gnt_wf_nonspec_op_ip));
	     
	     wire [0:num_ports-1] 	    any_gnt_ip;
	     c_or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_gnt_ip_or
	       (.data_in(gnt_wf_nonspec_op_ip),
		.data_out(any_gnt_ip));
	     
	     wire [0:num_ports*num_ports-1] any_gnt_in_ip_op;
	     c_replicator
	       #(.width(num_ports),
		 .count(num_ports))
	     any_gnt_in_ip_op_repl
	       (.data_in(any_gnt_ip),
		.data_out(any_gnt_in_ip_op));
	     
	     wire [0:num_ports-1] 	    any_gnt_op;
	     c_or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_gnt_op_or
	       (.data_in(gnt_wf_nonspec_ip_op),
		.data_out(any_gnt_op));
	     
	     wire [0:num_ports*num_ports-1] any_gnt_wf_ip_op;
	     assign any_gnt_wf_ip_op = {num_ports{any_gnt_op}};
	     
	     assign spec_mask_ip_op = ~(any_gnt_in_ip_op | any_gnt_wf_ip_op);
	     
	  end
   
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output stage (match first-stage requests to output ports)
   //---------------------------------------------------------------------------
   
   // if there are any requests at all in a cycle, at least one of them will
   // eventually be granted, so update priorities
   wire 				    update_alloc_nonspec;
   assign update_alloc_nonspec = |req_nonspec_ip_ivc;
   
   c_wf_alloc
     #(.num_ports(num_ports),
       .wf_allocator_type(wf_allocator_type),
       .reset_type(reset_type))
   gnt_wf_nonspec_ip_op_alloc
     (.clk(clk),
      .reset(reset),
      .update(update_alloc_nonspec),
      .req(req_wf_nonspec_ip_op),
      .gnt(gnt_wf_nonspec_ip_op));
   
   generate
      
      if(spec_level != `SW_SPEC_LEVEL_NONE)
	begin
	   
	   // only update priorities if there is no conflicting non-
	   // speculative request
	   wire update_alloc_spec;
	   assign update_alloc_spec = |(req_wf_spec_ip_op & spec_mask_ip_op);
	   
	   wire [0:num_ports*num_ports-1] gnt_wf_unmasked_spec_ip_op;
	   c_wf_alloc
	     #(.num_ports(num_ports),
	       .wf_allocator_type(wf_allocator_type),
	       .reset_type(reset_type))
	   gnt_wf_unmasked_spec_ip_op_alloc
	     (.clk(clk),
	      .reset(reset),
	      .update(update_alloc_spec),
	      .req(req_wf_spec_ip_op),
	      .gnt(gnt_wf_unmasked_spec_ip_op));
	   
	   assign gnt_wf_spec_ip_op
	     = gnt_wf_unmasked_spec_ip_op & spec_mask_ip_op;
	   
	end
      else
	assign gnt_wf_spec_ip_op = {num_ports*num_ports{1'b0}};
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grants
   //---------------------------------------------------------------------------
   
   assign gnt_ip_op = gnt_wf_nonspec_ip_op | gnt_wf_spec_ip_op;
   
endmodule
