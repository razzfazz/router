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
// module for extracting the flags for a given port and resource class
//==============================================================================

module rtr_vc_flags_mux
  (route_op, route_orc, flags_op_ovc, flags_ocvc);
      
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
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // ID of current input VC
   parameter vc_id = 0;
   
   
   //---------------------------------------------------------------------------
   // derived parameters
   //---------------------------------------------------------------------------
   
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // message class to which this VC belongs
   localparam message_class
     = (vc_id / (num_resource_classes*num_vcs_per_class)) % num_message_classes;
   
   
   //---------------------------------------------------------------------------
   // interface
   //---------------------------------------------------------------------------
   
   // destination port
   input [0:num_ports-1] route_op;
   
   // destination resource class
   input [0:num_resource_classes-1] route_orc;
   
   // bit field of output VC flags of interest
   input [0:num_ports*num_vcs-1]    flags_op_ovc;
   
   // subset of bits that we are interested in
   output [0:num_vcs_per_class-1]   flags_ocvc;
   wire [0:num_vcs_per_class-1]     flags_ocvc;
   
   
   //---------------------------------------------------------------------------
   // implementation
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 		    flags_ovc;
   c_select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs))
   flags_ovc_sel
     (.select(route_op),
      .data_in(flags_op_ovc),
      .data_out(flags_ovc));
   
   wire [0:num_resource_classes*num_vcs_per_class-1] flags_orc_ocvc;
   assign flags_orc_ocvc
     = flags_ovc[message_class*num_resource_classes*num_vcs_per_class:
		 (message_class+1)*num_resource_classes*num_vcs_per_class-1];
   
   generate
      
      if(num_resource_classes == 1)
	assign flags_ocvc = flags_orc_ocvc;
      else if(num_resource_classes > 1)
	begin
	   
	   c_select_1ofn
	     #(.num_ports(num_resource_classes),
	       .width(num_vcs_per_class))
	   flags_ocvc_sel
	     (.select(route_orc),
	      .data_in(flags_orc_ocvc),
	      .data_out(flags_ocvc));
	   
	end
      
   endgenerate
   
endmodule
