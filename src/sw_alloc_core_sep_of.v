module sw_alloc_core_sep_of
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, cred_op_ovc, gnt_ip_ivc,
   gnt_ip_op);
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
   /* supported architectures:
    0: use round-robin arbiters
    1: use matrix arbiters */
   parameter architecture = 0;
   
`include "config.v"
   
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
   
   wire [0:num_ports*num_ports-1] 	  gnt1_ip_op;
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

	   // since multiple ports may have been granted in the second stage, we
	   // must select the winning one
	   wire [0:num_ports-1] 	gnt1_op;
	   select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_ivc_sel
	     (.select(gnt1_ivc),
	      .data_in(req_ivc_op),
	      .data_out(gnt1_op));

	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------

	   wire [0:num_vcs-1] 		gnt_ivc;
	   assign gnt_ivc = gnt1_ivc;

	   wire [0:num_ports-1] 	gnt_op;
	   assign gnt_op = gnt1_op;
	   

	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------

	   assign req2_ip_op[ip*num_ports:(ip+1)*num_ports-1] = req2_op;
	   assign gnt1_ip_op[ip*num_ports:(ip+1)*num_ports-1] = gnt1_op;
	   assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = gnt_ivc;
	   assign gnt_ip_op[ip*num_ports:(ip+1)*num_ports-1] = gnt_op;
	   
	end
      
   endgenerate

   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------

   wire [0:num_ports-1] 		gnt1_op;
   or_nto1
     #(.width(num_ports),
       .num_ports(num_ports))
   gnt1_ip_or
     (.data_in(gnt1_ip_op),
      .data_out(gnt1_op));
   
   wire [0:num_ports*num_ports-1] 	req2_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req2_intl
     (.data_in(req2_ip_op),
      .data_out(req2_op_ip));
   
   wire [0:num_ports*num_ports-1] 	gnt2_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt2_intl
     (.data_in(gnt2_op_ip),
      .data_out(gnt2_ip_op));


   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------

   generate

      genvar 				op;
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops

	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req2_ip;
	   assign req2_ip = req2_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire 		gnt1;
	   assign gnt1 = gnt1_op[op];
	   
	   
	   //-------------------------------------------------------------------
	   // second arbitration stage (select input port)
	   //-------------------------------------------------------------------
	   
	   // if any VC requesting this output port was granted at any input
	   // port in the first stage, the corresponding second-stage grant must
	   // have taken place before that, so we can update priorities
	   wire 		update_arb;
	   assign update_arb = gnt1;
	   
	   wire [0:num_ports-1] gnt2_ip;
	   arbiter
	     #(.num_ports(num_ports),
	       .reset_type(reset_type),
	       .architecture(architecture_arb))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req2_ip),
	      .gnt(gnt2_ip));
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------
	   
	   assign gnt2_op_ip[op*num_ports:(op+1)*num_ports-1] = gnt2_ip;
	   
	end

   endgenerate

endmodule
