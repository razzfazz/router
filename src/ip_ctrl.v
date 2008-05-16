module ip_ctrl
  (clk, reset, valid_in, data_in, vc_in, head_in, tail_in, vc_req_ivc_op,
   vc_req_ivc_ovc, vc_gnt_ivc, vc_gnt_ivc_ovc, sw_req_ive_op, sw_req_ivc_ovc,
   sw_gnt_ivc, cred_out_ivc, data_out, vc_out, head_out, tail_out);
   
   parameter address = 0;
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
`include "config.v"

   input clk;
   input reset;
   
   input [0:data_width-1] data_in;
   input [0:vc_idx_width-1] vc_in;
   input [0:type_width-1] type_in;
   
   output [0:num_vcs*num_ports-1] vc_req_ivc_op;
   output [0:num_vcs*num-vcs-1] vc_req_ivc_ovc;
   input [0:num-vcs-1] vc_gnt_ivc;
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   output [0:num_vcs*num_ports-1] sw_req_ivc_op;
   output [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   output [0:num_vcs*num_vcs-1] sw_req_ivc_ovc;
   input [0:num_vcs-1] sw_gnt_ivc;

   output [0:data_width-1] data_out;
   output [0:vc_idx_width-1] vc_out;
   output [0:type_width-1] type_out;
   
   output cred_valid_out;
   output [0:vc_idx_width-1] cred_vc_out;
   
   
   // --------------------------------------------------------------------------
   // -- input registers
   // --------------------------------------------------------------------------
   
   wire [0:data_width-1] data_s0_s, data_s0_q;
   assign data_s0_s = data_in;
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   data_s0q
     (.clk(clk),
      .reset(reset),
      .d(data_s0_s),
      .q(data_s0_q));
   
   wire [0:vc_idx_width-1] vc_s0_s, vc_s0_q;
   assign vc_s0_s = vc_in;
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   vc_s0q
     (.clk(clk),
      .reset(reset),
      .d(vc_s0_s),
      .q(vc_s0_q));

   wire [0:type_width-1] type_s0_s, type_s0_q;
   assign type_s0_s = type_in;
   dff
     #(.width(type_width),
       .reset_type(reset_type))
   type_s0q
     (.clk(clk),
      .reset(reset),
      .d(type_s0_s),
      .q(type_s0_q));

   
   // --------------------------------------------------------------------------
   // -- virtual channels
   // --------------------------------------------------------------------------

   wire [0:num_vcs*data_width-1] data_s1_ivc;
   wire [0:num_vcs*type_width-1] type_s1_ivc;
   
   generate
      
      genvar 			 ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire [0:type_width-1] type_munged;
	   assign type_munged = type_s0_q & {type_width{(vc_s0_q == ivc)}};

	   ivc_ctrl
	     #(.architecture(architecture),
	       .reset_type(reset_type))
	   ivcc
	     (.clk(clk),
	      .reset(reset),
	      .data_in(data_s0_q),
	      .type_in(type_munged),
	      .vc_req_op(vc_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]),
	      .vc_req_ovc(vc_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]),
	      .vc_gnt(vc_gnt_ivc[ivc]),
	      .vc_gnt_ovc(vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]),
	      .sw_req_op(sw_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]),
	      .sw_req_nonspec_op(sw_req_nonspec_ivc_op[ivc*num_ports:
						       (ivc+1)*num_ports-1]),
	      .sw_req_ovc(sw_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]),
	      .sw_gnt(sw_gnt_ivc[ivc]),
	      .data_out(data_s1_ivc[ivc*data_width:(ivc+1)*data_width-1]),
	      .type_out(type_s1_ivc[ivc*type_width:(ivc+1)*type_width-1]));
	   
	end
      
   endgenerate

   
   // --------------------------------------------------------------------------
   // -- select winning VC and forward to output
   // --------------------------------------------------------------------------

   wire [0:data_width-1] 	 data_s2_s, data_s2_q;
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
   
   
   wire [0:vc_idx_width-1] 	 vc_s2_s, vc_s2_q;
   encoder
     #(.num_ports(num_vcs))
   vc_enc
     (.data_in(sw_gnt_ivc),
      .data_out(vc_s2_s));
   dff
     #(.width(vc_idx_width)
       .reset_type(reset_type))
   vc_s2q
     (.clk(clk),
      .reset(reset),
      .d(vc_s2_s),
      .q(vc_s2_q));
   
   assign vc_out = vc_s2_q;
   
   
   wire [0:type_wdith-1] 	 type_s2_s, type_s2_q;
   // note: the following assumes that all-zeroes is the "no valid flit" type!
   select_1ofn
     #(.num_ports(num_vcs),
       .width(type_width))
   type_out_sel
     (.select(sw_gnt_ivc),
      .data_in(type_s1_ivc),
      .data_out(type_s2_s));
   dff
     #(.width(type_width),
       .reset_type(reset_type))
   type_s2q
     (.clk(clk),
      .reset(reset),
      .d(type_s2_s),
      .q(type_s2_q));
   
   assign type_out = type_s2_q;
   
   
   wire 			 cred_valid_s, cred_valid_q;
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
   
   
   wire [0:vc_idx_width-1] 	 cred_vc_s, cred_vc_q;
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
