module sw_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_allocator_type = 0, // 0 = separable, 1 = wavefront
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_output_first = 0,
    parameter use_clock_gating = 1)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc,

    input [0:num_ports*num_vcs-1] cred_op_ovc,

    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_ports-1] gnt_ip_op);

   wire [0:num_ports*num_vcs*num_ports-1] req_qual_ip_ivc_op;

   genvar 				  i;
   
   generate
   
      for(i = 0; i < num_ports*num_vcs; i = i + 1)
	begin:input_vcs

	   wire [0:num_ports*num_vcs-1] req_op_ovc;

	   assign req_op_ovc 
	     = req_ip_ivc_op_ovc[i*num_ports*num_vcs:(i+1)*num_ports*num_vcs-1];

	   wire [0:num_vcs*num_ports-1] req_qual_op_ovc;

	   assign req_qual_op_ovc = req_op_ovc & cred_op_ovc;
	   
	   wire [0:num_vcs*num_ports-1] req_qual_ovc_op;

	   interleaver
	     #(.width(num_ports*num_vcs),
	       .num_blocks(num_ports))
	   intl_req_qual
	     (.data_in(req_qual_op_ovc),
	      .data_out(req_qual_ovc_op));
	     
	   wire [0:num_ports-1] 	req_qual_op;

	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   or_req_qual_ovc
	     (.data_in(req_qual_ovc_op),
	      .data_out(req_qual_op));
	   
	   assign req_qual_ip_ivc_op[i*num_ports:(i+1)*num_ports-1]
		    = req_qual_op;
	   
	end

   endgenerate

   generate
      
      if(use_allocator_type == 0)
	begin
	   if(use_output_first == 1)
	     begin
		
		sw_alloc_core_sep_of
		  #(.num_ports(num_ports),
		    .num_vcs(num_vcs),
		    .use_arbiter_type(use_arbiter_type),
		    .use_clock_gating(use_clock_gating))
		core_sep_of
		  (.clk(clk),
		   .reset(reset),
		   .req_ip_ivc_op(req_qual_ip_ivc_op),
		   .gnt_ip_ivc(gnt_ip_ivc),
		   .gnt_ip_op(gnt_ip_op));

	     end
	   else
	     begin
		
		sw_alloc_core_sep_if
		  #(.num_ports(num_ports),
		    .num_vcs(num_vcs),
		    .use_arbiter_type(use_arbiter_type),
		    .use_clock_gating(use_clock_gating))
		core_sep_if
		  (.clk(clk),
		   .reset(reset),
		   .req_ip_ivc_op(req_qual_ip_ivc_op),
		   .gnt_ip_ivc(gnt_ip_ivc),
		   .gnt_ip_op(gnt_ip_op));

	     end
	end
      else if(use_allocator_type == 1)
	begin
	   
	   sw_alloc_core_wf
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .use_arbiter_type(use_arbiter_type),
	       .use_clock_gating(use_clock_gating))
	   core_wf
	     (.clk(clk),
	      .reset(reset),
	      .req_ip_ivc_op(req_qual_ip_ivc_op),
	      .gnt_ip_ivc(gnt_ip_ivc),
	      .gnt_ip_op(gnt_ip_op));

	end
      
   endgenerate
   
endmodule
