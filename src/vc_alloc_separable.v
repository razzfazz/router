module vc_alloc_separable
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_clock_gating = 1)
   (input     clk,
    input     reset,
    
    // requests and grant signals to input controller
    // [sort order: input port,input VC,ouput port,output VC]
    // [each input VC at each input port can request any output port and VC]
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req,
    output wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt);
   
   genvar 						  i, j;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------

   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] 	  req2_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] 	  gnt2_ip_ivc_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      for(i = 0; i < num_ports; i = i + 1)
	begin:input_ports
	   for(j = 0; j < num_vcs; j = j + 1)
	     begin:input_vcs

		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------

		wire [0:num_ports*num_vcs-1] req_op_ovc;

		assign req_op_ovc = req[(i*num_vcs+v)*num_ports*num_vcs:
					(i*num_vcs+v+1)*num_ports*num_vcs-1];

		wire [0:num_ports*num_vcs-1] gnt2_op_ovc;
		
		assign gnt2_op_ovc
		  = gnt2_ip_ivc_op_ovc[(i*num_vcs+v)*num_ports*num_vcs:
				       (i*num_vcs+v+1)*num_ports*num_vcs-1];

		//--------------------------------------------------------------
		// first arbitration stage (select output port and VC)
		//--------------------------------------------------------------

		wire [0:num_ports*num_vcs-1] req1_op_ovc;
		
		assign req1_op_ovc = req_op_ovc;
		
		wire update_arb;
		
		assign update_arb = |gnt2_op_ovc;
		
		wire [0:num_ports*num_vcs-1] gnt1_op_ovc;
		
		arbiter
		  #(.num_ports(num_ports*num_vcs),
		    .num_blocks(num_ports),
		    .use_arbiter_type(use_arbiter_type),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
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

		assign req2_ip_ivc_op_ovc[(i*num_vcs+v)*num_ports*num_vcs:
					  (i*num_vcs+v+1)*num_ports*num_vcs-1]
			 = req2_op_ovc;

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
      for (i = 0; i < num_ports; i = i + 1)
	begin:output_ports
	   for(j = 0; j < num_vcs; j = j + 1)
	     begin:output_vcs

		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------

		wire [0:num_ports*num_vcs-1] req2_ip_ivc;

		assign req2_ip_ivc
		  = req2_op_ovc_ip_ivc[(i*num_vcs+v)*num_ports*num_vcs:
				       (i*num_vcs+v+1)*num_ports*num_vcs-1];
		

		//--------------------------------------------------------------
		// second stage arbitration (select input port and VC)
		//--------------------------------------------------------------

		wire 			     update_arb;

		assign update_arb = |req2_ip_ivc;
		
		wire [0:num_ports*num_vcs-1] gnt2_ip_ivc;

		arbiter
		  #(.num_ports(num_ports*num_vcs),
		    .num_blocks(num_ports),
		    .use_arbiter_type(use_arbiter_type),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req2_ip_ivc),
		   .gnt(gnt2_ip_ivc));

		
		//--------------------------------------------------------------
		// connect outputs
		//--------------------------------------------------------------

		assign gnt2_op_ovc_ip_ivc[(i*num_vcs+j)*num_ports:
					  (i*num_vcs+j+1)*num_ports-1]
			 = gnt2_ip_ivc;
		
	     end
	end
   endgenerate

   //---------------------------------------------------------------------------
   // assign global grant signals
   //---------------------------------------------------------------------------

   assign gnt = gnt2_ip_ivc_op_ovc;

endmodule
