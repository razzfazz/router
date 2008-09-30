module op_ctrl
  (clk, reset, cred_valid_in, cred_vc_in, vc_gnt_ovc, flit_valid_in, flit_vc_in,
   flit_tail_in, elig_ovc, free_ovc, free_ivc, cred_ovc, error);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "config_utils.v"
   
   parameter checker_enable = 1;
   parameter checker_capture_mode = 0;
   
   parameter reset_type = reset_type_async;
   
   // select method for credit signaling from output to input controller
   //  0: indicate credit level to input side
   //  1: push credits to input side one by one
   parameter credit_handling_type = 1;
   
   // number of bits to be used for credit level reporting
   // (note: must be less than or equal to cred_count_width as given below)
   // (note: this parameter is only used if credit_handling_type=0)
   parameter cred_level_width = 2;
   
   localparam [0:cred_level_width-1] max_cred_level
     = (1 << cred_level_width) - 1;
   
   localparam [0:cred_level_width-1] free_reset_value
     = (clogb(num_buffers+1) > cred_level_width) ?
       {cred_level_width{1'b1}} :
       num_buffers;
   
   localparam [0:num_vcs*num_vcs-1] mask_ivc_ovc
     = create_mask_ivc_ovc(restrict_vcs);
   
   // width for full range of credit count ([0:num_credits])
   localparam cred_count_width = clogb(num_buffers+1);
   
   // width of counter for credits waiting to be sent to input controller
   localparam cred_hold_width = clogb(num_buffers);
   
   
   input clk;
   input reset;
   
   input cred_valid_in;
   input [0:vc_idx_width-1] cred_vc_in;
   
   input [0:num_vcs-1] vc_gnt_ovc;
   
   input flit_valid_in;
   input [0:vc_idx_width-1] flit_vc_in;
   input flit_tail_in;
   
   output [0:num_vcs-1] elig_ovc;
   output [0:num_vcs*cred_level_width-1] free_ovc;
   output [0:num_vcs-1] free_ivc;
   output [0:num_vcs-1] cred_ovc;
   
   output error;
   
   wire [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs*cred_level_width-1] free_ovc;
   wire [0:num_vcs-1] 		       free_ivc;
   wire [0:num_vcs-1] 		       cred_ovc;
   
   wire 			       error;
   
   
   wire [0:num_vcs-1] 		       next_cred_ovc;
   wire [0:num_vcs-1] 		       error_hct_ovc;
   wire [0:num_vcs*2-1] 	       error_cred_ovc;
   
   generate
      
      genvar 			       ovc;
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   assign credit = cred_valid_in && (cred_vc_in == ovc);
	   
	   wire debit;
	   assign debit = flit_valid_in && (flit_vc_in == ovc);
	   
	   wire head_credit;
	   wire [0:cred_count_width-1] cred_count_s;
	   
	   if(num_headers > 1)
	     begin
		
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
		
		assign head_credit = |(tail_queue_q & pop_mask) & credit;
		
	     end
	   else
	     begin
		
		// if we can only have one packet per buffer, we can accept the
		// next one once the buffer has been emptied
		assign head_credit = credit && (cred_count_s == num_buffers);
		
	     end
	   
	   wire 			    vc_gnt;
	   assign vc_gnt = vc_gnt_ovc[ovc] & elig_ovc[ovc];
	   
	   wire 			    head_debit;
	   assign head_debit = vc_gnt;
	   
	   // track header credits using stock credit tracker module
	   wire 			    head_free;
	   wire 			    head_free_early;
	   wire 			    error_hct;
	   credit_tracker
	     #(.num_credits(num_headers),
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
	   
	   assign error_hct_ovc[ovc] = error_hct;
	   
	   wire [0:cred_count_width-1] cred_count_q;
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
	   
	   assign next_cred_ovc[ovc] = |cred_count_s;
	   
	   wire [0:1] 		       error_cred;
	   assign error_cred = {(cred_count_q == num_buffers) && credit,
				(cred_count_q == 0) && debit};
	   
	   assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
	   
	   case(credit_handling_type)
	     0:
	       begin
		  wire [0:cred_level_width-1] free_s, free_q;
		  assign free_s = (cred_count_s > max_cred_level) ?
				  max_cred_level :
				  cred_count_s[cred_count_width-
					       cred_level_width:
					       cred_count_width-1];
		  dff
		    #(.width(cred_level_width),
		      .reset_type(reset_type),
		      .reset_value(free_reset_value))
		  freeq
		    (.clk(clk),
		     .reset(reset),
		     .d(free_s),
		     .q(free_q));
		  
		  assign free_ovc[ovc*cred_level_width:
				  (ovc+1)*cred_level_width-1]
			   = free_q;
	       end
	     1:
	       begin
		  assign free_ovc[ovc*cred_level_width:
				  (ovc+1)*cred_level_width-1]
			   = {cred_level_width{1'b0}};
	       end
	   endcase
	   
	   wire 		       set_allocated;
	   assign set_allocated = vc_gnt;
	   
	   wire 		       reset_allocated;   
	   assign reset_allocated = debit & flit_tail_in;
	   
	   // per-output-VC bit indicating whether it is available for
	   // assignment
	   wire 		       allocated_s, allocated_q;
	   assign allocated_s
	     = set_allocated | (allocated_q & ~reset_allocated);
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   allocatedq
	     (.clk(clk),
	      .reset(reset),
	      .d(allocated_s),
	      .q(allocated_q));
	   
	   wire 		       elig_s;
	   
	   case(credit_handling_type)
	     0:
	       begin
		  assign cred_ovc[ovc] = 1'b0;
		  assign elig_s = ~allocated_s & head_free_early;
	       end
	     1:
	       begin
		  
		  wire [0:cred_hold_width-1]  cred_hold_copy;
		  assign cred_hold_copy
		    = cred_count_s[(cred_count_width-cred_hold_width):
				   cred_count_width-1] - |cred_count_s;
		  
		  wire [0:cred_hold_width-1]  cred_hold_s, cred_hold_q;
		  assign cred_hold_s
		    = reset_allocated ?
		      cred_hold_copy :
		      (vc_gnt | allocated_q) ?
		      (cred_hold_q - (|cred_hold_q & ~credit)) :
		      cred_hold_q;
		  dff
		    #(.width(cred_hold_width),
		      .reset_type(reset_type),
		      .reset_value(num_buffers-1))
		  cred_holdq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_hold_s),
		     .q(cred_hold_q));
		  
		  wire 			      cred_s, cred_q;
		  assign cred_s = |cred_hold_s | credit;
		  dff
		    #(.width(1),
		      .reset_type(reset_type),
		      .reset_value(1))
		  credq
		    (.clk(clk),
		     .reset(reset),
		     .d(cred_s),
		     .q(cred_q));
		  
		  assign cred_ovc[ovc] = cred_q;
		  
		  assign elig_s
		    = ~allocated_s & head_free_early & next_cred_ovc[ovc];
		  
	       end
	   endcase
	   
	   wire 			      elig_q;
	   dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .reset_value(1'b1))
	   eligq
	     (.clk(clk),
	      .reset(reset),
	      .d(elig_s),
	      .q(elig_q));
	   
	   assign elig_ovc[ovc] = elig_q;
	   
	end
      
      wire [0:num_vcs*2-1] 	       errors_out_ovc;
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
      
      case(credit_handling_type)
	0:
	  begin
	     genvar 			       ivc;
	     for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	       begin:ivcs
		  
		  wire port_cred_s, port_cred_q;
		  assign port_cred_s
		    = &(next_cred_ovc | ~mask_ivc_ovc[ivc*num_vcs:
						      (ivc+1)*num_vcs-1]);
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
	  end
	1:
	  begin
	     assign free_ivc = {num_vcs{1'b0}};
	  end  
      endcase
      
   endgenerate
   
endmodule
