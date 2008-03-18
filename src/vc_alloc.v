module vc_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1,

    /* supported architectures:
     0: separable, input-first, round-robin arbiters
     1: separable, input-first, matrix arbiters */
    parameter architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc,

    input [0:num_ports*num_vcs-1] elig_op_ovc,
    
    output wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_ip_ivc_op_ovc,
    output wire [0:num_ports*num_vcs-1] 		  gnt_ip_ivc);

   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_qual_ip_ivc_op_ovc;
   
   generate

      genvar 					  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   genvar ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		wire [0:num_ports*num_vcs-1] req_op_ovc;
		assign req_op_ovc
		  = req_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
				      (ip*num_vcs+ivc+1)*num_ports*num_vcs-1];

		wire [0:num_vcs*num_ports-1] req_qual_op_ovc;
		assign req_qual_op_ovc = req_op_ovc & elig_op_ovc;
	   
		assign req_qual_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*
					      num_vcs:
					      (ip*num_vcs+ivc+1)*num_ports*
					      num_vcs-1]
		    = req_qual_op_ovc;

	     end
	   
	end
      
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
		.req_ip_ivc_op_ovc(req_qual_ip_ivc_op_ovc),
		.gnt_ip_ivc_op_ovc(gnt_ip_ivc_op_ovc),
		.gnt_ip_ivc(gnt_ip_ivc));
	  end
	endcase

   endgenerate
   
endmodule
