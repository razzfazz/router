module vc_alloc
  (clk, reset, vc_req_ip_ivc_op, vc_req_ip_ivc_ovc, elig_op_ovc,
   vc_gnt_ip_ivc_ovc, vc_gnt_op_ovc);
   
`include "functions.v"   
`include "config.v"
`include "constants.v"
   
   parameter reset_type = reset_type_async;
   
   /*
    0: separable, input-first
    1: separable, output-first
    */
   parameter allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter arbiter_type = 0;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] vc_req_ip_ivc_ovc;
   
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   output [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 	vc_gnt_op_ovc;
   
   
   generate
      
      case(allocator_type)
	0:
	  begin
	     vc_alloc_core_sep_if
	       #(.reset_type(reset_type),
		 .arbiter_type(arbiter_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	  end
	1:
	  begin
	     vc_alloc_core_sep_of
	       #(.reset_type(reset_type),
		 .arbiter_type(arbiter_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	  end
      endcase
      
   endgenerate
   
endmodule
