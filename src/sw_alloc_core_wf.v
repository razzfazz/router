module sw_alloc_core_wf
  (clk, reset, req_ip_ivc_op, req_ip_ivc_ovc, cred_op_ovc, gnt_ip_ivc,
   gnt_ip_op);
   
   
`include "constants.v"
`include "config.v"
   
   
   parameter reset_type = reset_type_async;
   
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
   
   localparam architecture_wf = architecture >> 1;
   localparam architecture_arb = architecture & 1;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   
   input [0:num_ports*num_vcs-1] cred_op_ovc;
   
   output wire [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output wire [0:num_ports*num_ports-1] gnt_ip_op;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	 req2_ip_op;
   wire [0:num_ports*num_ports-1] 	 gnt2_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				 ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // connect inputs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] req_ivc_op;
	   assign req_ivc_op = req_ip_ivc_op[ip*num_vcs*num_ports:
					     (ip+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_vcs*num_vcs-1] 	req_ivc_ovc;
	   assign req_ivc_ovc = req_ip_ivc_ovc[ip*num_vcs*num_vcs:
					       (ip+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_ports-1] 	gnt2_op;
	   assign gnt2_op = gnt2_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   
	   //-------------------------------------------------------------------
	   // filter out unavailable VCs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] req2_ivc_op;
	   wire [0:num_vcs*num_ports-1] req1_ivc_op;
	   wire [0:num_vcs*num_ports-1] gnt1_ivc_op;
	   wire [0:num_vcs-1] 		gnt_ivc;
	   
	   genvar 			ivc;
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
		
		wire [0:num_ports-1] 	     req1_op;
		assign req1_op = req_op & cred_avail_op;
		
		assign req1_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = req1_op;
		
		wire [0:num_ports-1] 	     req2_op;
		assign req2_op = req_op & cred_avail_op;
		
		assign req2_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = req2_op;
		
		wire [0:num_ports-1] 	     gnt1_op;
		assign gnt1_op = gnt1_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1];
		
		wire 			     gnt;
		assign gnt = |(gnt1_op & gnt2_op);
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		assign gnt_ivc[ivc] = gnt;
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // generate requests for second stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	     req2_op;
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req2_ivc_or
	     (.data_in(req2_ivc_op),
	      .data_out(req2_op));
	   
	   
	   //-------------------------------------------------------------------
	   // first arbitration stage (pre-select winning VC for each output)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports*num_vcs-1]      req1_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req2_intl
	     (.data_in(req1_ivc_op),
	      .data_out(req1_op_ivc));
	   
	   wire [0:num_ports*num_vcs-1]      gnt1_op_ivc;
	   genvar 			     op;
	   for(op = 0; op < num_ports; op = op + 1)
	     begin:ops
		
		wire 			update_arb;
		assign update_arb = gnt2_op[op];
		
		wire [0:num_vcs-1] 	req1_ivc;
		assign req1_ivc = req1_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		
		wire [0:num_vcs-1] 	gnt1_ivc;
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
		
		assign gnt1_op_ivc[op*num_vcs:(op+1)*num_vcs-1] = gnt1_ivc;
		
	     end
	   
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt1_intl
	     (.data_in(gnt1_op_ivc),
	      .data_out(gnt1_ivc_op));
	   
	   
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
   assign update_alloc = |req2_ip_op;
   
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
