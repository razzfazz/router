module testbench
  ();
   
   parameter Tclk = 2;
   parameter sim_cycles = 10000;
   parameter warmup_cycles = 100;
   parameter initial_seed = 0;
   parameter output_as_csv = 1;
   parameter buffer_occupancy = 75;
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "sim_functions.v"
   
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, round-robin arbiters
    3: separable, output-first, matrix arbiters */
   localparam num_archs = 4;
   
   function integer get_flow(input [0:num_ports*num_vcs-1] gnt_matrix);
      integer i;
      begin
	 get_flow = 0;
	 for(i = 0; i < num_ports*num_vcs; i = i + 1)
	   get_flow = get_flow + gnt_matrix[i];
      end
   endfunction
   
   function integer zero_or_one_hot(input [0:num_ports*num_vcs-1] vector);
      integer i;
      reg [0:num_ports*num_vcs-1] vec_sub1;
      reg [0:num_ports*num_vcs-1] vec_rev;
      reg [0:num_ports*num_vcs-1] vec_rev_sub1;
      reg [0:num_ports*num_vcs-1] vec_sub1rev;
      begin
	 for(i = 0; i < num_ports*num_vcs; i = i + 1)
	   begin
	      vec_rev[i] = vector[num_ports*num_vcs - i - 1];
	   end
	 vec_sub1 = vector - {{num_ports*num_vcs-1{1'b0}}, 1'b1};
	 vec_rev_sub1 = vec_rev - {{num_ports*num_vcs-1{1'b0}}, 1'b1};
	 for(i = 0; i < num_ports*num_vcs; i = i + 1)
	   begin
	      vec_sub1rev[i] = vec_rev_sub1[num_ports*num_vcs - i - 1];
	   end
	 zero_or_one_hot = &(vector ^ (vec_sub1 | vec_sub1rev));
      end
   endfunction
   
   reg 		    reset;
   reg 		    clk;
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   reg [0:num_ports*num_vcs-1] req_ip_ivc;
   reg [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   reg [0:num_ports*num_vcs*num_vcs-1] 	 req_ip_ivc_ovc;
   
   integer 				 seed = initial_seed;
   
   integer 				 ip, ivc;

   reg [0:vc_idx_width-1] 		 vc_idx;
   
   always @(posedge clk)
     if(reset)
       begin
	  req_ip_ivc = {num_ports*num_vcs{1'b0}};
	  req_ip_ivc_op = {num_ports*num_vcs*num_ports{1'b0}};
	  req_ip_ivc_ovc = {num_ports*num_vcs*num_vcs{1'b0}};
       end
     else
       begin
	  for(ip = 0; ip < num_ports; ip = ip + 1)
	    begin
	       for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		 begin
		    req_ip_ivc[ip*num_vcs+ivc]
		      = ($dist_uniform(seed, 0, 99) < buffer_occupancy);
		    req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports +: num_ports]
		      = {num_ports{1'b0}};
		    req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports+
				  (ip + $dist_uniform(seed, 1, num_ports-1)) %
				  num_ports]
		      = req_ip_ivc[ip*num_vcs+ivc];
		    req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs +: num_vcs]
		      = {num_vcs{1'b0}};
		    vc_idx = {vc_idx_width{1'b0}};
		    vc_idx = set_traffic_class(vc_idx, get_traffic_class(ivc));
		    vc_idx = set_routing_class(vc_idx,
					       $dist_uniform(seed,
							     routing_class_minimal,
							     routing_class_non_minimal));
		    vc_idx = vc_idx + $dist_uniform(seed, 0, num_vcs_per_class-1);
		    req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs+vc_idx]
		      = req_ip_ivc[ip*num_vcs+ivc];
		 end
	    end
       end
   
   integer grant_actual[0:num_archs-1];
   
   generate
      
      genvar 			arch;
      for(arch = 0; arch < num_archs; arch = arch + 1)
	begin:archs
	   
	   wire [0:num_ports*num_vcs-1]   gnt_ip_ivc;
	   wire [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
	   wire [0:num_ports*num_vcs-1] 	gnt_op_ovc;
	   
	   vc_alloc
	     #(.reset_type(reset_type),
	       .architecture(arch))
	   alloc
	     (.clk(clk),
	      .reset(reset),
	      .vc_req_ip_ivc_op(req_ip_ivc_op),
	      .vc_req_ip_ivc_ovc(req_ip_ivc_ovc),
	      .vc_gnt_ip_ivc(gnt_ip_ivc),
	      .vc_gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
	      .vc_gnt_op_ovc(gnt_op_ovc));

	   integer 			  l, m;
	   integer 			  bad_alloc;
	   integer 			  grant_port[0:num_ports*num_vcs-1];
	   
	   initial
	   begin
	      
	      grant_actual[arch] = 0;

	      for(l = 0; l < num_ports*num_vcs; l = l + 1)
		grant_port[l] = 0;
	      
	      #(2*Tclk);
	      
	      #(warmup_cycles*Tclk);
	      
	      forever
		begin
		   for(l = 0; l < num_ports; l = l + 1)
		     begin
			bad_alloc = 0;
			for(m = 0; m < num_vcs; m = m + 1)
			  begin
			     if(!zero_or_one_hot(gnt_ip_ivc_ovc[(l*num_vcs+m)*num_vcs +: num_vcs]))
			       bad_alloc = bad_alloc | 1;
			     if(|gnt_ip_ivc[l*num_ports+m +: num_ports])
			       grant_port[l*num_ports+m] = grant_port[l*num_ports+m] + 1;
			  end
		     end
		   if(|(gnt_ip_ivc_ovc & ~req_ip_ivc_ovc))
		     bad_alloc = bad_alloc | 4;
		   grant_actual[arch] = grant_actual[arch] + get_flow(gnt_ip_ivc);
		   if(is_x(gnt_ip_ivc) || is_x(gnt_ip_ivc_ovc) || is_x(gnt_op_ovc))
		     bad_alloc = bad_alloc | 8;
		   if(bad_alloc != 0)
		     begin
			$display("SIM: ERROR: Assertion failed for arch=%d!",
				 arch);
			$display("SIM: Allocation error code %d > 0",
				 bad_alloc);
			$display("SIM: Requests:");
			for(l = 0; l < num_ports*num_vcs; l = l + 1)
			  $display("SIM: %b", req_ip_ivc_ovc[l*num_vcs +: num_vcs]);
			$display("SIM: Grants:");
			for(l = 0; l < num_ports*num_vcs; l = l + 1)
			  $display("SIM: %b", gnt_ip_ivc_ovc[l*num_vcs +: num_vcs]);
		     end
		   #(Tclk);
		end
	   end
	   
	end
      
   endgenerate
   
   integer 			 k;
   
   initial
   begin
      
      if(!output_as_csv) $display("SIM: starting reset sequence");
      
      reset = 1'b1;
      
      #(2*Tclk);
      
      reset = 1'b0;
      
      if(!output_as_csv)
	begin
	   $display("SIM: reset sequence completed");
	   $display("SIM: starting warmup phase");
	end
      
      #(warmup_cycles*Tclk);
      
      if(!output_as_csv)
	begin
	   $display("SIM: warmup phase completed");
	   $display("SIM: starting simulation");
	end
      
      #(sim_cycles*Tclk);
      
      if(output_as_csv)
	begin
	   $display("SIM: num_ports,num_vcs,occupancy,architecture,flow");
	   for(k = 0; k < num_archs; k = k + 1)
	     $display("SIM: %0d,%0d,%0d,%0d,%0d",
		      num_ports, num_vcs, buffer_occupancy, k, grant_actual[k]);
	end
      else
	begin
	   $display("SIM: simulation completed");
	   
	   $display("SIM: flow analysis:");
	   for(k = 0; k < num_archs; k = k + 1)
	     $display("SIM: arch=%d, flow=%d", k, grant_actual[k]);
	end
      
      $finish;
      
   end
   
endmodule
