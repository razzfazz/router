module sw_alloc_core_wf
  (clk, reset, sw_req_nonspec_ip_ivc_op, sw_req_spec_ip_ivc_op,
   sw_gnt_nonspec_ip_ivc, sw_gnt_spec_ip_ivc, sw_gnt_ip_op);
   
`include "functions.v"
`include "constants.v"
`include "config.v"
`include "config_utils.v"
   
   parameter error_recovery = 0;
   
   parameter reset_type = reset_type_async;
   
   /*
    0: wavefront, mux inputs for priority
    1: wavefront, replicate logic for priorities
    2: wavefront, diagonal propagation allocator
    3: wavefront, rotate inputs for priority
    4: wavefront, false combinational loop
    */
   parameter allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter arbiter_type = 0;
   
   /*
    0: disable speculative switch allocation
    1: only use speculative grants if no non-speculative requests/grants present
    2: use speculative grants when not conflicting with non-spec requests
    3: use speculative grants when not conflicting with non-spec grants
    */
   parameter spec_level = 0;
   
   localparam [0:num_ports*num_ports-1] mask_ip_op
     = create_mask_ip_op(ignore_same_port);
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] sw_req_nonspec_ip_ivc_op;
   input [0:num_ports*num_vcs*num_ports-1] sw_req_spec_ip_ivc_op;
   
   output [0:num_ports*num_vcs-1] sw_gnt_nonspec_ip_ivc;
   output [0:num_ports*num_vcs-1] sw_gnt_spec_ip_ivc;
   output [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   wire [0:num_ports*num_vcs-1] sw_gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] sw_gnt_spec_ip_ivc;
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
      
      genvar 			  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // combine requests from all VCs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
	   assign sw_req_nonspec_ivc_op
	     = sw_req_nonspec_ip_ivc_op[ip*num_vcs*num_ports:
					(ip+1)*num_vcs*num_ports-1] &
	       {num_vcs{mask_ip_op[ip*num_ports:(ip+1)*num_ports-1]}};
	   
	   wire [0:num_vcs*num_ports-1] req_in_nonspec_ivc_op;
	   assign req_in_nonspec_ivc_op = sw_req_nonspec_ivc_op;
	   
	   wire [0:num_ports-1] 	req_out_nonspec_op;
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_out_nonspec_op_or
	     (.data_in(sw_req_nonspec_ivc_op),
	      .data_out(req_out_nonspec_op));
	   
	   assign req_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
		    = req_out_nonspec_op;
	   
	   
	   //-------------------------------------------------------------------
	   // pre-select winning VC for each output
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports*num_vcs-1] req_in_nonspec_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req_in_nonspec_op_ivc_intl
	     (.data_in(req_in_nonspec_ivc_op),
	      .data_out(req_in_nonspec_op_ivc));
	   
	   wire [0:num_ports-1] 	gnt_out_nonspec_op;
	   assign gnt_out_nonspec_op
	     = gnt_out_nonspec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_ports*num_vcs-1] gnt_in_nonspec_op_ivc;
	   genvar 			op;
	   for(op = 0;
	       op < num_ports;
	       op = op + 1)
	     begin:nonspec_ops
		
		wire 			update_arb_nonspec;
		assign update_arb_nonspec = gnt_out_nonspec_op[op];
		
		wire [0:num_vcs-1] 	req_in_nonspec_ivc;
		assign req_in_nonspec_ivc
		  = req_in_nonspec_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		
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
		
		assign gnt_in_nonspec_op_ivc[op*num_vcs:(op+1)*num_vcs-1]
			 = gnt_in_nonspec_ivc;
		
	     end
	   
	   wire [0:num_vcs*num_ports-1] gnt_in_nonspec_ivc_op;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt_in_nonspec_ivc_op_intl
	     (.data_in(gnt_in_nonspec_op_ivc),
	      .data_out(gnt_in_nonspec_ivc_op));
	   
	   
	   //-------------------------------------------------------------------
	   // use output-side grants to select winning VC
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] req_masked_nonspec_ivc_op;
	   assign req_masked_nonspec_ivc_op
	     = {num_vcs{gnt_out_nonspec_op}} & gnt_in_nonspec_ivc_op;
	   
	   wire [0:num_ports*num_vcs-1] req_masked_nonspec_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req_masked_nonspec_ivc_op_intl
	     (.data_in(req_masked_nonspec_ivc_op),
	      .data_out(req_masked_nonspec_op_ivc));
	   
	   wire [0:num_vcs-1] 		sw_gnt_nonspec_ivc;
	   or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   sw_gnt_nonspec_ivc_or
	     (.data_in(req_masked_nonspec_op_ivc),
	      .data_out(sw_gnt_nonspec_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // handle speculative requests
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs-1] 		sw_gnt_spec_ivc;
	   
	   if(spec_level > 0)
	     begin
		
		//--------------------------------------------------------------
		// combine requests from all VCs
		//--------------------------------------------------------------
		
		wire [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
		assign sw_req_spec_ivc_op
		  = sw_req_spec_ip_ivc_op[ip*num_vcs*num_ports:
					     (ip+1)*num_vcs*num_ports-1] &
		    {num_vcs{mask_ip_op[ip*num_ports:(ip+1)*num_ports-1]}};
		
		wire [0:num_vcs*num_ports-1] req_in_spec_ivc_op;
		assign req_in_spec_ivc_op = sw_req_spec_ivc_op;
		
		wire [0:num_ports-1] 	     req_out_spec_op;
		or_nto1
		  #(.width(num_ports),
		    .num_ports(num_vcs))
		req_out_spec_op_or
		  (.data_in(sw_req_spec_ivc_op),
		   .data_out(req_out_spec_op));
		
		assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 = req_out_spec_op;
		
		
		//--------------------------------------------------------------
		// pre-select winning VC for each output
		//--------------------------------------------------------------
		
		wire [0:num_ports*num_vcs-1] req_in_spec_op_ivc;
		interleaver
		  #(.width(num_vcs*num_ports),
		    .num_blocks(num_vcs))
		req_in_spec_op_ivc_intl
		  (.data_in(req_in_spec_ivc_op),
		   .data_out(req_in_spec_op_ivc));
		
		wire [0:num_ports-1] 	     gnt_out_spec_op;
		assign gnt_out_spec_op
		  = gnt_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1];
		
		wire [0:num_ports*num_vcs-1] gnt_in_spec_op_ivc;
		for(op = 0; op < num_ports; op = op + 1)
		  begin:spec_ops
		     
		     wire 			update_arb_spec;
		     assign update_arb_spec = gnt_out_spec_op[op];
		     
		     wire [0:num_vcs-1] 	req_in_spec_ivc;
		     assign req_in_spec_ivc
		       = req_in_spec_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		     
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
		     
		     assign gnt_in_spec_op_ivc[op*num_vcs:(op+1)*num_vcs-1]
			      = gnt_in_spec_ivc;
		     
		  end
		
		wire [0:num_vcs*num_ports-1] 	gnt_in_spec_ivc_op;
		interleaver
		  #(.width(num_vcs*num_ports),
		    .num_blocks(num_ports))
		gnt_in_spec_ivc_op_intl
		  (.data_in(gnt_in_spec_op_ivc),
		   .data_out(gnt_in_spec_ivc_op));
		
		
		//--------------------------------------------------------------
		// use output-side grants to select winning VC
		//--------------------------------------------------------------
		
		wire [0:num_vcs*num_ports-1] 	req_masked_spec_ivc_op;
		assign req_masked_spec_ivc_op
		  = {num_vcs{gnt_out_spec_op}} & gnt_in_spec_ivc_op;
		
		wire [0:num_ports*num_vcs-1] 	req_masked_spec_op_ivc;
		interleaver
		  #(.width(num_vcs*num_ports),
		    .num_blocks(num_vcs))
		req_masked_spec_ivc_op_intl
		  (.data_in(req_masked_spec_ivc_op),
		   .data_out(req_masked_spec_op_ivc));
		
		or_nto1
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		sw_gnt_spec_ivc_or
		  (.data_in(req_masked_spec_op_ivc),
		   .data_out(sw_gnt_spec_ivc));
		
	     end
	   else
	     begin
		
		assign req_out_spec_ip_op[ip*num_ports:(ip+1)*num_ports-1]
			 ={num_ports{1'b0}};
		assign sw_gnt_spec_ivc = {num_vcs{1'b0}};
		
	     end
	   
	   
	   //-------------------------------------------------------------------
	   // combine global grants
	   //-------------------------------------------------------------------
	   
	   assign sw_gnt_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_gnt_nonspec_ivc;
	   assign sw_gnt_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
		    = sw_gnt_spec_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // mask speculative requests that conflict with non-speculative ones
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 		spec_mask_ip_op;
   generate
      
      case(spec_level)
	0:
	  begin
	     
	     assign spec_mask_ip_op
	       = {num_ports*num_ports{1'b0}};
	     
	  end
	1:
	  begin
	     
	     assign spec_mask_ip_op
	       = {num_ports*num_ports{~|req_out_nonspec_ip_op}};
	     
	  end
	2:
	  begin
	     
	     wire [0:num_ports*num_ports-1] req_out_nonspec_op_ip;
	     interleaver
	       #(.width(num_ports*num_ports),
		 .num_blocks(num_ports))
	     req_out_nonspec_op_ip_intl
	       (.data_in(req_out_nonspec_ip_op),
		.data_out(req_out_nonspec_op_ip));
	     
	     wire [0:num_ports-1] 	    any_req_ip;
	     or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_req_ip_or
	       (.data_in(req_out_nonspec_op_ip),
		.data_out(any_req_ip));
	     
	     wire [0:num_ports*num_ports-1] any_req_in_ip_op;
	     replicator
	       #(.width(num_ports),
		 .count(num_ports))
	     any_req_in_ip_op_repl
	       (.data_in(any_req_ip),
		.data_out(any_req_in_ip_op));
	     
	     wire [0:num_ports-1] any_req_op;
	     or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_req_op_or
	       (.data_in(req_out_nonspec_ip_op),
		.data_out(any_req_op));
	     
	     wire [0:num_ports*num_ports-1] any_req_out_ip_op;
	     assign any_req_out_ip_op = {num_ports{any_req_op}};
	     
	     assign spec_mask_ip_op = ~(any_req_in_ip_op | any_req_out_ip_op);
	     
	  end
	3:
	  begin
	     
	     wire [0:num_ports*num_ports-1] gnt_out_nonspec_op_ip;
	     interleaver
	       #(.width(num_ports*num_ports),
		 .num_blocks(num_ports))
	     gnt_out_nonspec_op_ip_intl
	       (.data_in(gnt_out_nonspec_ip_op),
		.data_out(gnt_out_nonspec_op_ip));
	     
	     wire [0:num_ports-1] 	    any_gnt_ip;
	     or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_gnt_ip_or
	       (.data_in(gnt_out_nonspec_op_ip),
		.data_out(any_gnt_ip));
	     
	     wire [0:num_ports*num_ports-1] any_gnt_in_ip_op;
	     replicator
	       #(.width(num_ports),
		 .count(num_ports))
	     any_gnt_in_ip_op_repl
	       (.data_in(any_gnt_ip),
		.data_out(any_gnt_in_ip_op));
	     
	     wire [0:num_ports-1] any_gnt_op;
	     or_nto1
	       #(.width(num_ports),
		 .num_ports(num_ports))
	     any_gnt_op_or
	       (.data_in(gnt_out_nonspec_ip_op),
		.data_out(any_gnt_op));
	     
	     wire [0:num_ports*num_ports-1] any_gnt_out_ip_op;
	     assign any_gnt_out_ip_op = {num_ports{any_gnt_op}};
	     
	     assign spec_mask_ip_op = ~(any_gnt_in_ip_op | any_gnt_out_ip_op);
	     
	  end
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output stage (match first-stage requests to output ports)
   //---------------------------------------------------------------------------
   
   // if there are any requests at all in a cycle, at least one of them will
   // eventually be granted, so update priorities
   wire 				update_alloc_nonspec;
   assign update_alloc_nonspec = |req_out_nonspec_ip_op;
   
   wf_alloc
     #(.num_ports(num_ports),
       .allocator_type(allocator_type),
       .mask(mask_ip_op),
       .error_recovery(error_recovery),
       .reset_type(reset_type))
   gnt_out_nonspec_ip_op_alloc
     (.clk(clk),
      .reset(reset),
      .update(update_alloc_nonspec),
      .req(req_out_nonspec_ip_op),
      .gnt(gnt_out_nonspec_ip_op));
   
   generate
      
      if(spec_level > 0)
	begin
	   
	   // only update priorities if there is no conflicting non-
	   // speculative request
	   wire 				update_alloc_spec;
	   assign update_alloc_spec = |(req_out_spec_ip_op & spec_mask_ip_op);
	   
	   wire [0:num_ports*num_ports-1] 	gnt_out_unmasked_spec_ip_op;
	   wf_alloc
	     #(.num_ports(num_ports),
	       .allocator_type(allocator_type),
	       .mask(mask_ip_op),
	       .error_recovery(error_recovery),
	       .reset_type(reset_type))
	   gnt_out_unmasked_spec_ip_op_alloc
	     (.clk(clk),
	      .reset(reset),
	      .update(update_alloc_spec),
	      .req(req_out_spec_ip_op),
	      .gnt(gnt_out_unmasked_spec_ip_op));
	   
	   assign gnt_out_spec_ip_op
	     = gnt_out_unmasked_spec_ip_op & spec_mask_ip_op;
	   
	end
      else
	begin
	   
	   assign gnt_out_spec_ip_op = {num_ports*num_ports{1'b0}};
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grants
   //---------------------------------------------------------------------------
   
   assign sw_gnt_ip_op = gnt_out_nonspec_ip_op | gnt_out_spec_ip_op;
   
endmodule
