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


// module for aligning flags for a class of VCs
module rtr_vc_align
  (flag_ocvc, inc_rc, flag_ovc);
   
   
`include "c_functions.v"
`include "c_constants.v"
   
   
   //---------------------------------------------------------------------------
   // parameters
   //---------------------------------------------------------------------------
   
   // number of message classes (e.g. request, reply)
   parameter num_message_classes = 2;
   
   // number of resource classes (e.g. minimal, adaptive)
   parameter num_resource_classes = 2;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // resource class to which this VC belongs
   localparam resource_class
     = (vc_id / num_vcs_per_class) % num_resource_classes;
   
   // packet class to which this VC belongs
   localparam packet_class = (vc_id / num_vcs_per_class) % num_packet_classes;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   // bit field for flags for VCs in current packet class
   input [0:num_vcs_per_class-1] flag_ocvc;
   
   // will the resource class be incremented at the current router?
   input inc_rc;
   
   // flags zero-extended to account for all VCs 
   output [0:num_vcs-1] flag_ovc;
   wire [0:num_vcs-1] flag_ovc;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   generate
      
      if(resource_class == (num_resource_classes-1))
	begin
	   
	   c_align
	     #(.data_width(num_vcs_per_class),
	       .dest_width(num_vcs),
	       .offset(packet_class*num_vcs_per_class))
	   flag_ovc_alg
	     (.data_in(flag_ocvc),
	      .dest_in({num_vcs{1'b0}}),
	      .data_out(flag_ovc));
	   
	end
      else
	begin
	   
	   c_align
	     #(.data_width(2*num_vcs_per_class),
	       .dest_width(num_vcs),
	       .offset(packet_class*num_vcs_per_class))
	   flag_ovc_alg
	     (.data_in({{num_vcs_per_class{~inc_rc}} & flag_ocvc,
			{num_vcs_per_class{inc_rc}} & flag_ocvc}),
	      .dest_in({num_vcs{1'b0}}),
	      .data_out(flag_ovc));

	end
      
   endgenerate
   
endmodule
