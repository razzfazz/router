module vc_alloc
  (clk, reset, vc_req_ip_ivc_op, vc_req_ip_ivc_ovc, vc_gnt_ip_ivc,
   vc_gnt_ip_ivc_ovc, vc_gnt_op_ovc);
   
`include "functions.v"   
`include "config.v"
`include "constants.v"
   
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, round-robin arbiters
    3: separable, output-first, matrix arbiters */
   parameter architecture = 0;
   
   localparam architecture_sep_if = architecture;
   localparam architecture_sep_of = architecture - 2;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] vc_req_ip_ivc_ovc;
   
   output [0:num_ports*num_vcs-1] vc_gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs-1] vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 	vc_gnt_op_ovc;
   
   
   generate
      
      case(architecture)
	0, 1:
	  begin
	     vc_alloc_core_sep_if
	       #(.reset_type(reset_type),
		 .architecture(architecture_sep_if))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.vc_gnt_ip_ivc(vc_gnt_ip_ivc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	  end
	2, 3:
	  begin
	     vc_alloc_core_sep_of
	       #(.reset_type(reset_type),
		 .architecture(architecture_sep_of))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.vc_gnt_ip_ivc(vc_gnt_ip_ivc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	  end
      endcase
      
   endgenerate
   
endmodule
