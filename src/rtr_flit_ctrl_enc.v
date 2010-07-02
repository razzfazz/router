// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
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



// flit control signal encoding logic
module rtr_flit_ctrl_enc
  (clk, reset, active, flit_valid_in, flit_head_in, flit_tail_in, sel_in_ivc, 
   flit_ctrl_out);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   input active;
   
   // flit valid indicator
   input flit_valid_in;
   
   // flit is a head flit
   input flit_head_in;
   
   // flit is a tail flit
   input flit_tail_in;
   
   // indicate which VC the current flit (if any) belongs to
   output [0:num_vcs-1] sel_in_ivc;
   wire [0:num_vcs-1] 	sel_in_ivc;
   
   // outgoing flit control signals
   output [0:flit_ctrl_width-1] flit_ctrl_out;
   wire [0:flit_ctrl_width-1] 	flit_ctrl_out;
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     assign flit_ctrl_out[0] = flit_valid_in;
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] flit_vc_out;
		  c_encode
		    #(.num_ports(num_vcs))
		  flit_vc_out_dec
		    (.data_in(sel_in_ivc),
		     .data_out(flit_vc_out));
		  
		  assign flit_ctrl_out[1:1+vc_idx_width-1] = flit_vc_out;
		  
	       end
	     
	     assign flit_ctrl_out[1+vc_idx_width+0] = flit_head_in;
	     
	     case(packet_format)
	       
	       `PACKET_FORMAT_HEAD_TAIL:
		 begin
		    
		    assign flit_ctrl_out[1+vc_idx_width+1] = flit_tail_in;
		    
		 end
	       
	       `PACKET_FORMAT_EXPLICIT_LENGTH:
		 begin
		    
		    // packet length information in the header stays intact, so
		    // no need to do anything here
		    
		 end
	       
	     endcase
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
