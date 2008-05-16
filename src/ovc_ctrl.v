module ovc_ctrl
  (clk, reset, push, head, tail, pop, elig, cred, errors);
   
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
   
   output [0:1] errors;
   
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

   wire 	packet_error;
   assign packet_error = alloc & ~free & ~elig_q;

   wire 	flit_error;
   credit_tracker
     #(.num_credits(num_credits),
       .reset_type(reset_type))
   ct
     (.clk(clk),
      .reset(reset),
      .credit(pop),
      .debit(push),
      .free(cred),
      .errors(flit_error));
   
   assign errors = {flit_error, packet_error};
   
endmodule
