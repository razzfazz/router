module ovc_ctrl
  (clk, reset, push, pop, alloc, free, elig, cred);
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
`include "config.v"
   
   input clk;
   input reset;
   
   input push;
   input pop;

   input alloc;
   input free;
   
   output elig;
   output cred;
   
   wire 	elig_s, elig_q;
   assign elig_s = (elig_q | free) & ~alloc;
   dff
     #(.width(1),
       .reset_type(reset_type))
   eligq
     (.clk(clk),
      .reset(reset),
      .d(elig_s),
      .q(elig_q));

   assign elig = elig_q;

   wire 	error;
   assign error = alloc & ~free & ~elig_q;

   credit_tracker
     #(.num_credits(num_buffers),
       .reset_type(reset_type))
   ct
     (.clk(clk),
      .reset(reset),
      .credit(pop),
      .debit(push),
      .free(cred));
   
endmodule
