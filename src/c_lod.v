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
  (data_in, data_out, mask_out);
   
   // number of input ports
   parameter width = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // provide separate grant signals for each priority level
   parameter split_output_by_prio = 0;
   
   // width of grant output
   localparam out_width = (split_output_by_prio ? num_priorities : 1) * width;
   
   // vector of requests
   input [0:num_priorities*width-1] data_in;
   
   // vector of grants
   output [0:out_width-1] 	    data_out;
   wire [0:out_width-1] 	    data_out;
   
   // vector of masked bits
   output [0:out_width-1] 	    mask_out;
   wire [0:out_width-1] 	    mask_out;
   
   wire [0:num_priorities*width-1]  data_out_by_prio;
   wire [0:num_priorities*width-1]  mask_out_by_prio;
   
   genvar 			    prio;
   
   generate
      
      for(prio = 0; prio < num_priorities; prio = prio + 1)
	begin:prios
	   
	   wire [0:width-1] prio_data_in;
	   assign prio_data_in = data_in[prio*width:(prio+1)*width-1];
	   
	   wire [0:width-1] prio_data_out;
	   wire [0:width-1] prio_mask_out;
	   
	   if(width == 1)
	     begin
		assign prio_data_out = prio_data_in;
		assign prio_mask_out = 1'b0;
	     end
	   else
	     begin
		
		// To find the first non-zero bit from the left, we must 
		// reverse the input and output vectors.
		
		wire [0:width-1] prio_data_in_rev;
		c_reverse
		  #(.width(width))
		prio_data_in_rev_revr
		  (.data_in(prio_data_in),
		   .data_out(prio_data_in_rev));
		
		wire [0:width-1] prio_data_in_rev_compl;
		assign prio_data_in_rev_compl = -prio_data_in_rev;
		
		wire [0:width-1] prio_data_out_rev;
		assign prio_data_out_rev
		  = prio_data_in_rev & prio_data_in_rev_compl;
		
		c_reverse
		  #(.width(width))
		prio_data_out_revr
		  (.data_in(prio_data_out_rev),
		   .data_out(prio_data_out));
		
		wire [0:width-1] prio_mask_out_rev;
		assign prio_mask_out_rev
		  = prio_data_in_rev ^ prio_data_in_rev_compl;
		
		c_reverse
		  #(.width(width))
		prio_mask_out_revr
		  (.data_in(prio_mask_out_rev),
		   .data_out(prio_mask_out));
		
	     end
	   
	   assign data_out_by_prio[prio*width:(prio+1)*width-1] = prio_data_out;
	   assign mask_out_by_prio[prio*width:(prio+1)*width-1] = prio_mask_out;
	   
	end
      
      if(num_priorities == 1)
	begin
	   assign data_out = data_out_by_prio;
	   assign mask_out = mask_out_by_prio;
	end
      else if(num_priorities > 1)
	begin
	   if((num_priorities == 2) && !split_output_by_prio)
	     begin
		
		wire hi_prio_reqs;
		assign hi_prio_reqs = |data_in[0:width-1];
		
		assign data_out = hi_prio_reqs ? 
				  data_out_by_prio[0:width-1] : 
				  data_out_by_prio[width:2*width-1];
		
		assign mask_out = hi_prio_reqs ?
				  mask_out_by_prio[0:width-1] :
				  mask_out_by_prio[width:2*width-1];
		
	     end
	   else if(((num_priorities == 2) && split_output_by_prio) ||
		    (num_priorities > 2))
	     begin
		
		wire [0:num_priorities-1] valid_prio;
		c_mat_mult
		  #(.dim1_width(num_priorities),
		    .dim2_width(width),
		    .dim3_width(1),
		    .prod_op(`BINARY_OP_AND),
		    .sum_op(`BINARY_OP_OR))
		valid_prio_mmult
		  (.input_a(data_in),
		   .input_b({width{1'b1}}),
		   .result(valid_prio));
		
		wire [0:num_priorities-1] req_prio;
		assign req_prio = {valid_prio[0:num_priorities-2], 1'b1};
		
		wire [0:num_priorities-1] req_prio_rev;
		c_reverse
		  #(.width(num_priorities))
		req_prio_rev_revr
		  (.data_in(req_prio),
		   .data_out(req_prio_rev));
		
		wire [0:num_priorities-1] gnt_prio_rev;
		assign gnt_prio_rev = req_prio_rev & -req_prio_rev;
		
		wire [0:num_priorities-1] gnt_prio;
		c_reverse
		  #(.width(num_priorities))
		gnt_piro_rev_revr
		  (.data_in(gnt_prio_rev),
		   .data_out(gnt_prio));
		
		if(split_output_by_prio)
		  begin
		     
		     wire [0:num_priorities*width-1] gnt_mask_prio;
		     c_mat_mult
		       #(.dim1_width(1),
			 .dim2_width(num_priorities),
			 .dim3_width(width),
			 .prod_op(`BINARY_OP_AND),
			 .sum_op(`BINARY_OP_OR))
		     gnt_mask_prio_mmult
		       (.input_a(gnt_prio),
			.input_b({width{1'b1}}),
			.result(gnt_mask_prio));
		     
		     assign data_out = data_out_by_prio & gnt_mask_prio;
		     assign mask_out = mask_out_by_prio & gnt_mask_prio;
		     
		  end
		else
		  begin
		     
		     c_select_1ofn
		       #(.num_ports(num_priorities),
			 .width(width))
		     data_out_sel
		       (.select(req_prio),
			.data_in(data_out_by_prio),
			.data_out(data_out));
		     
		     c_select_1ofn
		       #(.num_ports(num_priorities),
			 .width(width))
		     mask_out_sel
		       (.select(req_prio),
			.data_in(mask_out_by_prio),
			.data_out(mask_out));
		     
		  end
		
	     end
	   
	end
      
   endgenerate
   
endmodule
