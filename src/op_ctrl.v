module op_ctrl
  (clk, reset, cred_valid_in, cred_vc_in, vc_gnt_ovc, flit_valid_in, flit_vc_in,
   flit_tail_in, elig_ovc, free_ovc, free_plus1_ovc, free_ivc, error);

`include "functions.v"
`include "config.v"
`include "constants.v"
`include "config_utils.v"
   
   parameter checker_enable = 1;
   parameter checker_capture_mode = 0;
   
   parameter reset_type = reset_type_async;
   
   // use dedicated registers to store port credit summary bits per input VC
   parameter dedicated_free_ivc_regs = 0;
   
   // minimum number of available buffers required to consider VC free
   parameter buffer_free_threshold = 2;
   
   localparam [0:num_vcs*num_vcs-1] mask_ivc_ovc
     = create_mask_ivc_ovc(restrict_vcs);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_buffers+1);
   
   
   input clk;
   input reset;
   
   input cred_valid_in;
   input [0:vc_idx_width-1] cred_vc_in;
   
   input [0:num_vcs-1] vc_gnt_ovc;
   
   input flit_valid_in;
   input [0:vc_idx_width-1] flit_vc_in;
   input flit_tail_in;
   
   output [0:num_vcs-1] elig_ovc;
   output [0:num_vcs-1] free_ovc;
   output [0:num_vcs-1] free_plus1_ovc;
   output [0:num_vcs-1] free_ivc;
   
   output error;
   
   wire [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs-1] free_ovc;
   wire [0:num_vcs-1] free_plus1_ovc;
   wire [0:num_vcs-1] free_ivc;
   
   wire 	      error;
   
   
   wire [0:num_vcs-1] set_elig_ovc;
   wire [0:num_vcs-1] reset_elig_ovc;
   
   // per-output-VC bit indicating whether it is available for assignment
   wire [0:num_vcs-1] elig_ovc_s, elig_ovc_q;
   assign elig_ovc_s = set_elig_ovc | (elig_ovc_q & ~reset_elig_ovc);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type),
       .reset_value({num_vcs{1'b1}}))
   elig_ovcq
     (.clk(clk),
      .reset(reset),
      .d(elig_ovc_s),
      .q(elig_ovc_q));
   
   wire [0:num_vcs-1] set_cred_ovc;
   wire [0:num_vcs-1] reset_cred_ovc;
   
   // per-out-ut-VC bit indicating whether there is sufficient credit available
   // to accept a new packet
   wire [0:num_vcs-1] cred_ovc_s, cred_ovc_q;
   assign cred_ovc_s = set_cred_ovc | (cred_ovc_q & ~reset_cred_ovc);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type),
       .reset_value({num_vcs{1'b1}}))
   cred_ovcq
     (.clk(clk),
      .reset(reset),
      .d(cred_ovc_s),
      .q(cred_ovc_q));
   
   assign free_ovc = cred_ovc_q;
   
   wire [0:num_vcs-1] set_cred_plus1_ovc;
   wire [0:num_vcs-1] reset_cred_plus1_ovc;

   // per-out-ut-VC bit indicating whether there is sufficient credit available
   // to accept two packets (to be used when one is already in flight)
   wire [0:num_vcs-1] cred_plus1_ovc_s, cred_plus1_ovc_q;
   assign cred_plus1_ovc_s
     = set_cred_plus1_ovc | (cred_plus1_ovc_q & ~reset_cred_plus1_ovc);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type),
       .reset_value({num_vcs{1'b1}}))
   cred_plus1_ovcq
     (.clk(clk),
      .reset(reset),
      .d(cred_plus1_ovc_s),
      .q(cred_plus1_ovc_q));
   
   assign free_plus1_ovc = cred_plus1_ovc_q;
   
   wire [0:num_vcs-1] error_hct_ovc;
   wire [0:num_vcs*2-1] error_cred_ovc;
   
   generate
      
      genvar 	      ovc;
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   assign credit = cred_valid_in && (cred_vc_in == ovc);
	   
	   wire debit;
	   assign debit = flit_valid_in && (flit_vc_in == ovc);
	   
	   wire [0:num_buffers-1] push_mask;
	   wire [0:num_buffers-1] pop_mask;
	   
	   wire [0:num_buffers-1] tail_queue_s, tail_queue_q;
	   assign tail_queue_s
	     = (tail_queue_q & ~({num_buffers{credit}} & pop_mask)) |
	       ({num_buffers{debit & flit_tail_in}} & push_mask);
	   dff
	     #(.width(num_buffers),
	       .reset_type(reset_type))
	   tail_queueq
	     (.clk(clk),
	      .reset(reset),
	      .d(tail_queue_s),
	      .q(tail_queue_q));
	   
	   wire [0:buffer_idx_width-1] push_ptr, push_ptr_next;
	   mod_ctr
	     #(.num_values(num_buffers),
	       .reset_type(reset_type))
	   push_ptr_ctr
	     (.clk(clk),
	      .reset(reset),
	      .incr(debit),
	      .value(push_ptr),
	      .next_value(push_ptr_next));
	   
	   decoder
	     #(.num_ports(num_buffers))
	   push_mask_dec
	     (.data_in(push_ptr),
	      .data_out(push_mask));
	   
	   wire [0:buffer_idx_width-1] pop_ptr, pop_ptr_next;
	   mod_ctr
	     #(.num_values(num_buffers),
	       .reset_type(reset_type))
	   pop_ptr_ctr
	     (.clk(clk),
	      .reset(reset),
	      .incr(credit),
	      .value(pop_ptr),
	      .next_value(pop_ptr_next));
	   
	   decoder
	     #(.num_ports(num_buffers))
	   pop_mask_dec
	     (.data_in(pop_ptr),
	      .data_out(pop_mask));
	   
	   wire 		       head_credit;
	   assign head_credit = |(tail_queue_q & pop_mask) & credit;
	   
	   wire 		       head_debit;
	   assign head_debit = vc_gnt_ovc[ovc] & elig_ovc[ovc];
	   
	   // track header credits using stock credit tracker module
	   wire 		       head_free;
	   wire 		       head_free_early;
	   wire 		       error_hct;
	   credit_tracker
	     #(.num_credits(num_headers),
	       .min_credits(1),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type))
	   hct
	     (.clk(clk),
	      .reset(reset),
	      .credit(head_credit),
	      .debit(head_debit),
	      .free(head_free),
	      .free_early(head_free_early),
	      .error(error_hct));
	   
	   assign set_elig_ovc[ovc] = debit & flit_tail_in;
	   assign reset_elig_ovc[ovc] = head_debit;
	   
	   assign elig_ovc[ovc] = elig_ovc_q[ovc] & head_free;
	   
	   assign error_hct_ovc[ovc] = error_hct;
	   
	   // for overall credits, we can reuse part of the logic that keeps
	   // track of tails
	   wire [0:num_buffers-1]      set_mask;
	   assign set_mask
	     = (push_mask >> (buffer_free_threshold - 1)) |
	       (push_mask << (num_buffers - (buffer_free_threshold - 1)));
	
	   wire 		       incr;
	   assign incr = credit & ~debit;

	   wire 		       decr;
	   assign decr = debit & ~credit;
	   
	   wire [0:num_buffers-1]      reset_mask;
	   assign reset_mask
	     = (pop_mask << buffer_free_threshold) |
	       (pop_mask >> (num_buffers - buffer_free_threshold));
	   
	   assign set_cred_ovc[ovc] = |(pop_mask & set_mask) & incr;
	   assign reset_cred_ovc[ovc] = |(push_mask & reset_mask) & decr;
	   
	   wire [0:num_buffers-1]      set_plus1_mask;
	   assign set_plus1_mask
	     = (push_mask >> buffer_free_threshold) |
	       (push_mask << (num_buffers - buffer_free_threshold));
	   
	   wire [0:num_buffers-1]      reset_plus1_mask;
	   assign reset_plus1_mask
	     = (pop_mask << (buffer_free_threshold + 1)) |
	       (pop_mask >> (num_buffers - (buffer_free_threshold + 1)));
	   
	   assign set_cred_plus1_ovc[ovc]
		    = |(pop_mask & set_plus1_mask) & incr;
	   assign reset_cred_plus1_ovc[ovc]
		    = |(push_mask & reset_plus1_mask) & decr;
	   
	   wire [0:cred_count_width-1]   cred_count_s, cred_count_q;
	   assign cred_count_s = cred_count_q + credit - debit;
	   dff
	     #(.width(cred_count_width),
	       .reset_type(reset_type),
	       .reset_value(num_buffers))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   wire [0:1] 			 error_cred;
	   assign error_cred = {(cred_count_q == num_buffers) && credit,
				(cred_count_q == 0) && debit};
	   
	   assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
	   
	end
      
      wire [0:num_vcs*2-1] 		 errors_out_ovc;
      checker
	#(.num_errors(num_vcs*2),
	  .enable(checker_enable),
	  .capture_mode(checker_capture_mode),
	  .reset_type(reset_type))
      chk
	(.clk(clk),
	 .reset(reset),
	 .errors_in(error_cred_ovc),
	 .errors_out(errors_out_ovc));
      
      assign error = |error_hct_ovc | |errors_out_ovc;
      
      genvar 				 ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   if(dedicated_free_ivc_regs)
	     begin
		
		wire port_cred_s, port_cred_q;
		assign port_cred_s
		  = &(cred_ovc_s |
		      ~mask_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]);
		dff
		  #(.width(1),
		    .reset_type(reset_type))
		port_credq
		  (.clk(clk),
		   .reset(reset),
		   .d(port_cred_s),
		   .q(port_cred_q));
		
		assign free_ivc[ivc] = port_cred_q;
		
	     end
	   else
	     begin
		
		assign free_ivc[ivc]
			 = &(cred_ovc_q |
			     ~mask_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]);
		
	     end
	   
	end
      
   endgenerate
   
endmodule
