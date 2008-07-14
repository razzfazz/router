module sw_alloc
  (clk, reset, sw_req_ip_ivc, sw_req_ip_ivc_op, sw_gnt_ip_ivc, sw_gnt_ip_ivc_op,
   sw_gnt_ip_op);
   
`include "functions.v"   
`include "constants.v"
`include "config.v"
   
   // see dff.v for supported values
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, round-robin arbiters
    3: separable, output-first, matrix arbiters
    4: mux inputs based on prio, round-robin arbiters in final stage
    5: mux inputs based on prio, matrix arbiters in final stage
    6: replicate logic for prios, round-robin arbiters in final stage
    7: replicate logic for prios, matrix arbiters in final stage
    8: diagonal propagation arbiter, round-robin arbiters in final stage
    9: diagonal propagation arbiter, matrix arbiters in final stage
    10: rotate inputs based on prio, round-robin arbiters in final stage
    11: rotate inputs based on prio, matrix arbiters in final stage */
   parameter architecture = 0;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs-1] sw_req_ip_ivc;
   input [0:num_ports*num_vcs*num_ports-1] sw_req_ip_ivc_op;
   
   output [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_ports-1] sw_gnt_ip_ivc_op;
   output [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   wire [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_ports-1] sw_gnt_ip_ivc_op;
   wire [0:num_ports*num_ports-1] 	  sw_gnt_ip_op;
   
   
   generate
      
      case(architecture)
	0, 1:
	  begin
	     sw_alloc_core_sep_if
	       #(.reset_type(reset_type),
		 .architecture(architecture))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.sw_req_ip_ivc(sw_req_ip_ivc),
		.sw_req_ip_ivc_op(sw_req_ip_ivc_op),
		.sw_gnt_ip_ivc(sw_gnt_ip_ivc),
		.sw_gnt_ip_ivc_op(sw_gnt_ip_ivc_op),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
	2, 3:
	  begin
	     sw_alloc_core_sep_of
	       #(.reset_type(reset_type),
		 .architecture(architecture - 2))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.sw_req_ip_ivc(sw_req_ip_ivc),
		.sw_req_ip_ivc_op(sw_req_ip_ivc_op),
		.sw_gnt_ip_ivc(sw_gnt_ip_ivc),
		.sw_gnt_ip_ivc_op(sw_gnt_ip_ivc_op),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
	4, 5, 6, 7, 8, 9, 10, 11:
	  begin
	     sw_alloc_core_wf
	       #(.reset_type(reset_type),
		 .architecture(architecture - 4))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.sw_req_ip_ivc(sw_req_ip_ivc),
		.sw_req_ip_ivc_op(sw_req_ip_ivc_op),
		.sw_gnt_ip_ivc(sw_gnt_ip_ivc),
		.sw_gnt_ip_ivc_op(sw_gnt_ip_ivc_op),
		.sw_gnt_ip_op(sw_gnt_ip_op));
	  end
      endcase
      
   endgenerate
   
endmodule
