module op_ctrl
  #(parameter num_vcs = 4,
    parameter num_buffers = 8,
    parameter num_ptes = 4,

    // see dff.v for supported values
    parameter reset_type = 1)
   (clk, reset, debit, debit_vc, debit_type, credit, credit_vc, credit_type,
    alloc_vc, free_vc, flit_free, packet_free, errors);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   
   input clk;
   input reset;
   input debit;
   input [0:vc_width-1] debit_vc;
   input debit_type;
   input credit;
   input [0:vc_width-1] credit_vc;
   input credit_type;
   input [0:num_vcs-1] alloc_vc;
   input [0:num_vcs-1] free_vc;
   output wire [0:num_vcs-1] flit_ready;
   output wire [0:num_vcs-1] packet_ready;
   output wire [0:num_vcs-1] errors;

   wire [0:num_vcs-1] 	     vc_busy_s, vc_busy_q;
   assign vc_busy_s = alloc_vc | (vc_busy_q & ~free_vc);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vc_busyq
     (.clk(clk),
      .reset(reset),
      .d(vc_busy_s),
      .q(vc_busy_q));
   
   wire [0:num_vcs-1] 	     errors_flit, errors_packet;

   assign errors = errors_flit | errors_packet | (vc_busy_q & alloc_vc);

   wire [0:num_vcs-1] 	     packet_credit;

   assign packet_ready = packet_credit & ~vc_busy_q;
   
   generate

      genvar 		     vc;
      for(vc = 0; vc < num_vcs; vc = vc + 1)
	begin:vcs

	   wire credit_this_vc;
	   assign credit_this_vc = credit && (credit_vc == vc);

	   wire debit_this_vc;
	   assign debit_this_vc = debit && (debit_vc == vc);

	   credit_tracker
	     #(.num_credits(num_buffers),
	       .reset_type(reset_type))
	   flit_ct
	     (.clk(clk),
	      .reset(reset),
	      .credit(credit_this_vc),
	      .debit(debit_this_vc),
	      .free(flit_ready[vc]),
	      .errors(errors_flit[vc]));

	   credit_tracker
	     #(.num_credits(num_ptes),
	       .reset_type(reset_type))
	   packet_ct
	     (.clk(clk),
	      .reset(reset),
	      .credit(credit_this_vc && credit_type),
	      .debit(debit_this_vc && debit_type),
	      .free(packet_credit[vc]),
	      .errors(errors_packet[vc]));

	end

   endgenerate

endmodule
