module testbench
  ();
   
`include "constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // test for undefined bits
   function is_x(input integer net);
      begin
	 is_x = (^net === 1'bx);
      end
   endfunction
   
   // population count (count ones)
   function integer pop_count(input integer argument);
      integer i;
      begin
	 pop_count = 0;
	 for(i = argument; i > 0; i = i >> 1)
	   pop_count = pop_count + (i & 1);
      end
   endfunction
   
   parameter Tclk = 2;
   parameter initial_seed = 0;
   parameter walk_addresses = 0;
   parameter packet_count = 1000;
   parameter packet_length = 4;
   parameter packet_rate = 50;
   parameter adaptive_rate = 1;
   parameter packet_count_width = 32;
   parameter credit_latency = 8;
   localparam flit_idx_width = clogb(packet_length);
   
   // select network topology
   parameter network_topology = `NETWORK_TOPOLOGY_MESH;
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
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
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // current router's address
   parameter [0:router_addr_width-1] router_address = {router_addr_width{1'b0}};
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       2 :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 1;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;

   // flit width
   parameter data_width = 64;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // try to recover from errors
   parameter error_recovery = 0;
   
   // select routing function type
   localparam routing_function_type
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       `ROUTING_FUNCTION_TYPE_BY_RELATION :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       `ROUTING_FUNCTION_TYPE_BY_DIFFERENCE :
       -1;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // select method for credit checking
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_LEVEL)
   parameter sw_spec_cred_check = `SW_SPEC_CRED_CHECK_SEL_POST;
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   // enable speculative switch allocation
   localparam sw_spec_enable = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select crossbar implementation variant
   parameter crossbar_type = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
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
		    .packet_rate(packet_rate),
		    .initial_seed(initial_seed+ip),
		    .adaptive_rate(adaptive_rate),
		    .packet_count_width(packet_count_width),
		    .num_flit_buffers(num_flit_buffers),
		    .num_header_buffers(num_header_buffers),
		    .num_vcs(num_vcs),
		    .max_packet_length(packet_length),
		    .data_width(data_width),
		    .addr_width(addr_width),
		    .address(router_address+
			     ip-(num_ports-num_nodes_per_router)),
		    .walk_addresses(walk_addresses),
		    .reset_type(reset_type))
		ps
		  (.clk(clk),
		   .reset(reset),
		   .flit_valid(flit_valid),
		   .flit_head(flit_head),
		   .flit_tail(flit_tail),
		   .flit_vc(flit_vc),
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
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_vcs(num_vcs),
       .num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .router_address(router_address),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .data_width(data_width),
       .perf_ctr_enable(perf_ctr_enable),
       .perf_ctr_width(perf_ctr_width),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .error_recovery(error_recovery),
       .routing_function_type(routing_function_type),
       .credit_handling_type(credit_handling_type),
       .sw_spec_cred_check(sw_spec_cred_check),
       .vc_allocator_type(vc_allocator_type),
       .vc_arbiter_type(vc_arbiter_type),
       .sw_allocator_type(sw_allocator_type),
       .sw_arbiter_type(sw_arbiter_type),
       .sw_spec_level(sw_spec_level),
       .crossbar_type(crossbar_type),
       .reset_type(reset_type))
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
   
   wire [0:31] in_creds_s, in_creds_q;
   assign in_creds_s = in_creds_q + pop_count(cred_valid_out_ip);
   dff
     #(.width(32),
       .reset_type(reset_type))
   in_credsq
     (.clk(clk),
      .reset(reset),
      .d(in_creds_s),
      .q(in_creds_q));
   
   wire [0:31] in_creds;
   assign in_creds = in_creds_q;
   
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
   
   wire [0:31] out_creds_s, out_creds_q;
   assign out_creds_s = out_creds_q + pop_count(cred_valid_in_op);
   dff
     #(.width(32),
       .reset_type(reset_type))
   out_credsq
     (.clk(clk),
      .reset(reset),
      .d(out_creds_s),
      .q(out_creds_q));
   
   wire [0:31] out_creds;
   assign out_creds = out_creds_q;
   
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
      
      while(!(&done_ip) || (in_flits > out_flits) || (in_flits > in_creds))
	begin
	   cycles = cycles + 1;
	   #(Tclk);
	end

      #(Tclk*10);
      
      $display("%d flits sent in %d cycles", out_flits, cycles);
      
      $finish;
      
   end
   
endmodule
