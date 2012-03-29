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
// matrix arbiter
//==============================================================================

module c_matrix_arbiter
  (clk, reset, active, req_pr, gnt_pr, gnt, update);
   
`include "c_constants.v"
   
   // number of inputs ports
   parameter num_ports = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // perform masking between priorities
   parameter mask_priorities = 1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // request vector
   input [0:num_priorities*num_ports-1] req_pr;
   
   // grant vector
   output [0:num_priorities*num_ports-1] gnt_pr;
   wire [0:num_priorities*num_ports-1] 	 gnt_pr;
   
   // merged grant vector
   output [0:num_ports-1] 		 gnt;
   wire [0:num_ports-1] 		 gnt;
   
   // update port priorities
   input 				 update;
   
   generate
      
      if(num_ports == 1)
	begin
	   
	   c_lod
	     #(.width(num_priorities),
	       .num_priorities(1))
	   gnt_lod
	     (.data_in_pr(req_pr),
	      .data_out_pr(gnt_pr),
	      .data_out(),
	      .mask_out());
	   
	   assign gnt = |req_pr;
	   
	end
      else if(num_ports > 1)
	begin
	   
	   wire [0:num_priorities*num_ports-1] gnt_intm_pr;
	   wire [0:num_ports-1] 	       gnt_intm;
	   
	   // port priority matrix
	   wire [0:num_ports*num_ports-1] state;
	   
	   genvar 			  row;
	   
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:rows
		
		genvar prio;
		
		for(prio = 0; prio < num_priorities; prio = prio + 1)
		  begin:prios
		     
		     // grant requests if we have precedence over all other 
		     // requestors
		     assign gnt_intm_pr[prio*num_ports+row] 
		       = req_pr[prio*num_ports+row] &
			 (&(state[row*num_ports:(row+1)*num_ports-1] | 
			    ~req_pr[prio*num_ports:(prio+1)*num_ports-1]));
		     
		  end
		
		genvar col;
		
		for(col = 0; col < num_ports; col = col + 1)
		  begin:cols
		     
		     // lower triangle has inverted values of transposed upper 
		     // triangle
		     if(col < row)
		       assign state[row*num_ports+col]
			 = ~state[col*num_ports+row];
		     
		     // diagonal has all ones
		     else if(col == row)
		       assign state[row*num_ports+col] = 1'b1;
		     
		     // upper triangle has actual registers
		     else if(col > row)
		       begin
			  
			  wire state_s, state_q;
			  assign state_s
			    = update ? 
			      ((state_q | gnt_intm[col]) & ~gnt_intm[row]) : 
			      state_q;
			  c_dff
			    #(.width(1),
			      .reset_type(reset_type),
			      .reset_value(1'b1))
			  stateq
			    (.clk(clk),
			     .reset(reset),
			     .active(active),
			     .d(state_s),
			     .q(state_q));
			  
			  assign state[row*num_ports+col] = state_q;
			  
		       end
		     
		  end
		
	     end
	   
	   if(num_priorities == 1)
	     begin
		assign gnt_intm = gnt_intm_pr;
		assign gnt_pr = gnt_intm_pr;
		assign gnt = gnt_intm;
	     end
	   else if(num_priorities > 1)
	     begin
		
		wire [0:num_priorities-1] sel_pr;
		
		if(num_priorities == 2)
		  assign sel_pr
		    = {|req_pr[0:num_ports-1], ~|req_pr[0:num_ports-1]};
		else if(num_priorities > 2)
		  begin
		     
		     wire [0:num_priorities-1] valid_pr;
		     c_mat_mult
		       #(.dim1_width(num_priorities),
			 .dim2_width(num_ports),
			 .dim3_width(1),
			 .prod_op(`BINARY_OP_AND),
			 .sum_op(`BINARY_OP_OR))
		     valid_pr_mmult
		       (.input_a(req_pr),
			.input_b({num_ports{1'b1}}),
			.result(valid_pr));
		     
		     wire [0:num_priorities-1] any_req_pr;
		     assign any_req_pr = {valid_pr[0:num_priorities-2], 1'b1};
		     
		     c_lod
		       #(.width(num_priorities),
			 .num_priorities(1))
		     sel_pr_lod
		       (.data_in_pr(any_req_pr),
			.data_out_pr(sel_pr),
			.data_out(),
			.mask_out());
		     
		  end
		
		c_select_1ofn
		  #(.num_ports(num_priorities),
		    .width(num_ports))
		gnt_intm_sel
		  (.select(sel_pr),
		   .data_in(gnt_intm_pr),
		   .data_out(gnt_intm));
		
		if(mask_priorities)
		  begin
		     
		     wire [0:num_priorities*num_ports-1] gnt_mask_pr;
		     c_mat_mult
		       #(.dim1_width(num_priorities),
			 .dim2_width(1),
			 .dim3_width(num_ports),
			 .prod_op(`BINARY_OP_AND),
			 .sum_op(`BINARY_OP_OR))
		     gnt_mask_pr_mmult
		       (.input_a(sel_pr),
			.input_b({num_ports{1'b1}}),
			.result(gnt_mask_pr));
		     
		     assign gnt_pr = gnt_intm_pr & gnt_mask_pr;
		     assign gnt = gnt_intm;
		     
		  end
		else
		  begin
		     
		     assign gnt_pr = gnt_intm_pr;
		     
		     c_binary_op
		       #(.num_ports(num_priorities),
			 .width(num_ports),
			 .op(`BINARY_OP_OR))
		     gnt_or
		       (.data_in(gnt_intm_pr),
			.data_out(gnt));
		     
		  end
		
	     end
	   
	end
      
   endgenerate
   
endmodule
