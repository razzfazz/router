module sw_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_clock_gating = 1,
    parameter use_output_first = 0,
    parameter use_allocator_type = 0) // 0 = separable, 1 = wavefront
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs-1] req_ip_ivc,
    input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op,

    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_ports-1] gnt_ip_op);
    
   generate
      
      if(use_allocator_type == 0)
	begin
	   if(use_output_first == 1)
	     begin
		
		sw_alloc_sep_of
		  #(.num_ports(num_ports),
		    .num_vcs(num_vcs),
		    .use_arbiter_type(use_arbiter_type),
		    .use_clock_gating(use_clock_gating))
		sep_of_sw_alloc
		  (.clk(clk),
		   .reset(reset),
		   .req_ip_ivc(req_ip_ivc),
		   .req_ip_ivc_op(req_ip_ivc_op),
		   .gnt_ip_ivc(gnt_ip_ivc),
		   .gnt_ip_op(gnt_ip_op));

	     end
	   else
	     begin
		
		sw_alloc_sep_of
		  #(.num_ports(num_ports),
		    .num_vcs(num_vcs),
		    .use_arbiter_type(use_arbiter_type),
		    .use_clock_gating(use_clock_gating))
		sep_if_sw_alloc
		  (.clk(clk),
		   .reset(reset),
		   .req_ip_ivc(req_ip_ivc),
		   .req_ip_ivc_op(req_ip_ivc_op),
		   .gnt_ip_ivc(gnt_ip_ivc),
		   .gnt_ip_op(gnt_ip_op));

	     end
	end
      else if(use_allocator_type == 1)
	begin
	   
	   sw_alloc_wf
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .use_arbiter_type(use_arbiter_type),
	       .use_clock_gating(use_clock_gating))
	   wf_sw_alloc
	     (.clk(clk),
	      .reset(reset),
	      .req_ip_ivc(req_ip_ivc),
	      .req_ip_ivc_op(req_ip_ivc_op),
	      .gnt_ip_ivc(gnt_ip_ivc),
	      .gnt_ip_op(gnt_ip_op));

	end
      
   endgenerate
   
endmodule
