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



// flit control signal decoding logic
module rtr_flit_ctrl_dec
  (clk, reset, active, flit_ctrl_in, header_info_in, flit_valid_out, 
   flit_head_out, flit_tail_out, sel_out_ivc);
   
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length = 4;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length = 1;
   
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   
   // width of counter for remaining flits
   localparam flit_ctr_width = clogb(max_payload_length);
   
   // width required for lookahead routing information
   parameter la_route_info_width = 4;
   
   // total number of bits required for storing routing information
   parameter route_info_width = 10;
   
   // total number of bits of header information encoded in header flit payload
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (la_route_info_width + route_info_width) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (la_route_info_width + route_info_width + payload_length_width) : 
       -1;
   
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
   
   // incoming flit control signals
   input [0:flit_ctrl_width-1] flit_ctrl_in;
   
   // header information associated with current flit
   input [0:header_info_width-1] header_info_in;
   
   // flit valid indicators for each VC
   output flit_valid_out;
   wire flit_valid_out;
   
   // flit is head flit
   output flit_head_out;
   wire flit_head_out;

   // flit is tail flit
   output flit_tail_out;
   wire flit_tail_out;
   
   // indicate which VC the current flit (if any) belongs to
   output [0:num_vcs-1] sel_out_ivc;
   wire [0:num_vcs-1] sel_out_ivc;
   
   
   generate
      
      case(packet_format)
	
	`PACKET_FORMAT_HEAD_TAIL,
	`PACKET_FORMAT_EXPLICIT_LENGTH:
	  begin
	     
	     assign flit_valid_out = flit_ctrl_in[0];
	     
	     if(num_vcs > 1)
	       begin
		  
		  wire [0:vc_idx_width-1] flit_vc_in;
		  assign flit_vc_in = flit_ctrl_in[1:1+vc_idx_width-1];
		  
		  c_decode
		    #(.num_ports(num_vcs))
		  sel_out_ivc_dec
		    (.data_in(flit_vc_in),
		     .data_out(sel_out_ivc));
		  
	       end
	     else
	       assign sel_out_ivc = 1'b1;
	     
	     assign flit_head_out = flit_ctrl_in[1+vc_idx_width+0];
	     
	     case(packet_format)
	       
	       `PACKET_FORMAT_HEAD_TAIL:
		 begin
		    
		    assign flit_tail_out = flit_ctrl_in[1+vc_idx_width+1];
		    
		 end
	       
	       `PACKET_FORMAT_EXPLICIT_LENGTH:
		 begin
		    
		    if(max_payload_length == 0)
		      begin
			 
			 if(max_payload_length == min_payload_length)
			   assign flit_tail_out = flit_head_out;
			 
			 // synopsys translate_off
			 else
			   begin
			      initial
			      begin
				 $display({"ERROR: The value of the ", 
					   "max_payload_length parameter ", 
					   "(%d) in module %m cannot be ",
					   "smaller than that of the ",
					   "min_payload_length parameter ",
					   "(%d)."},
					  max_payload_length, 
					  min_payload_length);
				 $stop;
			      end
			   end
			 // synopsys translate_on
			 
		      end
		    else if(max_payload_length == 1)
		      begin
			 
			 wire has_payload;
			 
			 if(max_payload_length > min_payload_length)
			   assign has_payload
			     = header_info_in[la_route_info_width+
					      route_info_width];
			 else if(max_payload_length == min_payload_length)
			   assign has_payload = 1'b1;
			 
			 // synopsys translate_off
			 else
			   begin
			      initial
			      begin
				 $display({"ERROR: The value of the ", 
					   "max_payload_length parameter ",
					   "(%d) in module %m cannot be ",
					   "smaller than that of the ",
					   "min_payload_length parameter ",
					   "(%d)."},
					  max_payload_length,
					  min_payload_length);
				 $stop;
			      end
			   end
			 // synopsys translate_on
			 
			 assign flit_tail_out = ~flit_head_out | ~has_payload;
			 
		      end
		    else
		      begin
			 
			 wire [0:num_vcs-1] flit_tail_out_ivc;
			 
			 genvar ivc;
			 
			 for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
			   begin:ivcs
			      
			      wire [0:flit_ctr_width-1] flit_ctr_next;
			      wire [0:flit_ctr_width-1] flit_ctr_s, flit_ctr_q;
			      assign flit_ctr_s
				= (flit_valid_out & sel_out_ivc[ivc]) ? 
				  (flit_head_out ? 
				   flit_ctr_next : 
				   (flit_ctr_q - 1'b1)) : 
				  flit_ctr_q;
			      c_dff
				#(.width(flit_ctr_width),
				  .reset_type(reset_type))
			      flit_ctrq
				(.clk(clk),
				 .reset(reset),
				 .active(active),
				 .d(flit_ctr_s),
				 .q(flit_ctr_q));
			      
			      wire 			flit_tail_out;
			      
			      if(max_payload_length > min_payload_length)
				begin
				   
				   wire [0:payload_length_width-1] 
				     payload_length;
				   assign payload_length
				     = header_info_in[la_route_info_width+
						      route_info_width:
						      la_route_info_width+
						      route_info_width+
						      payload_length_width-1];
				   
				   assign flit_ctr_next
				     = (min_payload_length - 1) + 
				       payload_length;
				   
				   if(min_payload_length == 0)
				     assign flit_tail_out = flit_head_out ? 
							    ~|payload_length : 
							    ~|flit_ctr_q;
				   else
				     assign flit_tail_out = ~flit_head_out & 
							    ~|flit_ctr_q;
				   
				end
			      else if(max_payload_length == min_payload_length)
				begin
				   assign flit_ctr_next
				     = max_payload_length - 1;
				   assign flit_tail_out
				     = ~flit_head_out & ~|flit_ctr_q;
				end
			      
			      // synopsys translate_off
			      else
				begin
				   initial
				   begin
				      $display({"ERROR: The value of the ", 
						"max_payload_length parameter ",
						"(%d) in module %m cannot be ",
						"smaller than that of the ",
						"min_payload_length ", 
						"parameter (%d)."},
					       max_payload_length,
					       min_payload_length);
				      $stop;
				   end
				end
			      // synopsys translate_on
			      
			      assign flit_tail_out_ivc[ivc] = flit_tail_out;
			      
			   end
			 
			 assign flit_tail_out
			   = |(sel_out_ivc & flit_tail_out_ivc);
			 
		      end
		    
		 end
	       
	     endcase
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
