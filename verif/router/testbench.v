module testbench
  ();
   
   parameter Tclk = 2;
   parameter sim_cycles = 1000;
   parameter initial_seed = 0;
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "sim_functions.v"
   
   parameter reset_type = reset_type_async;
   
   // current router's address
   parameter [0:addr_width-1] address = 40;
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter enable_spec_sw_alloc = 1;
   
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
    0: use tristate buses
    1: use multiplexers
    */
   parameter crossbar_type = 1;
   
   // use dedicated registers to store port credit summary bits per input VC
   parameter dedicated_free_ivc_regs = 1;
   
   // minimum number of available buffers required to consider VC free
   // NOTE: This must be greater than or equal to 2 for the current 
   // implementation to work correctly!
   parameter buffer_free_threshold = 2;
   
   parameter packet_length = 1;
   parameter packet_rate = 50;
   parameter adaptive_rate = 0;
   parameter packet_count_width = 32;
   parameter credit_latency = 4;
   
   
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
		
	     end
	   else
	     begin
		
		wire cred_valid_in;
		wire [0:vc_idx_width-1] cred_vc_in;
		
		wire [0:credit_latency-1] cred_valid_dly_s,
					  cred_valid_dly_q;
		wire [0:credit_latency*vc_idx_width-1] cred_vc_dly_s,
						       cred_vc_dly_q;
		
		if(credit_latency > 1)
		  begin
		     assign cred_valid_dly_s
		       = {cred_valid_out_ip[ip],
			  cred_valid_dly_q[0:(credit_latency-1)-1]};
		     assign cred_valid_in
		       = cred_valid_dly_q[(credit_latency-1):credit_latency-1];
		     assign cred_vc_dly_s
		       = {cred_vc_out_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1],
			  cred_vc_dly_q[0:vc_idx_width*(credit_latency-1)-1]};
		     assign cred_vc_in
		       = cred_vc_dly_q[vc_idx_width*(credit_latency-1):
				       vc_idx_width*credit_latency-1];
		  end
		else
		  begin
		     assign cred_valid_dly_s = cred_valid_out_ip[ip];
		     assign cred_valid_in = cred_valid_dly_q;
		     assign cred_vc_dly_s
		       = cred_vc_out_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1];
		     assign cred_vc_in = cred_vc_dly_q;
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
		
		wire [0:num_vcs-1] 	vc_gnt_ivc;
		
		wire 			flit_valid_in;
		wire [0:vc_idx_width-1] flit_vc_in;
		wire 			flit_head_in;
		wire 			flit_tail_in;
		wire [0:data_width-1] 	flit_data_in;
		
		wire [0:num_vcs-1] 	elig_ivc;
		wire [0:num_vcs-1] 	free_ivc;
		wire [0:num_vcs-1] 	unused1;
		wire [0:num_vcs-1] 	unused2;
		op_ctrl
		  #(.reset_type(reset_type),
		    .dedicated_free_ivc_regs(0),
		    .buffer_free_threshold(1))
		opcc
		  (.clk(clk),
		   .reset(reset),
		   .cred_valid_in(cred_valid_in),
		   .cred_vc_in(cred_vc_in),
		   .vc_gnt_ovc(vc_gnt_ivc),
		   .flit_valid_in(flit_valid_in),
		   .flit_vc_in(flit_vc_in),
		   .flit_tail_in(flit_tail_in),
		   .elig_ovc(elig_ivc),
		   .free_ovc(free_ivc),
		   .free_plus1_ovc(unused1),
		   .free_ivc(unused2));
		
		wire [0:num_vcs-1] 	flit_valid_ivc;
		wire [0:num_vcs-1] 	flit_head_ivc;
		wire [0:num_vcs-1] 	flit_tail_ivc;
		wire [0:num_vcs*data_width-1] flit_data_ivc;
		
		wire [0:num_vcs-1] 	      vc_req_ivc;
		wire [0:num_vcs-1] 	      sw_req_ivc;
		wire [0:num_vcs-1] 	      sw_gnt_ivc;
		
		genvar 			      ivc;
		for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		  begin:ivcs
		     
		     wire vc_gnt;
		     assign vc_gnt = vc_gnt_ivc[ivc];
		     
		     wire sw_gnt;
		     assign sw_gnt = sw_gnt_ivc[ivc];
		     
		     wire flit_valid;
		     wire flit_head;
		     wire flit_tail;
		     wire [0:data_width-1] flit_data;
		     wire 		   vc_req;
		     wire 		   sw_req;
		     
		     packet_source
		       #(.packet_length(packet_length),
			 .packet_rate(packet_rate),
			 .initial_seed(initial_seed+ip*num_vcs+ivc),
			 .reset_type(reset_type),
			 .adaptive_rate(adaptive_rate),
			 .packet_count_width(packet_count_width),
			 .address(address+ip-(num_ports-num_nodes_per_router)))
		     ps
		       (.clk(clk),
			.reset(reset),
			.flit_valid(flit_valid),
			.flit_head(flit_head),
			.flit_tail(flit_tail),
			.flit_data(flit_data),
			.vc_req(vc_req),
			.vc_gnt(vc_gnt),
			.sw_req(sw_req),
			.sw_gnt(sw_gnt));
		     
		     assign flit_valid_ivc[ivc] = flit_valid;
		     assign flit_head_ivc[ivc] = flit_head;
		     assign flit_tail_ivc[ivc] = flit_tail;
		     assign flit_data_ivc[ivc*data_width:(ivc+1)*data_width-1]
			      = flit_data;
		     
		     assign vc_req_ivc[ivc] = vc_req;
		     assign sw_req_ivc[ivc] = sw_req;
		     
		  end
		
		wire [0:num_vcs-1] 	   vc_req_qual_ivc;
		assign vc_req_qual_ivc = vc_req_ivc & elig_ivc;
		arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .arbiter_type(vc_arbiter_type))
		vc_gnt_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(|vc_req_qual_ivc),
		   .req(vc_req_qual_ivc),
		   .gnt(vc_gnt_ivc));
		
		wire [0:num_vcs-1] 	   sw_req_qual_ivc;
		assign sw_req_qual_ivc = sw_req_ivc & free_ivc;
		arbiter
		  #(.num_ports(num_vcs),
		    .reset_type(reset_type),
		    .arbiter_type(sw_arbiter_type))
		sw_gnt_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(|sw_req_qual_ivc),
		   .req(sw_req_qual_ivc),
		   .gnt(sw_gnt_ivc));
		
		assign flit_valid_in = |flit_valid_ivc;
		
		encoder
		  #(.num_ports(num_vcs))
		flit_vc_in_enc
		  (.data_in(flit_valid_ivc),
		   .data_out(flit_vc_in));
		
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(1))
		flit_head_in_sel
		  (.select(flit_valid_ivc),
		   .data_in(flit_head_ivc),
		   .data_out(flit_head_in));
		
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(1))
		flit_tail_in_sel
		  (.select(flit_valid_ivc),
		   .data_in(flit_tail_ivc),
		   .data_out(flit_tail_in));
		
		select_1ofn
		  #(.num_ports(num_vcs),
		    .width(data_width))
		flit_data_in_sel
		  (.select(flit_valid_ivc),
		   .data_in(flit_data_ivc),
		   .data_out(flit_data_in));
		
		wire 			   error;
		assign error = pop_count(flit_valid_ivc) > 1;
		
		assign flit_valid_in_ip[ip] = flit_valid_in;
		assign flit_vc_in_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]
			 = flit_vc_in;
		assign flit_head_in_ip[ip] = flit_head_in;
		assign flit_tail_in_ip[ip] = flit_tail_in;
		assign flit_data_in_ip[ip*data_width:(ip+1)*data_width-1]
			 = flit_data_in;
		
	     end
	   
	end
      
   endgenerate
   
   router
     #(.reset_type(reset_type),
       .address(address),
       .enable_spec_sw_alloc(enable_spec_sw_alloc),
       .replicate_port_decoder(replicate_port_decoder),
       .vc_allocator_type(vc_allocator_type),
       .vc_arbiter_type(vc_arbiter_type),
       .sw_allocator_type(sw_allocator_type),
       .sw_arbiter_type(sw_arbiter_type),
       .crossbar_type(crossbar_type),
       .dedicated_free_ivc_regs(dedicated_free_ivc_regs),
       .buffer_free_threshold(buffer_free_threshold))
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
      .cred_vc_in_op(cred_vc_in_op));
   
   wire [0:num_ports*credit_latency-1] cred_valid_dly_op_s,
				       cred_valid_dly_op_q;
   wire [0:num_ports*credit_latency*vc_idx_width-1] cred_vc_dly_op_s,
						    cred_vc_dly_op_q;
   generate
      
      if(credit_latency > 1)
	begin
	   assign cred_valid_dly_op_s
	     = {flit_valid_out_op,
		cred_valid_dly_op_q[0:num_ports*(credit_latency-1)-1]};
	   assign cred_valid_in_op
	     = cred_valid_dly_op_q[num_ports*(credit_latency-1):
				   num_ports*credit_latency-1];
	   assign cred_vc_dly_op_s
	     = {flit_vc_out_op,
		cred_vc_dly_op_q[0:
				 num_ports*vc_idx_width*(credit_latency-1)-1]};
	   assign cred_vc_in_op
	     = cred_vc_dly_op_q[num_ports*vc_idx_width*(credit_latency-1):
				num_ports*vc_idx_width*credit_latency-1];
	end
      else
	begin
	   assign cred_valid_dly_op_s = flit_valid_out_op;
	   assign cred_valid_in_op = cred_valid_dly_op_q;
	   assign cred_vc_dly_op_s = flit_vc_out_op;
	   assign cred_vc_in_op = cred_vc_dly_op_q;
	end
      
   endgenerate
   
   dff
     #(.width(num_ports*credit_latency),
       .reset_type(reset_type))
   cred_valid_dly_opq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_dly_op_s),
      .q(cred_valid_dly_op_q));
   
   dff
     #(.width(num_ports*vc_idx_width*credit_latency),
       .reset_type(reset_type))
   cred_vc_dly_opq
     (.clk(clk),
      .reset(reset),
      .d(cred_vc_dly_op_s),
      .q(cred_vc_dly_op_q));
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   initial
   begin
      
      reset = 1'b1;
      
      #(2*Tclk);
      
      reset = 1'b0;
      
      #(sim_cycles*Tclk);
      
      $finish;
      
   end
   
endmodule
