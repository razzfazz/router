// $Id$

/*
Copyright (c) 2007-2010, Trustees of The Leland Stanford Junior University
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
// generic arbiter
//==============================================================================

module c_prio_arbiter
  (clk, reset, active, priorities, req, gnt, update);
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of input ports
   parameter num_ports = 32;
   
   // number of priority levels
   parameter num_priorities = 16;
   
   // select type of arbiter to use
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // width of priority fields
   localparam prio_width = clogb(num_priorities);
   
   // width of arbiter internal state
   localparam state_width
     = (arbiter_type == `ARBITER_TYPE_ROUND_ROBIN) ? num_ports :
       (arbiter_type == `ARBITER_TYPE_MATRIX) ? num_ports*num_ports :
       -1;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   input clk;
   input reset;
   input active;
   
   // priority values
   input [0:num_ports*prio_width-1] priorities;
   
   // request vector
   input [0:num_ports-1] 	    req;
   
   // grant vector
   output [0:num_ports-1] 	    gnt;
   wire [0:num_ports-1] 	    gnt;
   
   // update port priorities
   input 			    update;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire [0:state_width-1] 	    state;
   wire [0:num_priorities*num_ports-1] gnt_by_prio;
   wire [0:num_priorities-1] 	       prio_has_req;
   
   
   //---------------------------------------------------------------------------
   // priority levels in descending order
   //---------------------------------------------------------------------------
   
   genvar 			       prio;
   
   generate
      
      for(prio = 0; prio < (num_priorities - 1); prio = prio + 1)
	begin:prios
	   
	   wire [0:num_ports-1] prio_req;
	   
	   genvar 		port;
	   
	   for(port = 0; port < num_ports; port = port + 1)
	     begin:ports
		
		wire [0:prio_width-1] port_prio;
		assign port_prio
		  = priorities[port*prio_width:(port+1)*prio_width-1];
		
		assign prio_req[port]
		  = req[port] && (port_prio >= ((num_priorities - 1) - prio));
		
	     end
	   
	   wire [0:num_ports-1]       prio_gnt;
	   
	   case(arbiter_type)
	     
	     `ARBITER_TYPE_ROUND_ROBIN:
	       begin
		  
		  c_rr_arb_logic
		    #(.num_ports(num_ports))
		  rr_arb_log
		    (.state(state),
		     .req(prio_req),
		     .gnt(prio_gnt));
		  
	       end
	     
	     `ARBITER_TYPE_MATRIX:
	       begin
		  
		  c_matrix_arb_logic
		    #(.num_ports(num_ports))
		  matrix_arb_log
		    (.state(state),
		     .req(prio_req),
		     .gnt(prio_gnt));
		  
	       end
	     
	   endcase
	   
	   assign gnt_by_prio[prio*num_ports:(prio+1)*num_ports-1] = prio_gnt;
	   assign prio_has_req[prio] = |prio_req;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // lowest priority level and arbiter state
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1] 	    all_gnt;
   
   generate
      
      case(arbiter_type)
	
	`ARBITER_TYPE_ROUND_ROBIN:
	  begin
	     
	     c_rr_arb_logic
	       #(.num_ports(num_ports))
	     rr_arb_log
	       (.state(state),
		.req(req),
		.gnt(all_gnt));
	     
	     c_rr_arb_state
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     rr_arb_stat
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.update(update),
		.gnt(gnt),
		.state(state));
	     
	  end
	
	`ARBITER_TYPE_MATRIX:
	  begin
	     
	     c_matrix_arb_logic
	       #(.num_ports(num_ports))
	     matrix_arb_log
	       (.state(state),
		.req(req),
		.gnt(all_gnt));
	     
	     c_matrix_arb_state
	       #(.num_ports(num_ports),
		 .reset_type(reset_type))
	     matrix_arb_stat
	       (.clk(clk),
		.reset(reset),
		.active(active),
		.update(update),
		.gnt(gnt),
		.state(state));
	     
	  end
	
      endcase
      
   endgenerate
   
   assign gnt_by_prio[(num_priorities-1)*num_ports:num_priorities*num_ports-1]
     = all_gnt;
   
   // NOTE: The lowest priority level is always treated as active in order to
   // provide a fall-through for the case where no requests are present at all.
   
   assign prio_has_req[num_priorities-1] = 1'b1;
   
   
   //---------------------------------------------------------------------------
   // select grants from highest priority level that has any requests
   //---------------------------------------------------------------------------
   
   generate
      
      if(num_priorities == 2)
	begin
	   
	   assign gnt = |(req & priorities) ? 
			gnt_by_prio[0:num_ports-1] : 
			gnt_by_prio[num_ports:2*num_ports-1];
	   
	end
      else if(num_priorities > 2)
	begin
	   
	   wire [0:num_priorities-1] prio_sel;
	   c_lod
	     #(.width(num_priorities))
	   prio_sel_lod
	     (.data_in(prio_has_req),
	      .data_out(prio_sel));
	   
	   c_select_1ofn
	     #(.num_ports(num_priorities),
	       .width(num_ports))
	   gnt_sel
	     (.select(prio_sel),
	      .data_in(gnt_by_prio),
	      .data_out(gnt));
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // check parameters
   //---------------------------------------------------------------------------
   
   // synopsys translate_off
   
   generate
      
      if(arbiter_type == `ARBITER_TYPE_DW_FCFS)
	begin
	   
	   initial
	     begin
		$display({"ERROR: DesignWare FCFS arbiter does not support ", 
			  "multiple priorities."});
		$stop;
	     end
	   
	end
      
   endgenerate
   
   // synopsys translate_on
   
endmodule
