module credit_tracker
  (clk, reset, debit, credit, free, free_early, error);
   
`include "constants.v"
`include "functions.v"
   
   // total number of credits
   parameter num_credits = 8;
   
   // minimum number of credits to assert "free"
   // NOTE: must be greater than zero and smaller than or equal to num_credits!
   parameter min_credits = 1;
   
   parameter checker_enable = 1;
   parameter checker_capture_mode = 0;
   
   parameter reset_type = reset_type_async;
   
   localparam credit_idx_width = clogb(num_credits);
   
   // width for full range of credit count ([0:num_credits])
   localparam true_idx_width = clogb(num_credits+1);
   
   
   input clk;
   input reset;
   
   // inputs for subtracting and adding credits
   input debit;
   input credit;
   
   // at least min_credits credits available?
   output free;
   
   // 1 cycle early version of "free"
   output free_early;
   
   output error;
   
   wire free;
   wire free_early;
   
   wire error;
   
   
   wire set_cred, reset_cred;
   wire cred_s, cred_q;
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
   assign free_early = cred_s;
   
   wire incr;
   assign incr = credit & ~debit;

   wire decr;
   assign decr = debit & ~credit;

   wire [0:1] errors;
   wire [0:true_idx_width-1] true_count;
   
   generate

      // if we only have a single credit, we don't need explicit credit counter
      // NOTE: if num_credits == 1, we must have min_credits == 1!
      if(num_credits == 1)
	begin
	   
	   assign set_cred = incr;
	   assign reset_cred = decr;
	   
	   assign errors = {cred_q & credit,
			    ~cred_q & debit};
	   assign true_count = cred_q;
	   
	end

      // if we have more than one credit, we need an extra counter to keep track
      else
	begin
	   
	   wire [0:credit_idx_width-1] cred_count_q;
	   wire 		       cred_count_min;
	   assign cred_count_min = (cred_count_q == (min_credits-1));
	   
	   wire 		       incr_count;
	   assign incr_count = incr & ~(~cred_q & cred_count_min);
	   
	   wire 		       decr_count;
	   assign decr_count = decr & ~(cred_q & cred_count_min);
	   
	   wire [0:credit_idx_width-1] cred_count_s;
	   assign cred_count_s
	     = (cred_count_q - decr_count) + incr_count;
	   dff
	     #(.width(credit_idx_width),
	       .reset_type(reset_type),
	       .reset_value(num_credits-1))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   assign set_cred = incr & ~cred_q & cred_count_min;
	   assign reset_cred = decr & cred_q & cred_count_min;
	   
	   assign errors = {cred_q && (cred_count_q == num_credits-1) && credit,
			    !cred_q && (cred_count_q == 0) && debit};
	   assign true_count = cred_count_q + cred_q;
	   
	end
      
   endgenerate
   
   wire [0:1] errors_out;
   checker
     #(.num_errors(2),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors),
      .errors_out(errors_out));
   
   assign error = |errors_out;
   
endmodule
