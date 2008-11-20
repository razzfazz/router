// $Id$
// generic round-robin arbiter
module rr_arbiter
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input ports
   parameter num_ports = 32;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // update priority vector
   input update;
   
   // vector of requests
   input [0:num_ports-1] req;
   
   // vector of grants
   output [0:num_ports-1] gnt;
   wire [0:num_ports-1] gnt;
   
   // reversed request vector
   wire [0:num_ports-1] req_rev;
   reversor
     #(.width(num_ports))
   req_rev_revr
     (.data_in(req),
      .data_out(req_rev));
   
   // current priority vector
   wire [0:num_ports-2] prev_q;
   
   // unqualified grant (ignorign priority)
   // This finds the first non-zero bit from the right (which is why we reverse
   // the request vector in the first place).
   wire [0:num_ports-1] gnt_rev_unqual;
   assign gnt_rev_unqual = req_rev & -req_rev;
   
   // mask all inputs to the right of current priority pointer
   // FIXME: Can we reverse the order of prev_q to avoid having to invert the 
   // mask later?
   wire [0:num_ports-2] mask;
   assign mask = prev_q - 1'b1;
   
   // generate qualified requests (w/ priority)
   wire [0:num_ports-2] req_rev_qual;
   assign req_rev_qual = req_rev[0:num_ports-2] & ~mask;
   
   // generate qualified grants (w/ priority)
   // This finds the first non-zero bit from the right, not including
   wire [0:num_ports-2] gnt_rev_qual;
   assign gnt_rev_qual = req_rev_qual & -req_rev_qual;
   
   // reversed grant vector
   wire [0:num_ports-1] gnt_rev;
   assign gnt_rev = |req_rev_qual ? {gnt_rev_qual, 1'b0} : gnt_rev_unqual;
   
   reversor
     #(.width(num_ports))
   gnt_revr
     (.data_in(gnt_rev),
      .data_out(gnt));
   
   // The worst-case effect of bit errors in prev_q is screwing up priorities 
   // until the next update; this only affects performance, not functionality,
   // so no need to add protection here.
   wire [0:num_ports-2] prev_s;
   assign prev_s = update ? gnt_rev[1:num_ports-1] : prev_q;
   dff
     #(.width(num_ports-1),
       .reset_type(reset_type))
   prevq
     (.clk(clk),
      .reset(reset),
      .d(prev_s),
      .q(prev_q));
   
endmodule
