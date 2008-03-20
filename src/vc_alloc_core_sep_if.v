module vc_alloc_core_sep_if
  #(parameter num_ports = 8,
    parameter num_vcs = 4,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1,

    /* supported architectures:
     0: use round-robin arbiters
     1: use matrix arbiters */
    parameter architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc,

    output wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_ip_ivc_op_ovc,
    output wire [0:num_ports*num_vcs-1] 		  gnt_ip_ivc);
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------

   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] 	  req2_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] 	  gnt2_ip_ivc_op_ovc;
   
   
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

		wire [0:num_ports*num_vcs-1] req_op_ovc;
		assign req_op_ovc
		  = req_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
				      (ip*num_vcs+ivc+1)*num_ports*num_vcs-1];

		wire [0:num_ports*num_vcs-1] gnt2_op_ovc;
		assign gnt2_op_ovc
		  = gnt2_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
				       (ip*num_vcs+ivc+1)*num_ports*num_vcs-1];

		//--------------------------------------------------------------
		// first arbitration stage (select output port and VC)
		//--------------------------------------------------------------

		wire [0:num_ports*num_vcs-1] req1_op_ovc;
		assign req1_op_ovc = req_op_ovc;

		wire 			     gnt2;
		assign gnt2 = |gnt2_op_ovc;
		
		wire 			     update_arb;
		assign update_arb = gnt2;
		
		wire [0:num_ports*num_vcs-1] gnt1_op_ovc;

		arbiter
		  #(.num_ports(num_ports*num_vcs),
		    .num_blocks(num_ports),
		    .architecture(architecture),
		    .reset_type(reset_type))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req1_op_ovc),
		   .gnt(gnt1_op_ovc));

		
		//--------------------------------------------------------------
		// generate requests for second stage
		//--------------------------------------------------------------

		wire [0:num_ports*num_vcs-1] req2_op_ovc;
		assign req2_op_ovc = gnt1_op_ovc;
		

		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------

		assign req2_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					  (ip*num_vcs+ivc+1)*num_ports*num_vcs
					  -1] = req2_op_ovc;

		assign gnt_ip_ivc[ip*num_vcs+ivc] = gnt2;

	     end
	   
	end
      
   endgenerate


   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------

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
		

		//--------------------------------------------------------------
		// second stage arbitration (select input port and VC)
		//--------------------------------------------------------------

		wire 			     update_arb;
		assign update_arb = |req2_ip_ivc;
		
		wire [0:num_ports*num_vcs-1] gnt2_ip_ivc;
		arbiter
		  #(.num_ports(num_ports*num_vcs),
		    .num_blocks(num_ports),
		    .reset_type(reset_type),
		    .hold_type(hold_type),
		    .architecture(architecture))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req2_ip_ivc),
		   .gnt(gnt2_ip_ivc));

		
		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------

		assign gnt2_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					  (op*num_vcs+ovc+1)*num_ports*num_vcs
					  -1] = gnt2_ip_ivc;
		
	     end
	end
   endgenerate

   //---------------------------------------------------------------------------
   // assign global grant signals
   //---------------------------------------------------------------------------

   assign gnt_ip_ivc_op_ovc = gnt2_ip_ivc_op_ovc;

endmodule
