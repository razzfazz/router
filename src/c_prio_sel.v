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



// priority select logic
module c_prio_sel
  (priorities, select);
   
`include "c_functions.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   // number of priority levels
   parameter num_priorities = 16;
   
   // width of priority fields
   localparam prio_width = clogb(num_priorities);
   
   // priority values
   input [0:num_ports*prio_width-1] priorities;
   
   // vector representing maximum priority ports
   output [0:num_ports-1] 	    select;
   wire [0:num_ports-1] 	    select;
   
   wire [0:prio_width-1] 	    prio_some_set;
   c_binary_op
     #(.num_ports(num_ports),
       .width(prio_width),
       .op(`BINARY_OP_OR))
   prio_some_set_or
     (.data_in(priorities),
      .data_out(prio_some_set));
   
   wire [0:prio_width-1] 	    prio_some_unset;
   c_binary_op
     #(.num_ports(num_ports),
       .width(prio_width),
       .op(`BINARY_OP_NAND))
   prio_some_unset_nand
     (.data_in(priorities),
      .data_out(prio_some_unset));
   
   // find bit positions that are not identical for all ports
   wire [0:prio_width-1] 	    prio_diffs;
   assign prio_diffs = prio_some_set & prio_some_unset;
   
   wire [0:prio_width-1] 	    first_prio_diff;
   c_fp_arbiter
     #(.num_ports(prio_width))
   first_prio_diff_arb
     (.req(prio_diffs),
      .gnt(first_prio_diff));
   
   // for each priority bit, list all ports that have this bit set
   wire [0:prio_width*num_ports-1]  prio_ports;
   c_interleave
     #(.width(num_ports*prio_width),
       .num_blocks(num_ports))
   prio_ports_intl
     (.data_in(priorities),
      .data_out(prio_ports));
   
   // select all those ports who have the first differing bit set
   wire [0:num_ports-1] 	    max_ports;
   c_select_1ofn
     #(.num_ports(prio_width),
       .width(num_ports))
   max_ports_sel
     (.select(first_prio_diff),
      .data_in(prio_ports),
      .data_out(max_ports));
   
   // check if all inputs have the same priority
   wire 			    all_same_prio;
   assign all_same_prio = ~|prio_diffs;
   
   // if so, we must override the result
   assign select = max_ports | {num_ports{all_same_prio}};
   
endmodule
