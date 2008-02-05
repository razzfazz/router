// switch allocator
// (wavefront allocator for matching ports)

module sw_alloc_core_wf

  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_clock_gating = 1)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op,
    
    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_ports-1] gnt_ip_op);
   
   genvar 				  i;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
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
	   assign req_ivc_op = req_ip_ivc_op[i*num_vcs*num_ports:
					     (i+1)*num_vcs*num_ports-1];

	   wire [0:num_ports-1] 	gnt2_op;
	   assign gnt2_op = gnt2_ip_op[i*num_ports:(i+1)*num_ports-1];


	   //-------------------------------------------------------------------
	   // first arbitration stage (select VC)
	   //-------------------------------------------------------------------

	   wire 			gnt2;
	   assign gnt2 = |gnt2_op;

	   wire 			update_arb;
	   assign update_arb = gnt2;

	   wire [0:num_vcs*num_ports-1] mask_ivc_op;
	   assign mask_op = {num_vcs{gnt2_op}};
	   
	   wire [0:num_vcs*num_ports-1] req1_ivc_op;
	   assign req1_ivc_op = req_ivc_op & mask_ivc_op;

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
	     
	   wire [0:num_vcs-1] 		gnt1_ivc;
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
	   

	   //-------------------------------------------------------------------
	   // generate requests for second stage
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] req2_ivc_op;
	   assign req2_ivc_op = req_ivc_op;

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

	   assign req2_ip_op[i*num_ports:(i+1)*num_ports-1] = req2_op;
	   assign gnt_ip_ivc[i*num_vcs:(i+1)*num_vcs-1] = gnt_ivc;
	   
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
       .use_clock_gating(use_clock_gating),
       .use_architecture(use_architecture))
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
