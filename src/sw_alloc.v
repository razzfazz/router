module sw_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1,
    
    /* supported architectures:
     0: separable, input-first, round-robin arbiters
     1: separable, input-first, matrix arbiters
     2: separable, output-first, round-robin arbiters
     3: separable, output-first, matrix arbiters
     4: rotate inputs based on prio, round-robin arbiters in final stage
     5: rotate inputs based on prio, matrix arbiters in final stage
     6: replicate logic for prios, round-robin arbiters in final stage
     7: replicate logic for prios, matrix arbiters in final stage
     8: diagonal propagation arbiter, round-robin arbiters in final stage
     9: diagonal propagation arbiter, matrix arbiters in final stage */
    parameter architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc,

    input [0:num_ports*num_vcs-1] cred_op_ovc,

    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_ports-1] gnt_ip_op);

   wire [0:num_ports*num_vcs*num_ports-1] req_qual_ip_ivc_op;
   
   generate

      genvar 				  ip;
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
		assign req_qual_op_ovc = req_op_ovc & cred_op_ovc;
		
		wire [0:num_vcs*num_ports-1] req_qual_ovc_op;
		interleaver
		  #(.width(num_ports*num_vcs),
		    .num_blocks(num_ports))
		intl_req_qual
		  (.data_in(req_qual_op_ovc),
		   .data_out(req_qual_ovc_op));
		
		wire [0:num_ports-1] 	     req_qual_op;
		or_nto1
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		or_req_qual_ovc
		  (.data_in(req_qual_ovc_op),
		   .data_out(req_qual_op));
	   
		assign req_qual_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
					  (ip*num_vcs+ivc+1)*num_ports-1]
			 = req_qual_op;
		
	     end
	   
	end
      
      case(architecture)
	0, 1:
	  begin
	     sw_alloc_core_sep_if
	       #(.num_ports(num_ports),
		 .num_vcs(num_vcs),
		 .reset_type(reset_type),
		 .hold_type(hold_type),
		 .architecture(architecture & 1))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_qual_ip_ivc_op),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_op(gnt_ip_op));
	  end
	2, 3:
	  begin
	     sw_alloc_core_sep_of
	       #(.num_ports(num_ports),
		 .num_vcs(num_vcs),
		 .reset_type(reset_type),
		 .hold_type(hold_type),
		 .architecture(architecture & 1))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_qual_ip_ivc_op),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_op(gnt_ip_op));
	  end
	4, 5, 6, 7, 8, 9:
	  begin
	     
	     sw_alloc_core_wf
	       #(.num_ports(num_ports),
		 .num_vcs(num_vcs),
		 .reset_type(reset_type),
		 .hold_type(hold_type),
		 .architecture(architecture - 4))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.req_ip_ivc_op(req_qual_ip_ivc_op),
		.gnt_ip_ivc(gnt_ip_ivc),
		.gnt_ip_op(gnt_ip_op));
	     
	  end
      endcase
      
   endgenerate
   
endmodule
