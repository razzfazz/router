module vc_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_clock_gating = 1,
    parameter use_allocator_type = 0) // 0 = separable
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc,
    
    output wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_ip_ivc_op_ovc);

   generate

      if(use_allocator_type == 0)
	begin
	   vc_alloc_sep_if
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .use_arbiter_type(use_arbiter_type),
	       .use_clock_gating(use_clock_gating))
	   sep_if_vc_alloc
	     (.clk(clk),
	      .reset(reset),
	      .req_ip_ivc_op_ovc(req_ip_ivc_op_ovc),
	      .gnt_ip_ivc_op_ovc(gnt_ip_ivc_op_ovc));
	end
      
   endgenerate
   
endmodule
