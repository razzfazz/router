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

//==============================================================================
// leading one detector
//==============================================================================

module c_lod
  (data_in_pr, data_out_pr, data_out, mask_out);
   
`include "c_constants.v"
   
   // number of input ports
   parameter width = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // perform masking between priorities
   parameter mask_priorities = 1;
   
   // vector of requests
   input [0:num_priorities*width-1] data_in_pr;
   
   // vector of grants
   output [0:num_priorities*width-1] data_out_pr;
   wire [0:num_priorities*width-1]   data_out_pr;
   
   // merged vector of grants
   output [0:width-1] 		     data_out;
   wire [0:width-1] 		     data_out;
   
   // merged vector of masked bits
   output [0:width-1] 		     mask_out;
   wire [0:width-1] 		     mask_out;
   
   wire [0:num_priorities*width-1]   data_intm_pr;
   wire [0:num_priorities*width-1]   mask_out_pr;
   
   genvar 			     prio;
   
   generate
      
      for(prio = 0; prio < num_priorities; prio = prio + 1)
	begin:prios
	   
	   wire [0:width-1] data_in;
	   assign data_in = data_in_pr[prio*width:(prio+1)*width-1];
	   
	   wire [0:width-1] data_intm;
	   wire [0:width-1] mask_out;
	   
	   if(width == 1)
	     begin
		assign data_intm = data_in;
		assign mask_out = 1'b0;
	     end
	   else
	     begin
		
		// To find the first non-zero bit from the left, we must 
		// reverse the input and output vectors.
		
		wire [0:width-1] data_in_rev;
		c_reverse
		  #(.width(width))
		data_in_rev_revr
		  (.data_in(data_in),
		   .data_out(data_in_rev));
		
		wire [0:width-1] data_in_rev_compl;
		assign data_in_rev_compl = -data_in_rev;
		
		wire [0:width-1] data_intm_rev;
		assign data_intm_rev = data_in_rev & data_in_rev_compl;
		
		c_reverse
		  #(.width(width))
		data_intm_revr
		  (.data_in(data_intm_rev),
		   .data_out(data_intm));
		
		wire [0:width-1] mask_out_rev;
		assign mask_out_rev = data_in_rev ^ data_in_rev_compl;
		
		c_reverse
		  #(.width(width))
		mask_out_revr
		  (.data_in(mask_out_rev),
		   .data_out(mask_out));
		
	     end
	   
	   assign data_intm_pr[prio*width:(prio+1)*width-1] = data_intm;
	   assign mask_out_pr[prio*width:(prio+1)*width-1] = mask_out;
	   
	end
      
      if(num_priorities == 1)
	begin
	   assign data_out = data_intm_pr;
	   assign data_out_pr = data_intm_pr;
	   assign mask_out = mask_out_pr;
	end
      else if(num_priorities > 1)
	begin
	   
	   wire [0:num_priorities-1] sel_pr;
	   
	   if(num_priorities == 2)
	     assign sel_pr = {|data_in_pr[0:width-1], ~|data_in_pr[0:width-1]};
	   else if(num_priorities > 2)
	     begin
		
		wire [0:num_priorities-1] valid_pr;
		c_mat_mult
		  #(.dim1_width(num_priorities),
		    .dim2_width(width),
		    .dim3_width(1),
		    .prod_op(`BINARY_OP_AND),
		    .sum_op(`BINARY_OP_OR))
		valid_pr_mmult
		  (.input_a(data_in_pr),
		   .input_b({width{1'b1}}),
		   .result(valid_pr));
		
		wire [0:num_priorities-1] req_pr;
		assign req_pr = {valid_pr[0:num_priorities-2], 1'b1};
		
		wire [0:num_priorities-1] req_pr_rev;
		c_reverse
		  #(.width(num_priorities))
		req_pr_rev_revr
		  (.data_in(req_pr),
		   .data_out(req_pr_rev));
		
		wire [0:num_priorities-1] gnt_pr_rev;
		assign gnt_pr_rev = req_pr_rev & -req_pr_rev;
		
		wire [0:num_priorities-1] gnt_pr;
		c_reverse
		  #(.width(num_priorities))
		gnt_piro_rev_revr
		  (.data_in(gnt_pr_rev),
		   .data_out(gnt_pr));
		
		assign sel_pr = gnt_pr;
		
	     end
	   
	   if(mask_priorities)
	     begin
		
		wire [0:num_priorities*width-1] gnt_mask_pr;
		c_mat_mult
		  #(.dim1_width(num_priorities),
		    .dim2_width(1),
		    .dim3_width(width),
		    .prod_op(`BINARY_OP_AND),
		    .sum_op(`BINARY_OP_OR))
		gnt_mask_pr_mmult
		  (.input_a(sel_pr),
		   .input_b({width{1'b1}}),
		   .result(gnt_mask_pr));
		
		c_select_1ofn
		  #(.num_ports(num_priorities),
		    .width(width))
		data_out_sel
		  (.select(sel_pr),
		   .data_in(data_intm_pr),
		   .data_out(data_out));
		
		assign data_out_pr = data_intm_pr & gnt_mask_pr;
		
	     end
	   else
	     begin
		
		assign data_out_pr = data_intm_pr;
		
		c_binary_op
		  #(.num_ports(num_priorities),
		    .width(width),
		    .op(`BINARY_OP_OR))
		data_out_or
		  (.data_in(data_intm_pr),
		   .data_out(data_out));
		
	     end
	   
	   c_select_1ofn
	     #(.num_ports(num_priorities),
	       .width(width))
	   mask_out_sel
	     (.select(sel_pr),
	      .data_in(mask_out_pr),
	      .data_out(mask_out));
	   
	end
      
   endgenerate
   
endmodule
