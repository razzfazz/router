// $Id$
module vc_alloc_core_sep_of
  (clk, reset, vc_req_ip_ivc_op, vc_req_ip_ivc_ovc, elig_op_ovc,
   vc_gnt_ip_ivc_ovc, vc_gnt_op_ovc);
   
`include "constants.v"
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // request VC allocation for given port (for each input VC)
   input [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   
   // allowable VCs for VC allocation (for each input VC)
   input [0:num_ports*num_vcs*num_vcs-1] vc_req_ip_ivc_ovc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // granted output VC (to inpt controller)
   output [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 	vc_gnt_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_in_ip_ivc_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   genvar ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		//--------------------------------------------------------------
		// generate requests for output stage
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 	     vc_req_op;
		assign vc_req_op
		  = vc_req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				     (ip*num_vcs+ivc+1)*num_ports-1];
		
		wire [0:num_vcs-1] 	     vc_req_ovc;
		assign vc_req_ovc
		  = vc_req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1];
		
		wire [0:num_ports*num_vcs-1] vc_req_op_ovc;
		replicator
		  #(.width(num_ports),
		    .count(num_vcs))
		vc_req_op_ovc_repl
		  (.data_in(vc_req_op),
		   .data_out(vc_req_op_ovc));
		
		wire [0:num_ports*num_vcs-1] req_out_op_ovc;
		assign req_out_op_ovc = vc_req_op_ovc & {num_ports{vc_req_ovc}};
		
		assign req_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					     (ip*num_vcs+ivc+1)*num_ports*
					     num_vcs-1]
			 = req_out_op_ovc;
		
		
		//--------------------------------------------------------------
		// input arbitration stage (select output VC)
		//--------------------------------------------------------------
		
		wire [0:num_ports*num_vcs-1] gnt_out_op_ovc;
		assign gnt_out_op_ovc
		  = gnt_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					  (ip*num_vcs+ivc+1)*num_ports*num_vcs
					  -1];
		
		wire [0:num_vcs-1] 	     gnt_out_ovc;
		or_nto1
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		gnt_out_ovc_or
		  (.data_in(gnt_out_op_ovc),
		   .data_out(gnt_out_ovc));
		
		wire 			     update_arb;
		assign update_arb = |gnt_out_ovc;
		
		wire [0:num_vcs-1] 	     req_in_ovc;
		assign req_in_ovc = gnt_out_ovc;
		
		wire [0:num_vcs-1] 	     gnt_in_ovc;
		if(num_vcs_per_class > 1)
		  begin
		     arbiter
		       #(.num_ports(num_vcs),
			 .arbiter_type(arbiter_type),
			 .reset_type(reset_type))
		     gnt_in_ovc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb),
			.req(req_in_ovc),
			.gnt(gnt_in_ovc));
		  end
		else
		  assign gnt_in_ovc = req_in_ovc;
		
		wire [0:num_ports*num_vcs-1] gnt_in_op_ovc;
		assign gnt_in_op_ovc = vc_req_op_ovc & {num_ports{gnt_in_ovc}};
		
		assign gnt_in_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					    (ip*num_vcs+ivc+1)*num_ports*num_vcs
					    -1]
			 = gnt_in_op_ovc;
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		assign vc_gnt_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
					 (ip*num_vcs+ivc+1)*num_vcs-1]
			 = gnt_in_ovc;
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	     gnt_in_op_ovc;
   or_nto1
     #(.width(num_ports*num_vcs),
       .num_ports(num_ports*num_vcs))
   gnt_in_op_ovc_or
     (.data_in(gnt_in_ip_ivc_op_ovc),
      .data_out(gnt_in_op_ovc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   req_out_op_ovc_ip_ivc_intl
     (.data_in(req_out_ip_ivc_op_ovc),
      .data_out(req_out_op_ovc_ip_ivc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   gnt_out_ip_ivc_op_ovc_intl
     (.data_in(gnt_out_op_ovc_ip_ivc),
      .data_out(gnt_out_ip_ivc_op_ovc));
   
   
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
		// second stage arbitration (select input port and VC)
		//--------------------------------------------------------------
		
		wire 			     gnt_in;
		assign gnt_in = gnt_in_op_ovc[op*num_vcs+ovc];
		
		wire [0:num_ports*num_vcs-1] req_out_ip_ivc;
		assign req_out_ip_ivc
		  = req_out_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					  (op*num_vcs+ovc+1)*num_ports*num_vcs
					  -1];
		
		wire [0:num_ports-1] 	     req_out_ip;
		wire [0:num_ports-1] 	     gnt_out_ip;
		
		wire [0:num_ports-1] 	     update_arb_ip;
		assign update_arb_ip = {num_ports{gnt_in}} & gnt_out_ip;
		
		wire 			     elig;
		assign elig = elig_op_ovc[op*num_vcs+ovc];
		
		wire [0:num_ports*num_vcs-1] gnt_out_ip_ivc;
		
		genvar 			     ip;
		for(ip = 0; ip < num_ports; ip = ip + 1)
		  begin:ips
		     
		     wire [0:num_vcs-1] req_out_ivc;
		     assign req_out_ivc
		       = req_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		     
		     assign req_out_ip[ip] = |req_out_ivc;
		     
		     wire [0:num_vcs-1] gnt_out_ivc;
		     arbiter
		       #(.num_ports(num_vcs),
			 .arbiter_type(arbiter_type),
			 .reset_type(reset_type))
		     gnt_out_ivc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb_ip[ip]),
			.req(req_out_ivc),
			.gnt(gnt_out_ivc));
		     
		     assign gnt_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
			      = gnt_out_ivc & {num_vcs{gnt_out_ip[ip] & elig}};
		     
		  end
		
		wire 			update_arb;
		assign update_arb = gnt_in;
		
		arbiter
		  #(.num_ports(num_ports),
		    .arbiter_type(arbiter_type),
		    .reset_type(reset_type))
		gnt_out_ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req_out_ip),
		   .gnt(gnt_out_ip));
		
		assign gnt_out_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					     (op*num_vcs+ovc+1)*num_ports*
					     num_vcs-1]
			 = gnt_out_ip_ivc;
		
	     end
	end
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grant
   //---------------------------------------------------------------------------
   
   assign vc_gnt_op_ovc = gnt_in_op_ovc;
   
endmodule
