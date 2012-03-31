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
// generic arbiter
//==============================================================================

module c_arbiter
  (clk, reset, active, req_pr, gnt_pr, gnt, update);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   // number of priority levels
   parameter num_priorities = 1;
   
   // perform masking between priorities
   parameter mask_priorities = 1;
   
   // number fo bits required to select a port
   localparam port_idx_width = clogb(num_ports);
   
   // select type of arbiter to use
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
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
      
      case(arbiter_type)
	
	`ARBITER_TYPE_ROUND_ROBIN:
	  begin
	     
	     c_rr_arbiter
	       #(.num_ports(num_ports),
		 .num_priorities(num_priorities),
		 .mask_priorities(mask_priorities),
		 .reset_type(reset_type))
	     rr_arb
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req_pr(req_pr),
		.gnt_pr(gnt_pr),
		.gnt(gnt),
		.update(update));
	     
	  end
	
	`ARBITER_TYPE_MATRIX:
	  begin
	     
	     c_matrix_arbiter
	       #(.num_ports(num_ports),
		 .num_priorities(num_priorities),
		 .mask_priorities(mask_priorities),
		 .reset_type(reset_type))
	     matrix_arb
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.req_pr(req_pr),
		.gnt_pr(gnt_pr),
		.gnt(gnt),
		.update(update));
	     
	  end
	
	`ARBITER_TYPE_DW_FCFS:
	  begin
	     
	     // synopsys translate_off
	     
	     if(num_priorities > 1)
	       begin
		  
		  initial
		    begin
		       $display({"ERROR: DesignWare FCFS arbiter does not ", 
				 "support multiple priorities."});
		       $stop;
		    end
		  
	       end
	     
	     // synopsys translate_on
	     
	     if(num_ports == 1)
	       assign gnt_pr = req_pr;
	     else if(num_ports > 1)
	       begin
		  
		  wire enable;
		  assign enable = active & update;
		  
		  wire rst_n;
		  if(reset_type == `RESET_TYPE_ASYNC)
		    assign rst_n = ~reset;
		  else
		    assign rst_n = 1'b1;
		  
		  wire init_n;
		  if(reset_type == `RESET_TYPE_SYNC)
		    assign init_n = ~reset;
		  else
		    assign init_n = 1'b1;
		  
		  wire parked;
		  wire locked;
		  wire [0:port_idx_width-1] grant_index;
		  DW_arb_fcfs
		    #(.n(num_ports),
		      .park_mode(0),
		      .output_mode(0))
		  dw_fcfs_arb
		    (.clk(clk),
		     .rst_n(rst_n),
		     .init_n(init_n),
		     .enable(enable),
		     .request(req_pr),
		     .lock({num_ports{1'b0}}),
		     .mask({num_ports{1'b0}}),
		     .parked(parked),
		     .locked(locked),
		     .grant(gnt_pr),
		     .grant_index(grant_index));
		  
	       end
	     
	     assign gnt = gnt_pr;
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
