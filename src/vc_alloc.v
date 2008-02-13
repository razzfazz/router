module vc_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_clock_gating = 1,

    /* supported architectures:
     0: separable, input-first, round-robin arbiters
     1: separable, input-first, matrix arbiters */
    parameter use_architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc,

    input [0:num_ports*num_vcs-1] elig_op_ovc,
    
    output wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_ip_ivc_op_ovc,
    output wire [0:num_ports*num_vcs-1] 		  gnt_ip_ivc);

   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_qual_ip_ivc_op_ovc;
   
   genvar 				  i;
   
   generate
   
      for(i = 0; i < num_ports*num_vcs; i = i + 1)
	begin:input_vcs

	   wire [0:num_ports*num_vcs-1] req_op_ovc;

	   assign req_op_ovc 
	     = req_ip_ivc_op_ovc[i*num_ports*num_vcs:(i+1)*num_ports*num_vcs-1];

	   wire [0:num_vcs*num_ports-1] req_qual_op_ovc;

	   assign req_qual_op_ovc = req_op_ovc & elig_op_ovc;
	   
	   assign req_qual_ip_ivc_op_ovc[i*num_ports*num_vcs:
					 (i+1)*num_ports*num_vcs-1]
		    = req_qual_op_ovc;
	   
	end

   endgenerate

   generate

      if((use_architecture == 0) || (use_architecture == 1))
	begin
	   vc_alloc_core_sep_if
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .use_clock_gating(use_clock_gating),
	       .use_architecture(use_architecture))
	   core_sep_if
	     (.clk(clk),
	      .reset(reset),
	      .req_ip_ivc_op_ovc(req_qual_ip_ivc_op_ovc),
	      .gnt_ip_ivc_op_ovc(gnt_ip_ivc_op_ovc),
	      .gnt_ip_ivc(gnt_ip_ivc));
	end
      
   endgenerate
   
endmodule
