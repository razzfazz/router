module sw_alloc_core_wf
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, cred_op_ovc, gnt_ip_ivc,
   gnt_ip_op);
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
   /* supported architectures:
    0: mux inputs based on prio, round-robin arbiters in final stage
    1: mux inputs based on prio, matrix arbiters in final stage
    2: replicate logic for prios, round-robin arbiters in final stage
    3: replicate logic for prios, matrix arbiters in final stage
    4: diagonal propagation arbiter, round-robin arbiters in final stage
    5: diagonal propagation arbiter, matrix arbiters in final stage
    6: rotate inputs based on prio, round-robin arbiters in final stage
    7: rotate inputs based on prio, matrix arbiters in final stage */
   parameter architecture = 0;

`include "config.v"
   
   localparam architecture_wf = architecture >> 1;
   localparam architecture_arb = architecture & 1;
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   
   input [0:num_ports*num_vcs-1] cred_op_ovc;
   
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output [0:num_ports*num_ports-1] gnt_ip_op;
   
   
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
	   wire [0:num_vcs-1] 		req1_ivc;

	   genvar ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs

		wire [0:num_ports-1] req_op;
		assign req_op = req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1];

		wire [0:num_vcs-1]   req_ovc;
		assign req_ovc = req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];

		wire [0:num_ports*num_vcs-1] cred_avail_op_ovc;
		assign cred_avail_op_ovc = {num_ports{req_ovc}} & cred_op_ovc;

		wire [0:num_vcs*num_ports-1] cred_avail_ovc_op;
		interleaver
		  #(.width(num_ports*num_vcs),
		    .num_blocks(num_ports))
		cred_avail_intl
		  (.data_in(cred_avail_op_ovc),
		   .data_out(cred_avail_ovc_op));

		wire [0:num_ports-1] 	     cred_avail_op;
		or_nto1
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		cred_avail_ovc_or
		  (.data_in(cred_avail_ovc_op),
		   .data_out(cred_avail_op));

		wire [0:num_ports-1] req2_op;
		assign req2_op = req_op & cred_avail_op;
		
		assign req2_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = req2_op;

		assign req1_ivc[ivc] = |(req2_op & gnt2_op);
		
	     end
      
	   
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
	   // first arbitration stage (select VC)
	   //-------------------------------------------------------------------

	   wire 			update_arb;
	   assign update_arb = |gnt2_op;
	   
	   wire [0:num_vcs-1] 		gnt1_ivc;
	   arbiter
	     #(.num_ports(num_vcs),
	       .reset_type(reset_type),
	       .architecture(architecture_arb))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req1_ivc),
	      .gnt(gnt1_ivc));
	   
	   
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
       .architecture(architecture_wf))
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
