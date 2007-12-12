module sw_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_matrix_arb = 1,
    parameter use_speculation = 0)
   (input     clk,
    input     reset,
    
    // I/O to input controller
    // [sort order: input port,input VC,ouput port]
    input [0:num_ports*num_vcs*num_ports-1] req,
    output [0:num_ports*num_vcs*num_ports-1] gnt,
    
    // control signals to crossbar
    // [sort order: input port,output port]
    output [0:num_ports*num_ports-1] xbar_ctrl);
   
   genvar i;
   

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
      for(i = 0; i < num_ports; i = i + 1)
	begin:ip_arb_stg
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] req1_ivc_op;
	   
	   assign req1_ivc_op = req[i*num_vcs*num_ports:
				    (i+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_ports-1] 	gnt2_op;

	   assign gnt2_op = gnt2_ip_op[i*num_ports:(i+1)*num_ports-1];
	   

	   //-------------------------------------------------------------------
	   // first arbitration stage (input ports)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	gnt1_op;

	   wire 			update_arb;

	   // update priorities if request was successful in both stages
	   if(use_speculation)
	     begin
		
		// need to make sure we only update if output stage grants
		// output port requested by input stage's winning VC
		assign update_arb = |(gnt1_op & gnt2_op);
		
	     end
	   else
	     begin

		// as input ports only request output ports for their respective
		// winning VC, this is the case whenever the input port is
		// granted access to any output port
		assign update_arb = |gnt2_op;

	     end

	   wire [0:num_ports*num_vcs-1] req1_op_ivc;

	   // change sort order for VC output port requests
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req1_intl
	     (.data_in(req1_ivc_op),
	      .data_out(req1_op_ivc));

	   wire [0:num_vcs-1] 		req1_ivc;
	   
	   // combine requests for all ports (any output port requested by VC?)
	   or_n
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   req1_op_or
	     (.data_in(req1_op_ivc),
	      .data_out(req1_ivc));

	   wire [0:num_vcs-1] 		gnt1_ivc;

	   // arbitrate between all input VCs at given input port that request
	   // at least one output port
	   arbiter
	     #(.width(num_vcs),
	       .use_matrix_arb(use_matrix_arb))
	   arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req1_ivc),
	      .gnt(gnt1_ivc));

	   wire [0:num_vcs*num_ports-1] mask_op_ivc;
	   wire [0:num_vcs*num_ports-1] mask_ivc_op;

	   // create bit mask for output ports per VC
	   // mask has all ones for the selected VC's output ports, all zeroes
	   // for all others
	   assign mask_op_ivc = {num_ports{gnt1_ivc}};
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   mask_intl
	     (.data_in(mask_op_ivc),
	      .data_out(mask_ivc_op));
	   
	   // create bit vector per input port representing if the VC
	   // selected in the first round requests a given output port
	   select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req1_ivc_sel
	     (.select(gnt1_ivc),
	      .data_in(req1_ivc_op),
	      .data_out(gnt1_op));
		
	   
	   //-------------------------------------------------------------------
	   // generate requests for second stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	req2_op;
	   
	   if(use_speculation)
	     begin
	   
		// create bit vector per input port representing if any of the
		// input port's VCs requests a given output port
		or_n
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req1_ivc_or
		  (.data_in(req1_ivc_op),
		   .data_out(req2_op));
		
	     end
	   else
	     begin

		// request winning VC's requested output ports from second stage
		assign req2_op = gnt1_op;
		
	     end


	   //-------------------------------------------------------------------
	   // generate global grant signals
	   //-------------------------------------------------------------------

	   wire [0:num_vcs*num_ports-1] gnt2_ivc_op;

	   assign gnt2_ivc_op = {num_vcs{gnt2_op}};
	   
	   wire [0:num_vcs*num_ports-1] gnt_ivc_op;

	   assign gnt_ivc_op = req1_ivc_op & mask_ivc_op & gnt2_ivc_op;

	   
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
	begin:op_arb_stg

	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------

	   wire [0:num_ports-1] req2_ip;

	   assign req2_ip = req2_op_ip[i*num_ports:(i+1)*num_ports-1];

	   wire [0:num_ports-1] gnt1_ip;

	   assign gnt1_ip = gnt1_op_ip[i*num_ports:(i+1)*num_ports-1];

	   
	   //-------------------------------------------------------------------
	   // second arbitration stage (output ports)
	   //-------------------------------------------------------------------

	   wire [0:num_ports-1] gnt2_ip;
	   
	   wire 		update_arb;

	   // update priorities if request was successful in both stages
	   if(use_speculation)
	     begin
		
		// need to make sure we only update if output stage grants
		// output port requested by input stage's winning VC
		assign update_arb = |(gnt1_ip & gnt2_ip);
		
	     end
	   else
	     begin

		// as input ports only request output ports for their respective
		// winning VC, this is the case whenever the output port is
		// granted to any input port
		assign update_arb = |gnt2_ip;

	     end
	   
	   // arbitrate between requests at each port
	   arbiter
	     #(.width(num_ports),
	       .use_matrix_arb(use_matrix_arb))
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

   
   //---------------------------------------------------------------------------
   // crossbar control outputs
   //---------------------------------------------------------------------------

   assign xbar_ctrl = gnt2_ip_op;
   
endmodule
