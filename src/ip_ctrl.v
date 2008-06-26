module ip_ctrl
  (clk, reset, valid_in, data_in, vc_in, head_in, tail_in, vc_req_ivc_op,
   vc_req_ivc_ovc, vc_gnt_ivc, vc_gnt_ivc_ovc, sw_req_ivc_op,
   sw_req_nonspec_ivc_op, sw_req_ivc_ovc, sw_gnt_ivc, valid_out, data_out,
   vc_out, head_out, tail_out, cred_valid_out, cred_vc_out);
   
   
`include "config.v"
`include "constants.v"
   
   
   parameter reset_type = reset_type_async;
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   input clk;
   input reset;
   
   input valid_in;
   input [0:data_width-1] data_in;
   input [0:vc_idx_width-1] vc_in;
   input head_in;
   input tail_in;
   
   output wire [0:num_vcs*num_ports-1] vc_req_ivc_op;
   output wire [0:num_vcs*num_vcs-1]   vc_req_ivc_ovc;
   input [0:num_vcs-1] vc_gnt_ivc;
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   output wire [0:num_vcs*num_ports-1] sw_req_ivc_op;
   output wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   output wire [0:num_vcs*num_vcs-1]   sw_req_ivc_ovc;
   input [0:num_vcs-1] sw_gnt_ivc;
   
   output wire 			       valid_out;
   output wire [0:data_width-1]        data_out;
   output wire [0:vc_idx_width-1]      vc_out;
   output wire 			       head_out;
   output wire 			       tail_out;
   
   output wire 			       cred_valid_out;
   output wire [0:vc_idx_width-1]      cred_vc_out;
   
   
   // --------------------------------------------------------------------------
   // -- input registers
   // --------------------------------------------------------------------------
   
   wire 			       valid_s0_s, valid_s0_q;
   assign valid_s0_s = valid_in;
   dff
     #(.width(1),
       .reset_type(reset_type))
   valid_s0q
     (.clk(clk),
      .reset(reset),
      .d(valid_s0_s),
      .q(valid_s0_q));
   
   wire [0:data_width-1] 	       data_s0_s, data_s0_q;
   assign data_s0_s = data_in;
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   data_s0q
     (.clk(clk),
      .reset(reset),
      .d(data_s0_s),
      .q(data_s0_q));
   
   wire [0:vc_idx_width-1] 	       vc_s0_s, vc_s0_q;
   assign vc_s0_s = vc_in;
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   vc_s0q
     (.clk(clk),
      .reset(reset),
      .d(vc_s0_s),
      .q(vc_s0_q));
   
   wire 			       head_s0_s, head_s0_q;
   assign head_s0_s = head_in;
   dff
     #(.width(1),
       .reset_type(reset_type))
   head_s0q
     (.clk(clk),
      .reset(reset),
      .d(head_s0_s),
      .q(head_s0_q));
   
   wire 			       tail_s0_s, tail_s0_q;
   assign tail_s0_s = tail_in;
   dff
     #(.width(1),
       .reset_type(reset_type))
   tail_s0q
     (.clk(clk),
      .reset(reset),
      .d(tail_s0_s),
      .q(tail_s0_q));
   
   
   // --------------------------------------------------------------------------
   // -- virtual channels
   // --------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 		       valid_s1_ivc;
   wire [0:num_vcs*data_width-1]       data_s1_ivc;
   wire [0:num_vcs*vc_idx_width-1]     vc_s1_ivc;
   wire [0:num_vcs-1] 		       head_s1_ivc;
   wire [0:num_vcs-1] 		       tail_s1_ivc;
   
   generate
      
      genvar 			       ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire valid_munged;
	   assign valid_munged = valid_s0_q && (vc_s0_q == ivc);
	   
	   ivc_ctrl
	     #(.address(address),
	       .reset_type(reset_type))
	   ivcc
	     (.clk(clk),
	      .reset(reset),
	      .valid_in(valid_munged),
	      .data_in(data_s0_q),
	      .vc_in(ivc),
	      .head_in(head_s0_q),
	      .tail_in(tail_s0_q),
	      .vc_req_op(vc_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]),
	      .vc_req_ovc(vc_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]),
	      .vc_gnt(vc_gnt_ivc[ivc]),
	      .vc_gnt_ovc(vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]),
	      .sw_req_op(sw_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]),
	      .sw_req_nonspec_op(sw_req_nonspec_ivc_op[ivc*num_ports:
						       (ivc+1)*num_ports-1]),
	      .sw_req_ovc(sw_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]),
	      .sw_gnt(sw_gnt_ivc[ivc]),
	      .valid_out(valid_s1_ivc[ivc]),
	      .data_out(data_s1_ivc[ivc*data_width:(ivc+1)*data_width-1]),
	      .vc_out(vc_s1_ivc[ivc*vc_idx_width:(ivc+1)*vc_idx_width-1]),
	      .head_out(head_s1_ivc[ivc]),
	      .tail_out(tail_s1_ivc[ivc]));
	   
	end
      
   endgenerate
   
   
   // --------------------------------------------------------------------------
   // -- select winning VC and forward to output
   // --------------------------------------------------------------------------
   
   wire 	valid_s2_s, valid_s2_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   valid_out_sel
     (.select(sw_gnt_ivc),
      .data_in(valid_s1_ivc),
      .data_out(valid_s2_s));
   dff
     #(.width(1),
       .reset_type(reset_type))
   valid_S2q
     (.clk(clk),
      .reset(reset),
      .d(valid_s2_s),
      .q(valid_s2_q));

   assign valid_out = valid_s2_q;

   
   wire [0:data_width-1] data_s2_s, data_s2_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(data_width))
   data_out_sel
     (.select(sw_gnt_ivc),
      .data_in(data_s1_ivc),
      .data_out(data_s2_s));
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   data_s2q
     (.clk(clk),
      .reset(reset),
      .d(data_s2_s),
      .q(data_s2_q));
   
   assign data_out = data_s2_q;
   
   
   wire [0:vc_idx_width-1] vc_s2_s, vc_s2_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(vc_idx_width))
   vc_out_sel
     (.select(sw_gnt_ivc),
      .data_in(vc_s1_ivc),
      .data_out(vc_s2_s));
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   vc_s2q
     (.clk(clk),
      .reset(reset),
      .d(vc_s2_s),
      .q(vc_s2_q));
   
   assign vc_out = vc_s2_q;
   
   
   wire 		   head_s2_s, head_s2_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   head_out_sel
     (.select(sw_gnt_ivc),
      .data_in(head_s1_ivc),
      .data_out(head_s2_s));
   dff
     #(.width(1),
       .reset_type(reset_type))
   head_s2q
     (.clk(clk),
      .reset(reset),
      .d(head_s2_s),
      .q(head_s2_q));
   
   assign head_out = head_s2_q;
   
   
   wire 		   tail_s2_s, tail_s2_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   tail_out_sel
     (.select(sw_gnt_ivc),
      .data_in(tail_s1_ivc),
      .data_out(tail_s2_s));
   dff
     #(.width(1),
       .reset_type(reset_type))
   tail_s2q
     (.clk(clk),
      .reset(reset),
      .d(tail_s2_s),
      .q(tail_s2_q));
   
   assign tail_out = tail_s2_q;
   
   
   wire 		      cred_valid_s, cred_valid_q;
   assign cred_valid_s = |sw_gnt_ivc;
   dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign cred_valid_out = cred_valid_q;
   
   
   wire [0:vc_idx_width-1]    cred_vc_s, cred_vc_q;
   encoder
     #(.num_ports(num_vcs))
   cred_vc_enc
     (.data_in(sw_gnt_ivc),
      .data_out(cred_vc_s));
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   cred_vcq
     (.clk(clk),
      .reset(reset),
      .d(cred_vc_s),
      .q(cred_vc_q));
   
   assign cred_vc_out = cred_vc_q;
   
endmodule
