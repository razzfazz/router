$Id$
module sw_alloc
  (clk, reset, sw_req_nonspec_ip_ivc_op, sw_req_spec_ip_ivc_op,
   sw_gnt_nonspec_ip_ivc, sw_gnt_spec_ip_ivc, sw_gnt_ip_op);
   
`include "constants.v"
   
   // number of VCs
   parameter num_vcs = 4;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select implementation variant for wavefront allocator
   // (note: only valid for SW_ALLOCATOR_TYPE_WF_BASE+x
   localparam wf_allocator_type = sw_allocator_type-`SW_ALLOCATOR_TYPE_WF_BASE;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level
   parameter sw_spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // non-speculative switch requests
   input [0:num_ports*num_vcs*num_ports-1] sw_req_nonspec_ip_ivc_op;
   
   // speculative switch requests
   input [0:num_ports*num_vcs*num_ports-1] sw_req_spec_ip_ivc_op;
   
   // grants corresponding to non-speculative requests (to input controller)
   output [0:num_ports*num_vcs-1] sw_gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] sw_gnt_nonspec_ip_ivc;
   
   // grants corresponding to speculative requests (to input controller)
   output [0:num_ports*num_vcs-1] sw_gnt_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] sw_gnt_spec_ip_ivc;
   
   // crossbar control signals
   output [0:num_ports*num_ports-1] sw_gnt_ip_op;
   wire [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   
   generate
      
      case(sw_allocator_type)
	`SW_ALLOCATOR_TYPE_SEP_IF:
	  begin
	     sw_alloc_core_sep_if
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .sw_spec_level(sw_spec_level),
		 .reset_type(reset_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
		.sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
		.sw_gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
		.sw_gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
	`SW_ALLOCATOR_TYPE_SEP_OF:
	  begin
	     sw_alloc_core_sep_of
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .sw_spec_level(sw_spec_level),
		 .reset_type(reset_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
		.sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
		.sw_gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
		.sw_gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
      endcase
      
	if(sw_allocator_type >= `SW_ALLOCATOR_TYPE_WF_BASE)
	  begin
	     sw_alloc_core_wf
	       #(.num_vcs(num_vcs),
		 .num_ports(num_ports),
		 .wf_allocator_type(wf_allocator_type),
		 .arbiter_type(arbiter_type),
		 .sw_spec_level(sw_spec_level),
		 .reset_type(reset_type))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
		.sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
		.sw_gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
		.sw_gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
      
   endgenerate
   
endmodule
