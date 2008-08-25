module sw_alloc_core_sep_if
  (clk, reset, sw_req_nonspec_ip_ivc_op, sw_req_spec_ip_ivc_op, sw_gnt_ip_ivc,
   sw_gnt_ip_op);
   
`include "functions.v"
`include "constants.v"
`include "config.v"
`include "config_utils.v"
   
   parameter reset_type = reset_type_async;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter arbiter_type = 0;
   
   /*
    0: disable speculative switch allocation
    1: only use speculative grants if no non-speculative requests were issued
    2: use speculative grants when not conflicting with non-spec requests
    */
   parameter spec_level = 0;
   
   localparam [0:num_ports*num_ports-1] mask_ip_op
     = create_mask_ip_op(ignore_same_port);
   
   localparam [0:num_ports*num_ports-1] mask_op_ip
     = create_mask_op_ip(ignore_same_port);
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] sw_req_nonspec_ip_ivc_op;
   input [0:num_ports*num_vcs*num_ports-1] sw_req_spec_ip_ivc_op;
   
   output [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   output [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   wire [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   wire [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] req_out_nonspec_ip_op;
   wire [0:num_ports*num_ports-1] gnt_out_nonspec_ip_op;
   
   wire [0:num_ports*num_ports-1] req_out_spec_ip_op;
   wire [0:num_ports*num_ports-1] gnt_out_spec_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // perform input-side arbitration
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] gnt_out_nonspec_op;
	   assign gnt_out_nonspec_op
	     = gnt_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire 		gnt_out_nonspec;
	   assign gnt_out_nonspec = |gnt_out_nonspec_op;
	   
	   wire 		update_arb_nonspec;
	   assign update_arb_nonspec = gnt_out_nonspec;
	   
	   wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
	   assign sw_req_nonspec_ivc_op
	     = sw_req_nonspec_ip_ivc_op[ip*num_vcs*num_ports:
					(ip+1)*num_vcs*num_ports-1] &
	       {num_vcs{mask_ip_op[ip*num_ports:(ip+1)*num_ports-1]}};
	   
	   wire [0:num_vcs-1] 		req_in_nonspec_ivc;
	   genvar 			ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:nonspec_ivcs
		assign req_in_nonspec_ivc[ivc]
			 = |sw_req_nonspec_ivc_op[ivc*num_ports:
						  (ivc+1)*num_ports-1];
	     end
	   
	   wire [0:num_vcs-1] 	gnt_in_nonspec_ivc;
	   arbiter
	     #(.num_ports(num_vcs),
	       .reset_type(reset_type),
	       .arbiter_type(arbiter_type))
	   gnt_in_nonspec_ivc_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb_nonspec),
	      .req(req_in_nonspec_ivc),
	      .gnt(gnt_in_nonspec_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // generate requests for output stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_nonspec_op;
	   select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_out_nonspec_op_sel
	     (.select(gnt_in_nonspec_ivc),
	      .data_in(sw_req_nonspec_ivc_op),
	      .data_out(req_out_nonspec_op));
	   
	   assign req_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
		    = req_out_nonspec_op;
	   
	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	sw_gnt_nonspec_ivc;
	   assign sw_gnt_nonspec_ivc
	     = {num_vcs{gnt_out_nonspec}} & gnt_in_nonspec_ivc;
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 	sw_gnt_spec_ivc;
	   
	   if(spec_level > 0)
	     begin
		
		//--------------------------------------------------------------
		// perform input-side arbitration (speculative)
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] gnt_out_spec_op;
		assign gnt_out_spec_op
		  = gnt_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
		
		wire 		     gnt_out_spec;
		assign gnt_out_spec = |gnt_out_spec_op;
		
		wire 		     update_arb_spec;
		assign update_arb_spec = gnt_out_spec;
		
		wire [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
		assign sw_req_spec_ivc_op
		  = sw_req_spec_ip_ivc_op[ip*num_vcs*num_ports:
					  (ip+1)*num_vcs*num_ports-1] &
		    {num_vcs{mask_ip_op[ip*num_ports:(ip+1)*num_ports-1]}};
		
		wire [0:num_vcs-1] 	     req_in_spec_ivc;
		genvar 			     ivc;
		for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		  begin:spec_ivcs
		     assign req_in_spec_ivc[ivc]
			      = |sw_req_spec_ivc_op[ivc*num_ports:
						    (ivc+1)*num_ports-1];
		  end
		
		wire [0:num_vcs-1] 	gnt_in_spec_ivc;
		arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .arbiter_type(arbiter_type))
		gnt_in_spec_ivc_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb_spec),
		   .req(req_in_spec_ivc),
		   .gnt(gnt_in_spec_ivc));
		
		
		//--------------------------------------------------------------
		// generate requests for output stage (speculative)
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 	req_out_spec_op;
		select_1ofn
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req_out_spec_op_sel
		  (.select(gnt_in_spec_ivc),
		   .data_in(sw_req_spec_ivc_op),
		   .data_out(req_out_spec_op));
		
		assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 = req_out_spec_op;
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		wire [0:num_vcs-1] 	sw_gnt_spec_ivc;
		assign sw_gnt_spec_ivc
		  = {num_vcs{gnt_out_spec}} & gnt_in_spec_ivc;
		
	     end
	   else
	     begin
		
		assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 = {num_ports{1'b0}};
		assign sw_gnt_spec_ivc = {num_vcs{1'b0}};
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // combine global grants
	   //-------------------------------------------------------------------
	   
	   assign sw_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_gnt_nonspec_ivc | sw_gnt_spec_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	req_out_nonspec_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_nonspec_op_ip_intl
     (.data_in(req_out_nonspec_ip_op),
      .data_out(req_out_nonspec_op_ip));
   
   wire [0:num_ports*num_ports-1] 	gnt_out_nonspec_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_nonspec_op_ip_intl
     (.data_in(gnt_out_nonspec_op_ip),
      .data_out(gnt_out_nonspec_ip_op));
   
   wire [0:num_ports*num_ports-1] 	req_out_spec_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_spec_op_ip_intl
     (.data_in(req_out_spec_ip_op),
      .data_out(req_out_spec_op_ip));
   
   wire [0:num_ports*num_ports-1] 	gnt_out_spec_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_spec_op_ip_intl
     (.data_in(gnt_out_spec_op_ip),
      .data_out(gnt_out_spec_ip_op));
   
   
   //---------------------------------------------------------------------------
   // mask speculative requests that conflict with non-speculative ones
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 		spec_mask_op_ip;
   generate
      
      case(spec_level)
	0:
	  begin
	     
	     assign spec_mask_op_ip
	       = {num_ports*num_ports{1'b0}};
	     
	  end
	1:
	  begin
	     
	     assign spec_mask_op_ip
	       = {num_ports*num_ports{~|req_out_nonspec_ip_op}};
	     
	  end
	2:
	  begin
	     
	     wire [0:num_ports-1] any_req_ip;
	     or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_req_ip_or
	       (.data_in(req_out_nonspec_op_ip),
		.data_out(any_req_ip));
	     
	     wire [0:num_ports*num_ports-1] any_req_in_op_ip;
	     assign any_req_in_op_ip = {num_ports{any_req_ip}};
	     
	     wire [0:num_ports-1] any_req_op;
	     or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_req_op_or
	       (.data_in(req_out_nonspec_ip_op),
		.data_out(any_req_op));
	     
	     wire [0:num_ports*num_ports-1] any_req_out_op_ip;
	     replicator
	       #(.width(num_ports),
		 .count(num_ports))
	     any_req_out_op_ip_repl
	       (.data_in(any_req_op),
		.data_out(any_req_out_op_ip));
	     
	     assign spec_mask_op_ip = ~(any_req_in_op_ip | any_req_out_op_ip);
	     
	  end
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				op;
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   //-------------------------------------------------------------------
	   // perform output-side arbitration (select input port)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_nonspec_ip;
	   assign req_out_nonspec_ip
	     = req_out_nonspec_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   // if any VC requesting this output port was granted at any input
	   // port in the first stage, one of these input ports will be granted
	   // here as well, and we can thus update priorities
	   wire 		update_arb_nonspec;
	   assign update_arb_nonspec = |req_out_nonspec_ip;

	   wire [0:num_ports-1] gnt_out_nonspec_ip;
	   arbiter
	     #(.num_ports(num_ports),
	       .reset_type(reset_type),
	       .arbiter_type(arbiter_type),
	       .mask(mask_op_ip[op*num_ports:(op+1)*num_ports-1]))
	   gnt_out_nonspec_ip_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb_nonspec),
	      .req(req_out_nonspec_ip),
	      .gnt(gnt_out_nonspec_ip));
	   
	   
	   //-------------------------------------------------------------------
	   // feed grants back to input stage
	   //-------------------------------------------------------------------
	   
	   assign gnt_out_nonspec_op_ip[op*num_ports:(op+1)*num_ports-1]
		    = gnt_out_nonspec_ip;
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   if(spec_level > 0)
	     begin
		
		//--------------------------------------------------------------
		// perform output-side arbitration (speculative)
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] req_out_spec_ip;
		assign req_out_spec_ip
		  = req_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1];
		
		wire [0:num_ports-1] spec_mask_ip;
		assign spec_mask_ip
		  = spec_mask_op_ip[op*num_ports:(op+1)*num_ports-1];
		
		// only update priorities if there is no conflicting non-
		// speculative request
		wire 		     update_arb_spec;
		assign update_arb_spec = |(req_out_spec_ip & spec_mask_ip);
		
		wire [0:num_ports-1] gnt_out_unmasked_spec_ip;
		arbiter
		  #(.num_ports(num_ports),
		    .reset_type(reset_type),
		    .arbiter_type(arbiter_type),
		    .mask(mask_op_ip[op*num_ports:(op+1)*num_ports-1]))
		gnt_out_unmasked_spec_ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb_spec),
		   .req(req_out_spec_ip),
		   .gnt(gnt_out_unmasked_spec_ip));
		
		wire [0:num_ports-1] gnt_out_spec_ip;
		assign gnt_out_spec_ip
		  = gnt_out_unmasked_spec_ip & spec_mask_ip;
		
		
		//--------------------------------------------------------------
		// feed grants back to input stage (speculative)
		//--------------------------------------------------------------
		
		assign gnt_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1]
			 = gnt_out_spec_ip;
		
	     end
	   else
	     begin
		
		assign gnt_out_spec_op_ip[op*num_ports:(op+1)*num_ports-1]
			 = {num_ports{1'b0}};
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global outputs
   //---------------------------------------------------------------------------
   
   assign sw_gnt_ip_op = gnt_out_nonspec_ip_op | gnt_out_spec_ip_op;
   
endmodule
