module vc_alloc_core_sep_of
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, elig_op_ovc, gnt_ip_ivc,
   gnt_ip_ivc_ovc, gnt_op_ovc);
   
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
   
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------

   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req2_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt2_ip_ivc_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate

      genvar 						  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips

	   genvar ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] req_op;
		assign req_op = req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
					      (ip*num_vcs+ivc+1)*num_ports-1];
		
		wire [0:num_vcs-1]   req_ovc;
		assign req_ovc = req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
						(ip*num_vcs+ivc+1)*num_vcs-1];
		
		wire [0:num_ports*num_vcs-1] gnt2_op_ovc;
		assign gnt2_op_ovc
		  = gnt2_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
				       (ip*num_vcs+ivc+1)*num_ports*num_vcs-1];
		
		
		//--------------------------------------------------------------
		// generate requests for second stage
		//--------------------------------------------------------------
		
		wire [0:num_vcs*num_ports-1] port_req_ovc_op;
		assign port_req_ovc_op = {num_vcs{req_op}};
		
		wire [0:num_ports*num_vcs-1] port_req_op_ovc;
		interleaver
		  #(.width(num_vcs*num_ports),
		    .num_blocks(num_vcs))
		port_req_intl
		  (.data_in(port_req_ovc_op),
		   .data_out(port_req_op_ovc));
		
		wire [0:num_ports*num_vcs-1] vc_req_op_ovc;
		assign vc_req_op_ovc = {num_ports{req_ovc}};
		
		wire [0:num_ports*num_vcs-1] req2_op_ovc;
		assign req2_op_ovc
		  = port_req_op_ovc & vc_req_op_ovc & cred_op_ovc;
		
		
		//--------------------------------------------------------------
		// first arbitration stage (select output VC)
		//--------------------------------------------------------------
		
		wire [0:num_vcs-1] 	     gnt2_ovc;
		or_nto1
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		gnt2_op_or
		  (.data_in(gnt2_op_ovc),
		   .data_out(gnt2_ovc));
		
		wire 			     gnt2;
		assign gnt2 = |gnt2_ovc;
		
		wire 			     update_arb;
		assign update_arb = gnt2;
		
		wire [0:num_vcs-1] 	     req1_ovc;
		assign req1_ovc = gnt2_ovc;
		
		wire [0:num_vcs-1] 	     gnt1_ovc;
		arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .architecture(architecture_arb))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req1_ovc),
		   .gnt(gnt1_ovc));

		wire [0:num_ports*num_vcs-1] gnt1_op_ovc;
		assign gnt1_op_ovc = port_req_op_ovc & {num_ports{gnt1_ovc}};
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		wire 			     gnt;
		assign gnt = gnt2;
		
		wire [0:num_vcs-1] 	     gnt_ovc;
		assign gnt_ovc = gnt1_ovc;
		
		
		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------
		
		assign req2_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					  (ip*num_vcs+ivc+1)*num_ports*num_vcs
					  -1] = req2_op_ovc;
		assign gnt1_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					  (ip*num_vcs+ivc+1)*num_ports*num_vcs
					  -1] = gnt1_op_ovc;
		
		assign gnt_ip_ivc[ip*num_vcs+ivc] = gnt;
		assign gnt_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1] = gnt_ovc;
		
	     end
	   
	end
      
   endgenerate


   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	     gnt1_op_ovc;
   or_nto1
     #(.width(num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   gnt1_ip_ivc_or
     (.data_in(gnt1_ip_ivc_op_ovc),
      .data_out(gnt1_op_ovc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req2_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   req2_intl
     (.data_in(req2_ip_ivc_op_ovc),
      .data_out(req2_op_ovc_ip_ivc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt2_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   gnt2_intl
     (.data_in(gnt2_op_ovc_ip_ivc),
      .data_out(gnt2_ip_ivc_op_ovc));
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------

   generate

      genvar 					  op;
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   genvar ovc;
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------
		
		wire [0:num_ports*num_vcs-1] req2_ip_ivc;
		assign req2_ip_ivc
		  = req2_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
				       (op*num_vcs+ovc+1)*num_ports*num_vcs-1];
		
		wire 			     gnt1;
		assign gnt1 = gnt1_op_ovc[op*num_vcs+ovc];
		
		
		//--------------------------------------------------------------
		// second stage arbitration (select input port and VC)
		//--------------------------------------------------------------
		
		wire 			     update_arb;
		assign update_arb = gnt1;
		
		wire [0:num_ports-1] 	     req2_ip;
		wire [0:num_ports-1] 	     gnt2_ip;
		wire [0:num_ports*num_vcs-1] gnt2_ip_ivc;
		
		genvar 			     ip;
		for(ip = 0; ip < num_ports; ip = ip + 1)
		  begin:ips

		     wire [0:num_vcs-1] req2_ivc;
		     assign req2_ivc = req2_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];

		     assign req2_ip[ip] = |req2_ivc;

		     wire [0:num_vcs-1] gnt2_ivc;
		     arbiter
		       #(.num_ports(num_vcs),
			 .reset_type(reset_type),
			 .architecture(architecture_arb))
		     ivc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb),
			.req(req2_ivc),
			.gnt(gnt2_ivc));

		     assign gnt2_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
			      = gnt2_ivc & {num_vcs{gnt2_ip[ip]}};
		     
		  end
		
		arbiter
		  #(.num_ports(num_ports),
		    .reset_type(reset_type),
		    .architecture(architecture_arb))
		ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req2_ip),
		   .gnt(gnt2_ip));

		
		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------

		assign gnt2_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					  (op*num_vcs+ovc+1)*num_ports*num_vcs
					  -1] = gnt2_ip_ivc;
		
	     end
	end
   endgenerate

   assign gnt_op_ovc = gnt1_op_ovc;
   
endmodule
