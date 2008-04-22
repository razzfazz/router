module sw_alloc_core_wf
  #(parameter num_ports = 8,
    parameter num_vcs = 4,

    // see dff.v for supported values
    parameter reset_type = 1,

    /* supported architectures:
     0: mux inputs based on prio, round-robin arbiters in final stage
     1: mux inputs based on prio, matrix arbiters in final stage
     2: replicate logic for prios, round-robin arbiters in final stage
     3: replicate logic for prios, matrix arbiters in final stage
     4: diagonal propagation arbiter, round-robin arbiters in final stage
     5: diagonal propagation arbiter, matrix arbiters in final stage
     6: rotate inputs based on prio, round-robin arbiters in final stage
     7: rotate inputs based on prio, matrix arbiters in final stage */
    parameter architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op,
    input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc,
    
    input [0:num_ports*num_vcs-1] cred_op_ovc,
    
    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_ports-1] gnt_ip_op);
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	  req2_ip_op;
   wire [0:num_ports*num_ports-1] 	  gnt2_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate

      genvar 				  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] req_ivc_op;
	   assign req_ivc_op = req_ip_ivc_op[ip*num_vcs*num_ports:
					     (ip+1)*num_vcs*num_ports-1];

	   wire [0:num_vcs*num_vcs-1] req_ivc_ovc;
	   assign req_ivc_ovc = req_ip_ivc_ovc[ip*num_vcs*num_vcs:
					       (ip+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_ports-1] 	gnt2_op;
	   assign gnt2_op = gnt2_ip_op[ip*num_ports:(ip+1)*num_ports-1];


	   //-------------------------------------------------------------------
	   // filter out unavailable VCs
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] req2_ivc_op;

	   genvar ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs

		wire [0:num_ports-1] req_op;
		assign req_op = req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1];

		wire [0:num_vcs-1]   req_ovc;
		assign req_ovc = req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
	   
		wire [0:num_vcs-1]   cred_ovc;
		select_1ofn
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		cred_op_sel
		  (.select(req_op),
		   .data_in(cred_op_ovc),
		   .data_out(cred_ovc));
		
		wire [0:num_vcs-1]   req2_ovc;
		assign req2_ovc = req_ovc & cred_ovc;

		wire 		     req2;
		assign req2 = |req2_ovc;
		
		wire [0:num_ports-1] req2_op;
		assign req2_op = {num_ports{req2}} & req_op;
		
		assign req2_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = req2_op;
		
	     end
      
	   
	   //-------------------------------------------------------------------
	   // first arbitration stage (select VC)
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] mask_ivc_op;
	   assign mask_ivc_op = {num_vcs{gnt2_op}};
	   
	   wire [0:num_vcs*num_ports-1] req1_ivc_op;
	   assign req1_ivc_op = req2_ivc_op & mask_ivc_op;

	   wire [0:num_ports*num_vcs-1] req1_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req1_intl
	     (.data_in(req1_ivc_op),
	      .data_out(req1_op_ivc));
	   
	   wire [0:num_vcs-1] 		req1_ivc;
	   or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   req1_op_or
	     (.data_in(req1_op_ivc),
	      .data_out(req1_ivc));
	     
	   wire 			update_arb;
	   assign update_arb = |gnt2_op;
	   
	   wire [0:num_vcs-1] 		gnt1_ivc;
	   arbiter
	     #(.num_ports(num_vcs),
	       .reset_type(reset_type),
	       .architecture(architecture & 1))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req1_ivc),
	      .gnt(gnt1_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // generate requests for second stage
	   //-------------------------------------------------------------------

	   wire [0:num_ports-1] 	req2_op;
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req2_ivc_or
	     (.data_in(req2_ivc_op),
	      .data_out(req2_op));
	   
	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------

	   wire [0:num_vcs-1] 		gnt_ivc;
	   assign gnt_ivc = gnt1_ivc;


	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------

	   assign req2_ip_op[ip*num_ports:(ip+1)*num_ports-1] = req2_op;
	   assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = gnt_ivc;
	   
	end

   endgenerate


   //---------------------------------------------------------------------------
   // output stage (match first-stage requests to output ports)
   //---------------------------------------------------------------------------

   // if there are any requests at all in a cycle, at least one of them will
   // eventually be granted, so update priorities
   wire 				update_alloc;
   assign update_alloc = |req_ip_ivc_op;
   
   wf_alloc
     #(.num_ports(num_ports),
       .reset_type(reset_type),
       .architecture(architecture >> 1))
   alloc
     (.clk(clk),
      .reset(reset),
      .update(update_alloc),
      .req(req2_ip_op),
      .gnt(gnt2_ip_op));

   
   //---------------------------------------------------------------------------
   // generate global grants
   //---------------------------------------------------------------------------
   
   assign gnt_ip_op = gnt2_ip_op;
   

endmodule
