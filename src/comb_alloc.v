// switch allocator
// (wavefront allocator for matching ports)

module comb_alloc_wf

  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_clock_gating = 1,
    
    /* supported architectures:
     0: separable, round-robin arbiters
     1: separable, matrix arbiters
     2: wavefront, rotate inputs for priority, round-robin arbiters
     3: wavefront, rotate inputs for priority, matrix arbiters
     4: wavefront, replicated logic for priority, round-robin arbiters
     5: wavefront, replicated logic for priority, matrix arbiters */
    parameter use_architecture = 0)
   (input     clk,
    input     reset,
    
    input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op,
    input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc,
    input [0:num_ports*num_vcs-1] cred_op_ovc,
    input [0:num_ports*num_vcs-1] elig_op_ovc,
    input [0:num_ports*num_vcs-1] allocated_ip_ivc,
    
    output wire [0:num_ports*num_vcs-1] gnt_ip_ivc,
    output wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc,
    output wire [0:num_ports*num_ports-1] gnt_ip_op);
   
   genvar 				  i, j;
   
   
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

	   wire [0:num_vcs*num_ports-1] req_sw_ivc_op;
	   wire [0:num_vcs*num_ports-1] mask_sw_ivc_op;

	   wire [0:num_ports-1] 	gnt_sw_op;
	   assign gnt_sw_op = gnt_sw_ip_op[i*num_ports:(i+1)*num_ports-1];
	   
	   for(j = 0; j < num_vcs; j = j + 1)
	     begin:input_vcs

		wire [0:num_ports-1] req_op;
		assign req_op = req_ip_ivc_op[(i*num_vcs+j)*num_ports:
					      (i*num_vcs+j+1)*num_ports-1];

		wire [0:num_vcs-1]   req_ovc;
		assign req_ovc = req_ip_ivc_ovc[(i*num_vcs+j)*num_vcs:
						(i*num_vcs+j+1)*num_vcs-1];

		wire 		     allocated;
		assign allocated = allocated_ip_ivc[i*num_vcs+j];

		wire [0:num_vcs-1] elig_ovc;
		select_1ofn
		  #(.width(num_vcs),
		    num_ports(num_ports))
		elig_sel
		  (.select(req_op),
		   .data_in(elig_op_ovc),
		   .data_out(elig_ovc));

		wire [0:num_vcs-1] req_qual_elig_ovc;
		assign req_qual_elig_ovc = req_ovc & elig_ovc;

		wire 		   req_qual_elig;
		assign req_qual_elig = |req_qual_elig_ovc | allocated;
		
		wire [0:num_vcs-1] cred_ovc;
		select_1ofn
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		cred_sel
		  (.select(req_op),
		   .data_in(cred_op_ovc),
		   .data_out(cred_ovc));
		
		wire [0:num_vcs-1] req_qual_cred_ovc;
		assign req_qual_cred_ovc = req_ovc & cred_ovc;

		wire 		   req_qual_cred;
		assign req_qual_cred = |req_qual_cred_ovc;

		wire [0:num_vcs-1] gnt_ovc;
		arbiter
		  #(.num_ports(num_vcs),
		    .use_architecture(use_architecture & 1),
		    .use_clock_gating(use_clock_gating))
		gnt_ovc_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req_qual_elig_ovc),
		   .gnt(gnt_ovc));

		assign gnt_ip_ivc_ovc[(i*num_vcs+j)*num_vcs:
				      (i*num_vcs+j+1)*num_vcs-1]
			 = allocated ? req_ovc : gnt_ovc;

		wire 		   request_port;
		assign req_sw = req_qual_elig & req_qual_cred;
		
		select_1ofn
		  #(.width(num_ports),
		    .num_ports(1))
		req_op_sel
		  (.select(req_sw),
		   .data_in(req_op),
		   .data_out(req_sw_op));

		assign req_sw_ivc_op[j*num_ports:(j+1)*num_ports-1] = req_sw_op;

		wire [0:num_ports-1] mask_sw_op;
		assign mask_sw_op = mask_sw_ivc_op[j*num_ports:
						   (j+1)*num_ports-1];

		wire 		     gnt;
		assign gnt = |(gnt_sw_op & mask_sw_op);

		assign gnt_ip_ivc[i*num_vcs+j] = gnt;
		
	     end

	   wire [0:num_ports-1]    req_sw_op;
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_sw_ivc_or
	     (.data_in(req_sw_ivc_op),
	      .data_out(req_sw_op));

	   assign req_sw_ip_op[i*num_ports:(i+1)*num_ports-1] = req_sw_op;

	   wire [0:num_ports*num_vcs-1] req_sw_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req_sw_intl
	     (.data_in(req_sw_ivc_op),
	      .data_out(req_sw_op_ivc));

	   for(j = 0; j < num_ports; j = j + 1)
	     begin:output_ports

		wire [0:num_vcs-1] req_sw_ivc;
		assign req_sw_ivc = req_sw_op_ivc[j*num_vcs:(j+1)*num_vcs-1];
		
		wire [0:num_vcs-1] mask_sw_ivc;
		arbiter
		  #(.num_ports(num_vcs),
		    .use_architecture(use_architecture & 1),
		    .use_clock_gating(use_clock_gating))
		mask_sw_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req_sw_ivc),
		   .gnt(mask_sw_ivc));

		assign mask_sw_op_ivc[j*num_vcs:(j+1)*num_vcs-1] = mask_sw_ivc;
		
	     end

	   interleaver
	     #(.width(num_port*num_vcs),
	       .num_blocks(num_ports))
	   mask_sw_intl
	     (.data_in(mask_sw_op_ivc),
	      .data_out(mask_sw_ivc_op));

	end

   endgenerate

   generate

      if((use_architecture >= 0) && (use_architecture <= 1))
	begin

	   // [sort order: input port,output port]
	   wire [0:num_ports*num_ports-1] req1_ip_op;
	   wire [0:num_ports*num_ports-1] gnt1_ip_op;   
	   wire [0:num_ports*num_ports-1] gnt2_ip_op;   

	   assign req1_ip_op = req_sw_ip_op;

	   // first stage arbiters
	   for(i = 0; i < num_ports; i = i + 1)
	     begin:input_ports

		wire [0:num_ports-1] req1_op;
		wire [0:num_ports-1] gnt1_op;
		wire [0:num_ports-1] gnt2_op;

		assign req1_op = req1_ip_op[i*num_ports:(i+1)*num_ports-1];
		assign gnt2_op = gnt2_ip_op[i*num_ports:(i+1)*num_ports-1];
		
		wire 		     update;

		assign update = |gnt2_op;
	   
		arbiter
		  #(.num_ports(num_ports),
		    .use_architecture(use_architecture & 1),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(req1_op),
		   .gnt(gnt1_op));

		assign gnt1_ip_op[i*num_ports:(i+1)*num_ports-1] = gnt1_op;
		
	     end

	   // [sort order: input port,output port]
	   wire [0:num_ports*num_ports-1] req2_ip_op;

	   assign req2_ip_op = gnt1_ip_op;

	   // [sort order: output port,input port]
	   wire [0:num_ports*num_ports-1] req2_op_ip;
   
	   interleaver
	     #(.width(num_ports*num_ports),
	       .num_blocks(num_ports))
	   req2_intl
	     (.data_in(req2_ip_op),
	      .data_out(req2_op_ip));

	   // [sort order: output port,input port]
	   wire [0:num_ports*num_ports-1] gnt2_op_ip;

	   // second stage arbiters
	   for(i = 0; i < num_ports; i = i + 1)
	     begin:output_ports
		
		wire [0:num_ports-1] req2_ip;
		wire [0:num_ports-1] gnt2_ip;

		assign req2_ip = req2_op_ip[i*num_ports:(i+1)*num_ports-1];
		
		wire 		     update;
		
		assign update = |req2_ip;
	   
		arbiter
		  #(.num_ports(num_ports),
		    .use_architecture(use_architecture & 1),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(req2_ip),
		   .gnt(gnt2_ip));

		assign gnt2_op_ip[i*num_ports:(i+1)*num_ports-1] = gnt2_ip;
		
	     end
	   
	   interleaver
	     #(.width(num_ports*num_ports),
	       .num_blocks(num_ports))
	   gnt2_intl
	     (.data_in(gnt2_op_ip),
	      .data_out(gnt2_ip_op));

	   assign gnt_sw_ip_op = gnt2_ip_op;
	   
	end
      else if((use_architecture >= 2) && (use_architecture <= 5))
	begin

	   wire update;
	   assign update = |req_ip_ivc_op & |req_ip_ivc_ovc;

	   wf_alloc
	     #(.num_ports(num_ports),
	       .use_clock_gating(use_clock_gating),
	       .use_architecture(use_architecture))
	   sw_alloc
	     (.clk(clk),
	      .reset(reset),
	      .update(update),
	      .req(req_sw_ip_op),
	      .gnt(gnt_sw_ip_op));
	   
	end

   endgenerate
      
endmodule
