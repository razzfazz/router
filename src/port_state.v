module port_state
  #(parameter num_vcs = 4,
    parameter num_buffers = 8,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1)
   (clk, reset, push, push_vc, pop, pop_vc, cred, errors);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   
   input clk;
   input reset;
   input push;
   input [0:vc_width-1] push_vc;
   input pop;
   input [0:vc_width-1] pop_vc;
   output wire [0:num_vcs-1] cred;
   output wire [0:num_vcs-1] errors;

   localparam buffer_width = clogb(num_buffers);

   wire [0:num_vcs-1] 	     set_cred, reset_cred;
   wire [0:num_vcs-1] 	     cred_s, cred_q;
   assign cred_s = set_cred | (cred_q & ~reset_cred);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type),
       .reset_value({num_vcs{1'b1}}),
       .hold_type(hold_type))
   credq
     (.clk(clk),
      .reset(reset),
      .enable(push || pop),
      .d(cred_s),
      .q(cred_q));
   assign cred = cred_q;

   generate

      genvar 		     vc;
      for(vc = 0; vc < num_vcs; vc = vc + 1)
	begin:vcs

	   wire push_this_vc;
	   assign push_this_vc = push && (push_vc == vc);

	   wire pop_this_vc;
	   assign pop_this_vc = pop && (pop_vc == vc);
	   
	   wire [0:buffer_width-1] cred_count_q;
	   wire cred_count_zero;
	   assign cred_count_zero = ~|cred_count_q;

	   wire incr_count;
	   assign incr_count = pop_this_vc && !push_this_vc && cred_q[vc];

	   wire decr_count;
	   assign decr_count = push_this_vc && !pop_this_vc && !cred_count_zero;
	   
	   wire [0:buffer_width-1] cred_count_s;
	   if(hold_type == 0)
	     assign cred_count_s = cred_q[vc] ?
				   cred_count_q - decr_count + incr_count :
				   cred_count_q;
	   else
	     assign cred_count_s = cred_count_q - decr_count + incr_count;
	   dff
	     #(.width(buffer_width),
	       .reset_type(reset_type),
	       .reset_value(num_buffers-1),
	       .hold_type(hold_type))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .enable(cred_q[vc]),
	      .d(cred_count_s),
	      .q(cred_count_q));

	   assign set_cred[vc] = pop_this_vc && !push_this_vc && !cred_q[vc];
	   assign reset_cred[vc] = push_this_vc && !pop_this_vc &&
				   cred_count_zero;

	   assign errors[vc] = (!cred_q[vc] && push_this_vc) ||
			       ((cred_count_q == num_buffers-1) && pop_this_vc);
	   
	end

   endgenerate

endmodule
