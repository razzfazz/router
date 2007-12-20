module sw_alloc_separable
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_clock_gating = 1,
    parameter use_output_first = 0)
   (input     clk,
    input     reset,
    
    // requests and grant signals to input controller
    // [sort order: input port,input VC,ouput port]
    // [each input VC at each input port can request at most one output port]
    input [0:num_ports*num_vcs*num_ports-1] req,
    output wire [0:num_ports*num_vcs*num_ports-1] gnt);
   
   genvar 					  i;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 		  gnt1_ip_op;
   wire [0:num_ports*num_ports-1] 		  req2_ip_op;
   wire [0:num_ports*num_ports-1] 		  gnt2_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      for(i = 0; i < num_ports; i = i + 1)
	begin:input_ports
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] req_ivc_op;
	   
	   assign req_ivc_op = req[i*num_vcs*num_ports:
				   (i+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_ports-1] 	gnt2_op;

	   assign gnt2_op = gnt2_ip_op[i*num_ports:(i+1)*num_ports-1];
	   

	   //-------------------------------------------------------------------
	   // first arbitration stage (select VC)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] mask2_ivc_op;
	   assign mask2_ivc_op = {num_vcs{gnt2_op}};

	   wire [0:num_vcs*num_ports-1] req1_ivc_op;
	   wire [0:num_ports*num_vcs-1] req1_op_ivc;
	   wire [0:num_vcs-1] 		req1_ivc;
	   wire [0:num_ports-1] 	gnt1_op;
	   wire 			update_arb;
	   
	   if(use_output_first)
	     begin

		// only propagate requests that were granted in the output stage
		assign req1_ivc_op = req_ivc_op & mask2_ivc_op;
		
	     end
	   else
	     begin

		// propagate all requests
		assign req1_ivc_op = req_ivc_op;
		
	     end
	   
	   // change sort order for VC output port requests
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req1_intl
	     (.data_in(req1_ivc_op),
	      .data_out(req1_op_ivc));
	   
	   // combine requests for all output ports (any output port requested
	   // by each VC?)
	   or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   req1_op_or
	     (.data_in(req1_op_ivc),
	      .data_out(req1_ivc));

	   // update priorities if request was successful in both stages
	   // (for output-first case, if any output ports are granted to this
	   // input port, we know they were previously requested by at least
	   // one VC here; thus, at least one of the VCs will have a valid
	   // qualified request, and consequently at least one VC will be
	   // granted; for input-first case, output ports can only have grants
	   // in the second-stage if they were also granted in the first stage)
	   assign update_arb = |gnt2_op;
	   
	   wire [0:num_vcs-1] 		gnt1_ivc;

	   // arbitrate between all input VCs at given input port that request
	   // at least one output port
	   arbiter
	     #(.num_ports(num_vcs),
	       .use_arbiter_type(use_arbiter_type),
	       .use_clock_gating(use_clock_gating))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req1_ivc),
	      .gnt(gnt1_ivc));

	   wire [0:num_ports*num_vcs-1] mask1_op_ivc;
	   wire [0:num_vcs*num_ports-1] mask1_ivc_op;

	   // create bit mask for output ports per VC
	   // mask has all ones for the selected VC's output ports, all zeroes
	   // for all others
	   assign mask1_op_ivc = {num_ports{gnt1_ivc}};
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt1_intl
	     (.data_in(mask1_op_ivc),
	      .data_out(mask1_ivc_op));

	   wire [0:num_vcs*num_ports-1] gnt1_ivc_op;

	   // create per-VC bit vector representing which output port the
	   // winning VC requests (all-zeroes for other VCs)
	   assign gnt1_ivc_op = req1_ivc_op & mask1_ivc_op;
	   
	   // create bit vector representing if the VC selected in the input
	   // stage requests a given output port
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   gnt1_ivc_or
	     (.data_in(gnt1_ivc_op),
	      .data_out(gnt1_op));
		
	   
	   //-------------------------------------------------------------------
	   // generate requests for second stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	req2_op;
	   
	   if(use_output_first)
	     begin
	   
		// create bit vector per input port representing if any of the
		// input port's VCs requests a given output port
		or_nto1
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req_ivc_or
		  (.data_in(req_ivc_op),
		   .data_out(req2_op));
		
	     end
	   else
	     begin

		// request winning VC's requested output port from second stage
		assign req2_op = gnt1_op;
		
	     end


	   //-------------------------------------------------------------------
	   // generate global grant signals
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] gnt_ivc_op;

	   if(use_output_first)
	     begin
		assign gnt_ivc_op = gnt1_ivc_op;
	     end
	   else
	     begin
		assign gnt_ivc_op = gnt1_ivc_op & mask2_ivc_op;
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------

	   assign gnt1_ip_op[i*num_ports:(i+1)*num_ports-1] = gnt1_op;
	   assign req2_ip_op[i*num_ports:(i+1)*num_ports-1] = req2_op;
	   assign gnt[i*num_vcs*num_ports:
		      (i+1)*num_vcs*num_ports-1] = gnt_ivc_op;
	   
	end
   endgenerate

   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------

   wire [0:num_ports*num_ports-1] 	gnt1_op_ip;

   // sort bit vector by output port
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req2_intl
     (.data_in(gnt1_ip_op),
      .data_out(gnt1_op_ip));

   wire [0:num_ports*num_ports-1] 	req2_op_ip;

   // sort bit vector by output port
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req2_intl
     (.data_in(req2_ip_op),
      .data_out(req2_op_ip));
   
   wire [0:num_ports*num_ports-1] 	gnt2_op_ip;
   
   // sort bit vector by input port
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt2_deintl
     (.data_in(gnt2_op_ip),
      .data_out(gnt2_ip_op));


   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------

   generate
      for (i = 0; i < num_ports; i = i + 1)
	begin:output_ports

	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------

	   wire [0:num_ports-1] req2_ip;

	   assign req2_ip = req2_op_ip[i*num_ports:(i+1)*num_ports-1];

	   wire [0:num_ports-1] gnt1_ip;

	   assign gnt1_ip = gnt1_op_ip[i*num_ports:(i+1)*num_ports-1];

	   
	   //-------------------------------------------------------------------
	   // second arbitration stage (select input port)
	   //-------------------------------------------------------------------

	   wire [0:num_ports-1] gnt2_ip;
	   wire 		update_arb;

	   // update priorities if request was successful in both stages
	   // (for input-first case, if any VC requesting this output port was
	   // granted at any input port in the first stage, one of these input
	   // ports will be granted here as well, and we can thus update
	   // priorities; for output-first case, input ports can only have
	   // grants in the first stage if they were also granted in the second
	   // stage)
	   assign update_arb = |gnt1_ip;
	   
	   // arbitrate between requests at each port
	   arbiter
	     #(.num_ports(num_ports),
	       .use_arbiter_type(use_arbiter_type),
	       .use_clock_gating(use_clock_gating))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req2_ip),
	      .gnt(gnt2_ip));

	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------

	   assign gnt2_op_ip[i*num_ports:(i+1)*num_ports-1] = gnt2_ip;
	   
	end
   endgenerate

endmodule
