module sw_alloc
  (clk, reset, sw_req_nonspec_ip_ivc_op, sw_req_spec_ip_ivc_op, sw_gnt_ip_ivc,
   sw_gnt_ip_op);
   
`include "functions.v"   
`include "constants.v"
`include "config.v"
   
   parameter error_recovery = 0;
   
   parameter reset_type = reset_type_async;
   
   /*
    0: separable, input-first
    1: separable, output-first
    2: wavefront, mux inputs for priority
    3: wavefront, replicate logic for priorities
    4: wavefront, diagonal propagation allocator
    5: wavefront, rotate inputs for priority
    6: wavefront, false combinational loop
    */
   parameter allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter arbiter_type = 0;
   
   /*
    0: disable speculative switch allocation
    1: only use speculative grants if no non-speculative requests/grants present
    2: use speculative grants when not conflicting with non-spec requests
    3: use speculative grants when not conflicting with non-spec grants
    */
   parameter spec_level = 0;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] sw_req_nonspec_ip_ivc_op;
   input [0:num_ports*num_vcs*num_ports-1] sw_req_spec_ip_ivc_op;
   
   output [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   output [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   wire [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   wire [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   
   generate
      
      case(allocator_type)
	0:
	  begin
	     sw_alloc_core_sep_if
	       #(.reset_type(reset_type),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .error_recovery(error_recovery))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
		.sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
		.sw_gnt_ip_ivc(sw_gnt_ip_ivc),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
	1:
	  begin
	     sw_alloc_core_sep_of
	       #(.reset_type(reset_type),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .error_recovery(error_recovery))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
		.sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
		.sw_gnt_ip_ivc(sw_gnt_ip_ivc),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
	2, 3, 4, 5, 6:
	  begin
	     sw_alloc_core_wf
	       #(.reset_type(reset_type),
		 .allocator_type(allocator_type-2),
		 .arbiter_type(arbiter_type),
		 .spec_level(spec_level),
		 .error_recovery(error_recovery))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
		.sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
		.sw_gnt_ip_ivc(sw_gnt_ip_ivc),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
      endcase
      
   endgenerate
   
endmodule
