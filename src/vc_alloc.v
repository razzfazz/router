module vc_alloc
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, elig_op_ovc, gnt_ip_ivc,
   gnt_ip_ivc_ovc);
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, round-robin arbiters
    3: separable, output-first, matrix arbiters */
   parameter architecture = 0;
   
`include "config.v"

   localparam architecture_sep_if = architecture;
   localparam architecture_sep_of = architecture;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   
   
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
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc));
	  end
	2, 3:
	  begin
	     vc_alloc_core_sep_of
	       #(.reset_type(reset_type),
		 .architecture(architecture_sep_of))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
		.gnt_op_ovc(gnt_op_ovc));
	  end
	endcase

   endgenerate
   
endmodule
