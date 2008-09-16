module rr_arbiter
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   parameter num_ports = 32;
   parameter reset_type = reset_type_async;
   
   
   input clk;
   input reset;
   input update;
   input [0:num_ports-1] req;
   output [0:num_ports-1] gnt;
   
   wire [0:num_ports-1] gnt;
   
   wire [0:num_ports-1] req_rev;
   wire [0:num_ports-2] prev_q;
   
   wire [0:num_ports-1] gnt_unqual;
   assign gnt_unqual = req_rev & -req_rev;
   
   wire [0:num_ports-2] mask;
   assign mask = prev_q - 1'b1;
   
   wire [0:num_ports-2] req_qual;
   assign req_qual = req_rev[0:num_ports-2] & ~mask;
   
   wire [0:num_ports-2] gnt_qual;
   assign gnt_qual = req_qual & -req_qual;
   
   wire [0:num_ports-1] gnt_rev;
   assign gnt_rev = |req_qual ? {gnt_qual, 1'b0} : gnt_unqual;
   
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
   
   generate   
      
      genvar 		i;
      for(i = 0; i < num_ports; i = i + 1)
	begin:connect
	   assign req_rev[i] = req[(num_ports-1)-i];
	   assign gnt[i] = gnt_rev[(num_ports-1)-i];
	end
      
   endgenerate
   
endmodule
