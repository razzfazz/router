module sw_alloc_core_sep_if
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
    
    input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op,
    
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
	   
	   wire [0:num_ports-1] 	gnt2_op;
	   assign gnt2_op = gnt2_ip_op[ip*num_ports:(ip+1)*num_ports-1];


	   //-------------------------------------------------------------------
	   // first arbitration stage (select VC)
	   //-------------------------------------------------------------------

	   wire 			gnt2;
	   assign gnt2 = |gnt2_op;

	   wire 			update_arb;
	   assign update_arb = gnt2;

	   wire [0:num_ports*num_vcs-1] req_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req_intl
	     (.data_in(req_ivc_op),
	      .data_out(req_op_ivc));

	   wire [0:num_vcs-1] 		req1_ivc;
	   or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   req_op_or
	     (.data_in(req_op_ivc),
	      .data_out(req1_ivc));

	   wire [0:num_vcs-1] 		gnt1_ivc;
	   if(num_vcs > 1)
	     begin
		arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .hold_type(hold_type),
		    .architecture(architecture & 1))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req1_ivc),
		   .gnt(gnt1_ivc));
	     end
	   else
	     assign gnt1_ivc = req1_ivc;
	   

	   //-------------------------------------------------------------------
	   // generate requests for second stage
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] req2_ivc_op;
	   assign req2_ivc_op = req_ivc_op;

	   wire [0:num_ports-1] 	req2_op;
	   select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req2_ivc_sel
	     (.select(gnt1_ivc),
	      .data_in(req2_ivc_op),
	      .data_out(req2_op));


	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------

	   wire [0:num_vcs-1] 		gnt_ivc;
	   
	   select_1ofn
	     #(.width(num_vcs),
	       .num_ports(1))
	   gnt_sel
	     (.select(gnt2),
	      .data_in(gnt1_ivc),
	      .data_out(gnt_ivc));

	   
	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------

	   assign req2_ip_op[ip*num_ports:(ip+1)*num_ports-1] = req2_op;
	   assign gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = gnt_ivc;
	   
	end

   endgenerate

   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------

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

   wire [0:num_ports*num_ports-1] 	gnt_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_intl
     (.data_in(gnt_op_ip),
      .data_out(gnt_ip_op));


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

	   
	   //-------------------------------------------------------------------
	   // second arbitration stage (select input port)
	   //-------------------------------------------------------------------
	   
	   wire 		req2;
	   assign req2 = |req2_ip;

	   // if any VC requesting this output port was granted at any input
	   // port in the first stage, one of these input ports will be granted
	   // here as well, and we can thus update priorities
	   wire 		update_arb;
	   assign update_arb = req2;

	   wire [0:num_ports-1] gnt2_ip;
	   arbiter
	     #(.num_ports(num_ports),
	       .reset_type(reset_type),
	       .hold_type(hold_type),
	       .architecture(architecture & 1))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req2_ip),
	      .gnt(gnt2_ip));

	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------

	   wire [0:num_ports-1] gnt_ip;
	   assign gnt_ip = gnt2_ip;
	   

	   //-------------------------------------------------------------------
	   // connect outputs
	   //-------------------------------------------------------------------

	   assign gnt2_op_ip[op*num_ports:(op+1)*num_ports-1] = gnt2_ip;
	   assign gnt_op_ip[op*num_ports:(op+1)*num_ports-1] = gnt_ip;
	   
	end

   endgenerate

endmodule
