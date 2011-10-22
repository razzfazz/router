// $Id$

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



// switch allocator variant usign separable input-first allocation
module vcr_sw_alloc_sep_if
  (clk, reset, route_port_ip_ivc, req_nonspec_ip_ivc, req_spec_ip_ivc, 
   gnt_nonspec_ip_ivc, gnt_spec_ip_ivc, gnt_op_ip);
   
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
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // width required to select an individual port
   localparam port_idx_width = clogb(num_ports);
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level
   parameter spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // destination port selects
   input [0:num_ports*num_vcs*port_idx_width-1] route_port_ip_ivc;
   
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
   output [0:num_ports*num_ports-1] gnt_op_ip;
   wire [0:num_ports*num_ports-1] gnt_op_ip;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] req_in_nonspec_ip_op;   
   wire [0:num_ports*num_ports-1] req_out_nonspec_ip_op;
   wire [0:num_ports*num_ports-1] gnt_out_nonspec_ip_op;
   
   wire [0:num_ports*num_ports-1] req_out_spec_ip_op;
   wire [0:num_ports*num_ports-1] gnt_out_spec_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 			  ip;
      
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   wire [0:num_vcs*port_idx_width-1] route_port_ivc;
	   assign route_port_ivc
	     = route_port_ip_ivc[ip*num_vcs*port_idx_width:
				 (ip+1)*num_vcs*port_idx_width-1];
	   
	   wire [0:num_vcs*num_ports-1]      route_ivc_op;
	   
	   genvar 			     ivc;
	   
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		wire [0:port_idx_width-1] route_port;
		assign route_port = route_port_ivc[ivc*port_idx_width:
						   (ivc+1)*port_idx_width-1];
		
		wire [0:num_ports-1] 	  route_op;
		c_decoder
		  #(.num_ports(num_ports))
		route_op_dec
		  (.data_in(route_port),
		   .data_out(route_op));
		
		assign route_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
			 = route_op;
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // perform input-side arbitration
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] gnt_out_nonspec_op;
	   assign gnt_out_nonspec_op
	     = gnt_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire 		gnt_out_nonspec;
	   assign gnt_out_nonspec = |gnt_out_nonspec_op;
	   
	   wire 		update_arb_nonspec;
	   assign update_arb_nonspec = gnt_out_nonspec;
	   
	   wire [0:num_vcs-1] 	req_nonspec_ivc;
	   assign req_nonspec_ivc
	     = req_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] 		req_in_nonspec_ivc;
	   assign req_in_nonspec_ivc = req_nonspec_ivc;
	   
	   wire [0:num_vcs-1] gnt_in_nonspec_ivc;
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
	   
	   wire [0:num_ports-1] req_in_nonspec_op;
	   c_select_mofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_in_nonspec_ip_op_sel
	     (.select(req_in_nonspec_ivc),
	      .data_in(route_ivc_op),
	      .data_out(req_in_nonspec_op));
	   
	   assign req_in_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
		    = req_in_nonspec_op;
	   
	   //-------------------------------------------------------------------
	   // generate requests for output stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_nonspec_op;
	   c_select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_out_nonspec_op_sel
	     (.select(gnt_in_nonspec_ivc),
	      .data_in(route_ivc_op),
	      .data_out(req_out_nonspec_op));
	   
	   assign req_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
		    = req_out_nonspec_op;
	   
	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	gnt_nonspec_ivc;
	   assign gnt_nonspec_ivc
	     = {num_vcs{gnt_out_nonspec}} & gnt_in_nonspec_ivc;
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	gnt_spec_ivc;
	   
	   if(spec_level != `SW_SPEC_LEVEL_NONE)
	     begin
		
		//--------------------------------------------------------------
		// perform input-side arbitration (speculative)
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] gnt_out_spec_op;
		assign gnt_out_spec_op
		  = gnt_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
		
		wire 		     gnt_out_spec;
		assign gnt_out_spec = |gnt_out_spec_op;
		
		wire 		     update_arb_spec;
		assign update_arb_spec = gnt_out_spec;
		
		wire [0:num_vcs-1]   req_spec_ivc;
		assign req_spec_ivc
		  = req_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		
		wire [0:num_vcs-1] 	     req_in_spec_ivc;
		assign req_in_spec_ivc = req_spec_ivc;
		
		wire [0:num_vcs-1] 	gnt_in_spec_ivc;
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
		
		
		//--------------------------------------------------------------
		// generate requests for output stage (speculative)
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 	req_out_spec_op;
		c_select_1ofn
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req_out_spec_op_sel
		  (.select(gnt_in_spec_ivc),
		   .data_in(route_ivc_op),
		   .data_out(req_out_spec_op));
		
		assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 = req_out_spec_op;
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		assign gnt_spec_ivc
		  = {num_vcs{gnt_out_spec}} & gnt_in_spec_ivc;
		
	     end
	   else
	     begin
		
		assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 = {num_ports{1'b0}};
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
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] req_in_nonspec_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_in_nonspec_op_ip_intl
     (.data_in(req_in_nonspec_ip_op),
      .data_out(req_in_nonspec_op_ip));
   
   wire [0:num_ports*num_ports-1] req_out_nonspec_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_nonspec_op_ip_intl
     (.data_in(req_out_nonspec_ip_op),
      .data_out(req_out_nonspec_op_ip));
   
   wire [0:num_ports*num_ports-1] gnt_out_nonspec_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_nonspec_op_ip_intl
     (.data_in(gnt_out_nonspec_op_ip),
      .data_out(gnt_out_nonspec_ip_op));
   
   wire [0:num_ports*num_ports-1] req_out_spec_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_spec_op_ip_intl
     (.data_in(req_out_spec_ip_op),
      .data_out(req_out_spec_op_ip));
   
   wire [0:num_ports*num_ports-1] gnt_out_spec_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_spec_op_ip_intl
     (.data_in(gnt_out_spec_op_ip),
      .data_out(gnt_out_spec_ip_op));
   
   
   //---------------------------------------------------------------------------
   // mask speculative requests that conflict with non-speculative ones
   //---------------------------------------------------------------------------

   wire [0:num_ports-1] 	  unused_by_nonspec_ip;
   wire [0:num_ports-1] 	  unused_by_nonspec_op;
   
   generate
      
      case(spec_level)
	
	`SW_SPEC_LEVEL_NONE:
	  begin
	     
	     assign unused_by_nonspec_ip = {num_ports{1'b0}};
	     assign unused_by_nonspec_op = {num_ports{1'b0}};
	     
	  end
	
	`SW_SPEC_LEVEL_ANY_NONSPEC_MASKS:
	  begin
	     
	     assign unused_by_nonspec_ip = {num_ports{~|req_nonspec_ip_ivc}};
	     assign unused_by_nonspec_op = {num_ports{1'b1}};
	     
	  end
	
	`SW_SPEC_LEVEL_CONFL_NONSPEC_REQ_MASKS:
	  begin
	     
	     // We can potentially improve matching by using the grants of the
	     // input stage (i.e., the requests of the output stage) to filter 
	     // out output ports that have all requests for them eliminated in 
	     // the input stage. As the associated OR reduction can be performed
	     // in parallel with output-stage arbitration, this should not 
	     // increase delay.
	     c_nor_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     unused_by_nonspec_op_nor
	       (.data_in(req_out_nonspec_ip_op),
		.data_out(unused_by_nonspec_op));
	     
	     // For determining which inputs are in use, looking at the input-
	     // stage grants rather than its requests does not yield any 
	     // additional information, as the input-side arbitration stage will
	     // generate a grant if and only if there were any requests. Thus,
	     // we use the requests here to ease timing.
	     c_nor_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     unused_by_nonspec_ip_nor
	       (.data_in(req_in_nonspec_op_ip),
		.data_out(unused_by_nonspec_ip));
	     
	  end
	
	`SW_SPEC_LEVEL_CONFL_NONSPEC_GNT_MASKS:
	  begin
	     
	     // An output is granted if and only if there were any output-stage 
	     // requests for it; thus, it is sufficient to look at the arbiter 
	     // inputs here.
	     c_nor_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     unused_by_nonspec_op_nor
	       (.data_in(req_out_nonspec_ip_op),
		.data_out(unused_by_nonspec_op));
	     
	     // However, we can make no such simplification to determine which
	     // input ports are in use: A given input may have requested 
	     // one or more outputs, but all of its requests could have been 
	     // eliminated in the output arbitration stage.
	     c_nor_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     unused_by_nonspec_ip_nor
	       (.data_in(gnt_out_nonspec_op_ip),
		.data_out(unused_by_nonspec_ip));
	     
	  end
	
	`SW_SPEC_LEVEL_CONFL_NONSPEC_INT_MASKS:
	  begin
	     
	     c_nor_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     unused_by_nonspec_op_nor
	       (.data_in(req_in_nonspec_ip_op),
		.data_out(unused_by_nonspec_op));
	     
	     c_nor_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     unused_by_nonspec_ip_nor
	       (.data_in(req_in_nonspec_op_ip),
		.data_out(unused_by_nonspec_ip));
	     
	  end
	
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				    op;
      
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   //-------------------------------------------------------------------
	   // perform output-side arbitration (select input port)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_nonspec_ip;
	   assign req_out_nonspec_ip
	     = req_out_nonspec_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   // if any VC requesting this output port was granted at any input
	   // port in the first stage, one of these input ports will be granted
	   // here as well, and we can thus update priorities
	   wire 		update_arb_nonspec;
	   assign update_arb_nonspec = |req_out_nonspec_ip;
	   
	   wire [0:num_ports-1] gnt_out_nonspec_ip;
	   c_arbiter
	     #(.num_ports(num_ports),
	       .arbiter_type(arbiter_type),
	       .reset_type(reset_type))
	   gnt_out_nonspec_ip_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb_nonspec),
	      .req(req_out_nonspec_ip),
	      .gnt(gnt_out_nonspec_ip));
	   
	   
	   //-------------------------------------------------------------------
	   // feed grants back to input stage
	   //-------------------------------------------------------------------
	   
	   assign gnt_out_nonspec_op_ip[op*num_ports:(op+1)*num_ports-1]
		    = gnt_out_nonspec_ip;
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   if(spec_level != `SW_SPEC_LEVEL_NONE)
	     begin
		
		//--------------------------------------------------------------
		// perform output-side arbitration (speculative)
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] req_out_spec_ip;
		assign req_out_spec_ip
		  = req_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1];
		
		wire 		     unused_by_nonspec;
		assign unused_by_nonspec = unused_by_nonspec_op[op];
		
		wire 		     update_arb_spec;
		wire [0:num_ports-1] req_out_spec_int_ip;
		wire [0:num_ports-1] gnt_out_spec_int_ip;
		wire [0:num_ports-1] gnt_out_spec_ip;
		
		if(spec_level == `SW_SPEC_LEVEL_CONFL_NONSPEC_INT_MASKS)
		  begin
		     
		     assign req_out_spec_int_ip
		       = req_out_spec_ip & unused_by_nonspec_ip;
		     
		     assign gnt_out_spec_ip
		       = gnt_out_spec_int_ip & {num_ports{unused_by_nonspec}};
		     
		  end
		else
		  begin
		     
		     assign req_out_spec_int_ip = req_out_spec_ip;
		     
		     assign gnt_out_spec_ip
		       = gnt_out_spec_int_ip & unused_by_nonspec_ip &
			 {num_ports{unused_by_nonspec}};
		     
		  end
		
		assign update_arb_spec
		  = |(req_out_spec_int_ip & unused_by_nonspec_ip) & 
		    unused_by_nonspec;
		
		c_arbiter
		  #(.num_ports(num_ports),
		    .arbiter_type(arbiter_type),
		    .reset_type(reset_type))
		gnt_out_spec_int_ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb_spec),
		   .req(req_out_spec_int_ip),
		   .gnt(gnt_out_spec_int_ip));
		
		
		//--------------------------------------------------------------
		// feed grants back to input stage (speculative)
		//--------------------------------------------------------------
		
		assign gnt_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1]
			 = gnt_out_spec_ip;
		
	     end
	   else
	     assign gnt_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1]
		      = {num_ports{1'b0}};
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global outputs
   //---------------------------------------------------------------------------

   assign gnt_op_ip = gnt_out_nonspec_op_ip | gnt_out_spec_op_ip;
   
endmodule
