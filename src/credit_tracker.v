module credit_tracker
  (clk, reset, debit, credit, free);
   
   parameter num_credits = 8;
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
   input clk;
   input reset;
   input debit;
   input credit;
   output free;
   
`include "functions.v"
   
   localparam credit_idx_width = clogb(num_credits);
   
   wire        set_cred, reset_cred;
   wire        cred_s, cred_q;
   assign cred_s = set_cred | (cred_q & ~reset_cred);
   dff
     #(.width(1),
       .reset_type(reset_type),
       .reset_value(1'b1))
   credq
     (.clk(clk),
      .reset(reset),
      .d(cred_s),
      .q(cred_q));
   assign free = cred_q;
   
   
   wire        error;
   
   generate
      
      if(num_credits == 1)
	begin
	   
	   assign set_cred = credit & ~debit;
	   assign reset_cred = debit & ~credit;
	   
	   assign error = cred_q ? credit : debit;
	   
	end
      else
	begin
	   
	   wire [0:credit_idx_width-1] cred_count_q;
	   wire 		       cred_count_zero;
	   assign cred_count_zero = ~|cred_count_q;
	   
	   wire 		       incr_count;
	   assign incr_count = credit & ~debit & cred_q;
	   
	   wire 		       decr_count;
	   assign decr_count = debit & ~credit & ~cred_count_zero;
	   
	   wire [0:credit_idx_width-1] cred_count_s;
	   assign cred_count_s = cred_count_q - decr_count + incr_count;
	   dff
	     #(.width(credit_idx_width),
	       .reset_type(reset_type),
	       .reset_value(num_credits-1))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   assign set_cred = credit & ~debit & ~cred_q;
	   assign reset_cred = debit & ~credit & cred_count_zero;
	   
	   assign error = (!cred_q && debit) ||
			  ((cred_count_q == num_credits-1) && credit);
	   
	end
      
   endgenerate
   
endmodule
