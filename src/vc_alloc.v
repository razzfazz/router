module vc_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1,

    /* supported architectures:
     0: separable, input-first, round-robin arbiters
     1: separable, input-first, matrix arbiters
     2: separable, output-first, round-robin arbiters
     3: separable, output-first, matrix arbiters */
    parameter architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op,
    input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc,
    
    input [0:num_ports*num_vcs-1] elig_op_ovc,
    
    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc);
   
   generate

      case(architecture)
	0, 1:
	  begin
	     vc_alloc_core_sep_if
	       #(.num_ports(num_ports),
		 .num_vcs(num_vcs),
		 .reset_type(reset_type),
		 .hold_type(hold_type),
		 .architecture(architecture))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc));
	  end
/*	2, 3:
	  begin
	     vc_alloc_core_sep_of
	       #(.num_ports(num_ports),
		 .num_vcs(num_vcs),
		 .reset_type(reset_type),
		 .hold_type(hold_type),
		 .architecture(architecture-2))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_ip_ivc_op),
		.req_ip_ivc_ovc(req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_ivc_ovc(gnt_ip_ivc_ovc));
	  end*/
	endcase

   endgenerate
   
endmodule
