// $Id$

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
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

// module to filter output port requests based on turn restrictions
module port_filter
  (route_op_in, inc_rc, route_op_out, error);
   
`include "constants.v"
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // nuber of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   parameter num_nodes_per_router = 4;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 1;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // ID of current port
   parameter port_id = 0;
   
   // current traffic class
   parameter traffic_class = 0;
   
   // current routing class
   parameter routing_class = 0;
   
   // unmasked output port
   input [0:num_ports-1] route_op_in;

   // if we have reached our destination for the current routing class, 
   // increment the routing class (unless it's already the highest)
   input inc_rc;
   
   // filtered output port
   output [0:num_ports-1] route_op_out;
   wire [0:num_ports-1] route_op_out;
   
   // internal error condition detected
   output error;
   wire error;   
   
   wire [0:num_ports-1] route_restricted_op;
   wire [0:num_ports-1] error_op;
   
   generate
   
      genvar 					op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   // packets in the lower routing classes can only go back out through
	   // the same port they came in on if the current router is the
	   // destination router for their current routing class (this cannot 
	   // happen for packets in the highest routing class); for the
	   // flattened butterfly, this applies to all links in the same
	   // dimension
	   if((op < (num_ports - num_nodes_per_router)) &&
	      (((routing_function_type == `ROUTING_FUNCTION_TYPE_MESH) &&
		(op == port_id)) ||
	       ((routing_function_type == `ROUTING_FUNCTION_TYPE_FBFLY) &&
		((op / num_neighbors_per_dim) == 
		 (port_id / num_neighbors_per_dim)))))
	     begin
		if(routing_class == (num_routing_classes - 1))
		  begin
		     assign route_restricted_op[op] = 1'b0;
		     assign error_op[op] = route_op_in[op];
		  end
		else
		  begin

		     // we could mask this by inc_rc; however, the goal of port 
		     // filtering is to allow synthesis to take advantage of
		     // turn restrictions in optimizing the design, so from this
		     // point of view, masking here would be counterproductive;
		     // also, note that we don't actually recover from illegal 
		     // port requests -- packets just remain in the input buffer
		     // forever; consequently, we save the gate and don't mask 
		     // here
		     assign route_restricted_op[op]
			      = route_op_in[op] /* & inc_rc*/;
		     
		     assign error_op[op] = route_op_in[op] & ~inc_rc;
		  end
	     end
	   
	   // only packets in the highest routing class can go to the injection/
	   // ejection ports; also, a packet coming in on an injection/ejection 
	   // port should never exit the router on the same injection/ejection 
	   // port
	   else if((op >= (num_ports - num_nodes_per_router)) &&
		   ((routing_class < (num_routing_classes - 1)) ||
		    (op == port_id)))
	     begin
		assign route_restricted_op[op] = 1'b0;
		assign error_op[op] = route_op_in[op];
	     end
	   
	   // remaining port requests are valid
	   else
	     begin
		assign route_restricted_op[op] = route_op_in[op];
		assign error_op[op] = 1'b0;
	     end
	   
	end
      
      if(restrict_turns != 0)
	assign route_op_out = route_restricted_op;
      else
	assign route_op_out = route_op_in;
      
   endgenerate
   
   assign error = |error_op;
   
endmodule
