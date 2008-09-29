module testbench
  ();
   
   parameter Tclk = 2;
   parameter initial_seed = 0;
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "sim_functions.v"
   
   parameter reset_type = reset_type_async;
   
   // current router's address
   parameter [0:addr_width-1] address = 40;
   
   // replicate port decoding logic in routing logic
   parameter replicate_port_decoder = 1;
   
   /*
    0: separable, input-first
    1: separable, output-first
    */
   parameter vc_allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter vc_arbiter_type = 1;
   
   /*
    0: separable, input-first
    1: separable, output-first
    2: wavefront, mux inputs for priority
    3: wavefront, replicate logic for priorities
    4: wavefront, diagonal propagation allocator
    5: wavefront, rotate inputs for priority
    */
   parameter sw_allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter sw_arbiter_type = 1;
   
   /*
    0: disable speculative switch allocation
    1: only use speculative grants if no non-speculative requests were issued
    2: use speculative grants when not conflicting with non-spec requests
    3: use speculative grants when not conflicting with non-spec grants
    */
   parameter sw_spec_level = 3;
   
   /*
    0: do not check credit for speculative switch allocation (e.g. if implicit
       credit check is performed during VC allocation)
    1: check that credit is available at all potential output VCs before issuing
       request
    2: check that credit is available at all potential output VCs in parallel
       with allocation, then mask grants
    3: check that credit is available at slected output VC while doing
       allocation, then mask grants
    */
   parameter sw_spec_cred_check = 0;
   
   /*
    0: use tristate buses
    1: use multiplexers
    */
   parameter crossbar_type = 1;
   
   parameter walk_addresses = 0;
   parameter packet_count = 1000;
   parameter packet_length = 4;
   parameter packet_rate = 50;
   parameter adaptive_rate = 1;
   parameter packet_count_width = 32;
   parameter credit_latency = 8;
   localparam flit_idx_width = clogb(packet_length);
   
   
   reg 		    reset;
   reg 		    clk;
   
   wire [0:num_ports-1] flit_valid_in_ip;
   wire [0:num_ports*vc_idx_width-1] flit_vc_in_ip;
   wire [0:num_ports-1] 	     flit_head_in_ip;
   wire [0:num_ports-1] 	     flit_tail_in_ip;
   wire [0:num_ports*data_width-1]   flit_data_in_ip;
   wire [0:num_ports-1] 	     cred_valid_out_ip;
   wire [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   wire [0:num_ports-1] 	     flit_valid_out_op;
   wire [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   wire [0:num_ports-1] 	     flit_head_out_op;
   wire [0:num_ports-1] 	     flit_tail_out_op;
   wire [0:num_ports*data_width-1]   flit_data_out_op;
   wire [0:num_ports-1] 	     cred_valid_in_op;
   wire [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   wire [0:num_ports-1] 	     done_ip;
   wire [0:num_ports-1] 	     ps_error_ip;
   
   generate
      
      genvar 			     ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   if(ip < num_ports - num_nodes_per_router)
	     begin
		
		assign flit_valid_in_ip[ip] = 1'b0;
		assign flit_vc_in_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]
			 = {vc_idx_width{1'b0}};
		assign flit_head_in_ip[ip] = 1'b0;
		assign flit_tail_in_ip[ip] = 1'b0;
		assign flit_data_in_ip[ip*data_width:(ip+1)*data_width-1]
			 = {data_width{1'b0}};
		assign done_ip[ip] = 1'b1;
		assign ps_error_ip[ip] = 1'b0;
		
	     end
	   else
	     begin
		
		wire cred_valid;
		wire [0:vc_idx_width-1] cred_vc;
		
		wire [0:credit_latency-1] cred_valid_dly_s,
					  cred_valid_dly_q;
		wire [0:credit_latency*vc_idx_width-1] cred_vc_dly_s,
						       cred_vc_dly_q;
		
		if(credit_latency > 1)
		  begin
		     assign cred_valid_dly_s
		       = {cred_valid_out_ip[ip],
			  cred_valid_dly_q[0:(credit_latency-1)-1]};
		     assign cred_valid
		       = cred_valid_dly_q[(credit_latency-1):credit_latency-1];
		     assign cred_vc_dly_s
		       = {cred_vc_out_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1],
			  cred_vc_dly_q[0:vc_idx_width*(credit_latency-1)-1]};
		     assign cred_vc
		       = cred_vc_dly_q[vc_idx_width*(credit_latency-1):
				       vc_idx_width*credit_latency-1];
		  end
		else
		  begin
		     assign cred_valid_dly_s = cred_valid_out_ip[ip];
		     assign cred_valid = cred_valid_dly_q;
		     assign cred_vc_dly_s
		       = cred_vc_out_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1];
		     assign cred_vc = cred_vc_dly_q;
		  end
		
		dff
		  #(.width(credit_latency),
		    .reset_type(reset_type))
		cred_valid_dlyq
		  (.clk(clk),
		   .reset(reset),
		   .d(cred_valid_dly_s),
		   .q(cred_valid_dly_q));
		
		dff
		  #(.width(vc_idx_width*credit_latency),
		    .reset_type(reset_type))
		cred_vc_dlyq
		  (.clk(clk),
		   .reset(reset),
		   .d(cred_vc_dly_s),
		   .q(cred_vc_dly_q));
		
		wire 			flit_valid;
		wire [0:vc_idx_width-1] flit_vc;
		wire 			flit_head;
		wire 			flit_tail;
		wire [0:data_width-1] 	flit_data;
		
		wire 			done;
		wire 			ps_error;
		packet_source
		  #(.packet_count(packet_count),
		    .packet_length(packet_length),
		    .packet_rate(packet_rate),
		    .initial_seed(initial_seed+ip),
		    .reset_type(reset_type),
		    .adaptive_rate(adaptive_rate),
		    .packet_count_width(packet_count_width),
		    .address(address+ip-(num_ports-num_nodes_per_router)),
		    .walk_addresses(walk_addresses))
		ps
		  (.clk(clk),
		   .reset(reset),
		   .flit_valid(flit_valid),
		   .flit_vc(flit_vc),
		   .flit_head(flit_head),
		   .flit_tail(flit_tail),
		   .flit_data(flit_data),
		   .cred_valid(cred_valid),
		   .cred_vc(cred_vc),
		   .done(done),
		   .error(ps_error));
		
		assign flit_valid_in_ip[ip] = flit_valid;
		assign flit_vc_in_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]
			 = flit_vc;
		assign flit_head_in_ip[ip] = flit_head;
		assign flit_tail_in_ip[ip] = flit_tail;
		assign flit_data_in_ip[ip*data_width:(ip+1)*data_width-1]
			 = flit_data;
		assign done_ip[ip] = done;
		assign ps_error_ip[ip] = ps_error;
		
	     end
	   
	end
      
   endgenerate
   
   wire 				rtr_error;
   
   router
     #(.reset_type(reset_type),
       .address(address),
       .replicate_port_decoder(replicate_port_decoder),
       .vc_allocator_type(vc_allocator_type),
       .vc_arbiter_type(vc_arbiter_type),
       .sw_allocator_type(sw_allocator_type),
       .sw_arbiter_type(sw_arbiter_type),
       .sw_spec_level(sw_spec_level),
       .crossbar_type(crossbar_type))
   rtr
     (.clk(clk),
      .reset(reset),
      .flit_valid_in_ip(flit_valid_in_ip),
      .flit_vc_in_ip(flit_vc_in_ip),
      .flit_head_in_ip(flit_head_in_ip),
      .flit_tail_in_ip(flit_tail_in_ip),
      .flit_data_in_ip(flit_data_in_ip),
      .cred_valid_out_ip(cred_valid_out_ip),
      .cred_vc_out_ip(cred_vc_out_ip),
      .flit_valid_out_op(flit_valid_out_op),
      .flit_vc_out_op(flit_vc_out_op),
      .flit_head_out_op(flit_head_out_op),
      .flit_tail_out_op(flit_tail_out_op),
      .flit_data_out_op(flit_data_out_op),
      .cred_valid_in_op(cred_valid_in_op),
      .cred_vc_in_op(cred_vc_in_op),
      .error(rtr_error));
   
   wire [0:num_ports*num_vcs-1] 	error_op_ovc;
   
   generate
      
      genvar 					    op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:credit_latency-1] cred_valid_dly_s, cred_valid_dly_q;
	   wire [0:credit_latency*vc_idx_width-1] cred_vc_dly_s, cred_vc_dly_q;
	   
	   dff
	     #(.width(credit_latency),
	       .reset_type(reset_type))
	   cred_valid_dlyq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_valid_dly_s),
	      .q(cred_valid_dly_q));
	   
	   dff
	     #(.width(vc_idx_width*credit_latency),
	       .reset_type(reset_type))
	   cred_vc_dlyq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_vc_dly_s),
	      .q(cred_vc_dly_q));
	   
	   if(credit_latency > 1)
	     begin
		assign cred_valid_dly_s
		  = {flit_valid_out_op[op],
		     cred_valid_dly_q[0:(credit_latency-1)-1]};
		assign cred_valid_in_op[op]
		  = cred_valid_dly_q[(credit_latency-1):credit_latency-1];
		assign cred_vc_dly_s
		  = {flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1],
		     cred_vc_dly_q[0:vc_idx_width*(credit_latency-1)-1]};
		assign cred_vc_in_op[op*vc_idx_width:(op+1)*vc_idx_width-1]
		  = cred_vc_dly_q[vc_idx_width*(credit_latency-1):
				  vc_idx_width*credit_latency-1];
	     end
	   else
	     begin
		assign cred_valid_dly_s = flit_valid_out_op[op];
		assign cred_valid_in_op[op] = cred_valid_dly_q;
		assign cred_vc_dly_s
		  = flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1];
		assign cred_vc_in_op[op*vc_idx_width:(op+1)*vc_idx_width-1]
			 = cred_vc_dly_q;
	     end
	   
	   genvar ovc;
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		wire flit_valid;
		assign flit_valid
		  = flit_valid_out_op[op] &&
		    (flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1] ==
		     ovc);
		
		if(packet_length > 1)
		  begin

		     wire wait_head_s, wait_head_q;
		     assign wait_head_s = (wait_head_q &
					   ~(flit_valid &
					     flit_head_out_op[op])) |
					  (flit_valid &
					   flit_tail_out_op[op]);
		     dff
		       #(.width(1),
			 .reset_type(reset_type),
			 .reset_value(1'b1))
		     wait_headq
		       (.clk(clk),
			.reset(reset),
			.d(wait_head_s),
			.q(wait_head_q));
		     
		     wire wait_tail_s, wait_tail_q;
		     assign wait_tail_s = (wait_tail_q &
					   ~(flit_valid &
					     flit_tail_out_op[op])) |
					  (flit_valid &
					   flit_head_out_op[op]);
		     dff
		       #(.width(1),
			 .reset_type(reset_type))
		     wait_tailq
		       (.clk(clk),
			.reset(reset),
			.d(wait_tail_s),
			.q(wait_tail_q));
		     
		     wire [0:flit_idx_width-1] flit_ctr_s, flit_ctr_q;
		     assign flit_ctr_s = (wait_head_q ?
					  (packet_length - 1'b1) :
					  flit_ctr_q) - flit_valid;
		     dff
		       #(.width(flit_idx_width),
			 .reset_type(reset_type),
			 .reset_value(packet_length-1))
		     flit_ctrq
		       (.clk(clk),
			.reset(reset),
			.d(flit_ctr_s),
			.q(flit_ctr_q));
		     
		     assign error_op_ovc[op*num_vcs+ovc]
			      = flit_valid &
				((flit_head_out_op[op] & ~wait_head_q) |
				 (flit_tail_out_op[op] & ~wait_tail_q) |
				 (flit_tail_out_op[op] ^ ~|flit_ctr_q));
		     
		  end
		else
		  begin
		     
		     assign error_op_ovc[op*num_vcs+ovc]
			      = flit_valid &
				~(flit_head_out_op[op] & flit_tail_out_op[op]);
		     
		  end
		
	     end
	   
	end
      
   endgenerate
   
   wire error;
   assign error = |ps_error_ip | rtr_error | |error_op_ovc;
   
   wire [0:31] in_flits_s, in_flits_q;
   assign in_flits_s = in_flits_q + pop_count(flit_valid_in_ip);
   dff
     #(.width(32),
       .reset_type(reset_type))
   in_flitsq
     (.clk(clk),
      .reset(reset),
      .d(in_flits_s),
      .q(in_flits_q));
   
   wire [0:31] in_flits;
   assign in_flits = in_flits_s;
   
   wire [0:31] out_flits_s, out_flits_q;
   assign out_flits_s = out_flits_q + pop_count(flit_valid_out_op);
   dff
     #(.width(32),
       .reset_type(reset_type))
   out_flitsq
     (.clk(clk),
      .reset(reset),
      .d(out_flits_s),
      .q(out_flits_q));
   
   wire [0:31] out_flits;
   assign out_flits = out_flits_s;
   
   reg 	       clk_en;
   
   always
   begin
      clk <= clk_en;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   integer cycles;
   
   initial
   begin

      reset = 1'b0;
      clk_en = 1'b0;
      
      #(Tclk/2);
      
      reset = 1'b1;
      
      #(Tclk);
      
      reset = 1'b0;
      
      #(Tclk);

      clk_en = 1'b1;
      
      #(Tclk/2);
      
      cycles = 0;
      
      while(!(&done_ip) || (in_flits > out_flits))
	begin
	   cycles = cycles + 1;
	   #(Tclk);
	end

      #(Tclk*10);
      
      $display("%d flits sent in %d cycles", out_flits, cycles);
      
      $finish;
      
   end
   
endmodule
