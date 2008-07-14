module vc_alloc_core_sep_of
  (clk, reset, vc_req_ip_ivc_op, vc_req_ip_ivc_ovc, vc_gnt_ip_ivc,
   vc_gnt_ip_ivc_ovc, vc_gnt_op_ovc);
   
`include "functions.v"   
`include "config.v"
`include "constants.v"
`include "config_utils.v"
   
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: use round-robin arbiters
    1: use matrix arbiters */
   parameter architecture = 0;
   
   localparam architecture_arb = architecture & 1;
   
   localparam [0:num_ports*num_ports-1] mask_ip_op
     = create_mask_ip_op(ignore_same_port);
   
   localparam [0:num_ports*num_ports-1] mask_op_ip
     = create_mask_op_ip(ignore_same_port);
   
   localparam [0:num_vcs*num_vcs-1] mask_ivc_ovc
     = create_mask_ivc_ovc(restrict_vcs);
   
   localparam [0:num_vcs*num_vcs-1] mask_ovc_ivc
     = create_mask_ovc_ivc(restrict_vcs);
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] vc_req_ip_ivc_ovc;
   
   output [0:num_ports*num_vcs-1] vc_gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs-1] vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
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
				     (ip*num_vcs+ivc+1)*num_ports-1] &
		    mask_ip_op[ip*num_ports:(ip+1)*num_ports-1];
		
		wire [0:num_vcs-1] 	     vc_req_ovc;
		assign vc_req_ovc
		  = vc_req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1] &
		    mask_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
		
		wire [0:num_ports*num_vcs-1] vc_req_op_ovc;
		replicator
		  #(.width(num_ports),
		    .count(num_vcs))
		vc_req_op_ovc_repl
		  (.data_in(vc_req_op),
		   .data_out(vc_req_op_ovc));
		
		wire [0:num_ports*num_vcs-1] req_out_op_ovc;
		assign req_out_op_ovc
		  = vc_req_op_ovc & {num_ports{vc_req_ovc}};
		
		assign req_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					     (ip*num_vcs+ivc+1)*num_ports*
					     num_vcs-1]
			 = req_out_op_ovc;
		
		
		//--------------------------------------------------------------
		// first arbitration stage (select output VC)
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
		
		wire 			     gnt_out;
		assign gnt_out = |gnt_out_ovc;
		
		wire 			     update_arb;
		assign update_arb = gnt_out;
		
		wire [0:num_vcs-1] 	     req_in_ovc;
		assign req_in_ovc = gnt_out_ovc;
		
		wire [0:num_vcs-1] 	     gnt_in_ovc;
		arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .architecture(architecture_arb),
		    .mask(mask_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1]))
		gnt_in_ovc_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req_in_ovc),
		   .gnt(gnt_in_ovc));
		
		wire [0:num_ports*num_vcs-1] gnt_in_op_ovc;
		assign gnt_in_op_ovc
		  = vc_req_op_ovc & {num_ports{gnt_in_ovc}};
		
		assign gnt_in_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					    (ip*num_vcs+ivc+1)*num_ports*num_vcs
					    -1]
			 = gnt_in_op_ovc;
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		assign vc_gnt_ip_ivc[ip*num_vcs+ivc] = gnt_out;
		
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
			 .reset_type(reset_type),
			 .architecture(architecture_arb),
			 .mask(mask_ovc_ivc[ovc*num_vcs:(ovc+1)*num_vcs-1]))
		     gnt_out_ivc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb_ip[ip]),
			.req(req_out_ivc),
			.gnt(gnt_out_ivc));
		     
		     assign gnt_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
			      = gnt_out_ivc & {num_vcs{gnt_out_ip[ip]}};
		  end
		
		wire 			update_arb;
		assign update_arb = gnt_in;
		
		arbiter
		  #(.num_ports(num_ports),
		    .reset_type(reset_type),
		    .architecture(architecture_arb),
		    .mask(mask_op_ip[op*num_ports:(op+1)*num_ports-1]))
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
