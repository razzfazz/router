module testbench
  #(parameter Tclk = 2,
    parameter sim_cycles = 1000,
    parameter warmup_cycles = 100,
    parameter initial_seed = 0,
    parameter output_as_csv = 1,
    parameter buffer_occupancy = 25,
    parameter num_ports = 5,
    parameter num_vcs = 2,
    parameter reset_type = 1)
   ();
   
    /* supported architectures:
     0: separable, input-first, round-robin arbiters
     1: separable, input-first, matrix arbiters
     2: separable, output-first, round-robin arbiters
     3: separable, output-first, matrix arbiters
     4: rotate inputs based on prio, round-robin arbiters in final stage
     5: rotate inputs based on prio, matrix arbiters in final stage
     6: replicate logic for prios, round-robin arbiters in final stage
     7: replicate logic for prios, matrix arbiters in final stage
     8: diagonal propagation arbiter, round-robin arbiters in final stage
     9: diagonal propagation arbiter, matrix arbiters in final stage */
   localparam num_archs = 10;
   
   function integer get_flow(input [0:num_ports*num_ports-1] gnt_matrix);
      integer i, j;
      begin
	 get_flow = 0;
	 for(i = 0; i < num_ports; i = i + 1)
	   begin
	      for(j = 0; j < num_ports; j = j + 1)
		begin
		   if(gnt_matrix[i*num_ports+j])
		     get_flow = get_flow + 1;
		end
	   end
      end
   endfunction
   
/*   function integer max_flow(input [0:num_ports*num_ports-1] req_matrix);
      integer i, j, k, l;
      integer i_k, j_k, j_l;
      integer sum;
      begin
	 
	 // can have at most 1 grant per port, so we start out with that
	 max_flow = num_ports;
	 
	 // traverse all possible cut sets
	 for(i = 0; i < 2 ** num_ports; i = i + 1)
	   begin
	      sum = 0;
	      for(j = 0; j < 2 ** num_ports; j = j + 1)
		begin
		   for(k = 0; k < num_ports; k = k + 1)
		     begin
			
			i_k = (i >> k) & 1;
			j_k = (j >> k) & 1;
			j_l = (j >> l) & 1;
			
			// add 1 for each input node in right part of cut set
			if(!i_k)
			  sum = sum + 1;
			
			// add 1 for each output node in left part of cut set
			if(j_k)
			  sum = sum + 1;
			
			for(l = 0; l < num_ports; l = l + 1)
			  begin
			     
			     // add 1 for each request where the input port is
			     // in the left part of the cutset and the output
			     // port is in its right part
			     if(i_k && !j_l)
			       sum = sum + req_matrix[k*num_ports+l];
			     
			  end
		     end
		   if (sum < max_flow)
		     max_flow = sum;
		end
	   end
      end
   endfunction
*/

   function [0:num_ports*num_ports-1] augment_alloc
     (input [0:num_ports*num_ports-1] requests,
      input [0:num_ports*num_ports-1] grants);
      reg [0:num_ports*num_ports-1] results;
      integer 			    i, j;
/*      integer 			    k;*/
      reg 			    done;
      reg 			    assigned;
      begin
/*	 $display("SIM: >>>augment_alloc");
	 $display("SIM: Requests:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("SIM: %b", requests[i*num_ports +: num_ports]);
	 $display("SIM: Grants:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("SIM: %b", grants[i*num_ports +: num_ports]);*/
	 done = 1'b0;
	 requests = requests & ~grants;
	 while(!done)
	   begin
/*	      $display("SIM: begin while loop");*/
	      done = 1'b1;
	      for(i = 0; i < num_ports; i = i + 1)
		begin
/*		   $display("SIM: begin for loop (i=%d)", i);*/
		   assigned = 1'b0;
		   for(j = 0; j < num_ports; j = j + 1)
		     begin
			if(grants[j*num_ports+i])
			  begin
			     assigned = 1'b1;
			  end
		     end
		   if(!assigned)
		     begin
/*			$display("SIM: checking port %d", i);*/
			results = find_aug_path(i, {num_ports{1'b0}}, requests, grants);
			if(|results)
			  begin
			     requests = requests ^ results;
			     grants = grants ^ results;
			     done = 1'b0;
			     i = num_ports;
/*			     $display("SIM: found path; restarting");
			     $display("SIM: New request matrix:");
			     for(k = 0; k < num_ports; k = k + 1)
			       $display("SIM: %b", requests[k*num_ports +: num_ports]);
			     $display("SIM: New grant matrix:");
			     for(k = 0; k < num_ports; k = k + 1)
			       $display("SIM: %b", grants[k*num_ports +: num_ports]);*/
			  end
		     end
/*		   $display("SIM: end for loop");*/
		end
/*	      $display("SIM: end while loop");*/
	   end
	 augment_alloc = grants;
/*	 $display("SIM: Augmented:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("SIM: %b", augment_alloc[i*num_ports +: num_ports]);
	 $display("SIM: <<<augment_alloc");*/
      end
   endfunction
   
   function automatic [0:num_ports*num_ports-1] find_aug_path
     (input integer port_select,
      input [0:num_ports-1] ports_ignore,
      input [0:num_ports*num_ports-1] requests,
      input [0:num_ports*num_ports-1] grants);
      reg [0:num_ports*num_ports-1] results;
      reg 			    done;
      integer 			    i, j;
      begin
/*	 $display("SIM: >>>find_aug_path");
	 $display("SIM: port_select=%d, ports_ignore=%b", port_select, ports_ignore);
	 $display("SIM: Requests:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("SIM: %b", requests[i*num_ports +: num_ports]);
	 $display("SIM: Grants:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("SIM: %b", grants[i*num_ports +: num_ports]);*/
	 find_aug_path = {num_ports*num_ports{1'b0}};
	 done = 1'b0;
	 for(i = 0; (i < num_ports) && !done; i = i + 1)
	   begin

/*	      $display("SIM: checking input port %d", i);*/
	      
	      // check if there is an unsatisfied request from this input port
	      if(requests[i*num_ports+port_select] && !ports_ignore[i])
		begin

		   find_aug_path[i*num_ports+port_select] = 1'b1;

		   if(!(|grants[i*num_ports +: num_ports]))
		     begin

/*			$display("SIM: input port %d has not been granted to anybody so far; terminating", i);*/
			
			// if input port has not yet been granted, we have found
			// an augmenting path, and leave the loop (we know there
			// was a request from this input port to our initial
			// output port, i.e., the lack of grant is not simply
			// due to no request having been made by this input)
			done = 1'b1;
			     
		     end
			
		   // has this input port been granted to someone else?
		   // (can't be the current output, otherwise we wouldn't have
		   // an unsatisfied request)
		   for(j = 0; (j < num_ports) && !done; j = j + 1)
		     begin
			if(grants[i*num_ports+j])
			  begin

/*			     $display("SIM: input port %d was previously granted to output port %d; recursing", i, j);*/
			     
			     // try if removing that grant helps using recursion
			     find_aug_path[i*num_ports+j] = 1'b1;
			     results = find_aug_path(j, ports_ignore | ({1'b1, {num_ports-1{1'b0}}} >> i),
						     requests ^ find_aug_path,
						     grants ^ find_aug_path);
			     if(|results)
			       begin
				  
				  // we found an augmenting path, so look no
				  // further
				  find_aug_path
				    = find_aug_path | results;
				  done = 1'b1;
				  
			       end
			     else
			       begin

				  // this path didn't work out, so remove from
				  // results
				  find_aug_path[i*num_ports+j] = 1'b0;
			     
			       end
			  end
		     end
		   
		   if(!done)
		     begin

			// none of the paths through this input port worked out,
			// so remove from results
			find_aug_path[i*num_ports+port_select] = 1'b0;
			
		     end
		end
	   end
/*	 $display("SIM: Result:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("SIM: %b", find_aug_path[i*num_ports +: num_ports]);
	 $display("SIM: <<<find_aug_path");*/
      end
   endfunction
   
   function integer zero_or_one_hot(input [0:num_ports-1] vector);
      integer i;
      reg [0:num_ports-1] vec_sub1;
      reg [0:num_ports-1] vec_rev;
      reg [0:num_ports-1] vec_rev_sub1;
      reg [0:num_ports-1] vec_sub1rev;
      begin
	 for(i = 0; i < num_ports; i = i + 1)
	   begin
	      vec_rev[i] = vector[num_ports - i - 1];
	   end
	 vec_sub1 = vector - {{num_ports-1{1'b0}}, 1'b1};
	 vec_rev_sub1 = vec_rev - {{num_ports-1{1'b0}}, 1'b1};
	 for(i = 0; i < num_ports; i = i + 1)
	   begin
	      vec_sub1rev[i] = vec_rev_sub1[num_ports - i - 1];
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

   reg [0:num_ports*num_ports-1]         req_ip_op;
   reg [0:num_ports*num_ports-1] 	 max_ip_op;
   reg [0:num_ports*num_vcs-1]           req_ip_ivc;
   reg [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   reg [0:num_ports*num_vcs*num_vcs-1] 	 req_ip_ivc_ovc;

   integer 				 seed = initial_seed;
   
   integer 				  ip, ivc;

   integer 				  grant_ideal;
   integer 				  flow_ideal;

   always @(posedge clk)
     if(reset)
       begin
	  req_ip_op = {num_ports*num_ports{1'b0}};
	  max_ip_op = {num_ports*num_ports{1'b0}};
	  req_ip_ivc_op = {num_ports*num_vcs*num_ports{1'b0}};
	  req_ip_ivc_ovc = {num_ports*num_vcs*num_vcs{1'b0}};
	  flow_ideal = 0;
	  grant_ideal = 0;
       end
     else
       begin
	  for(ip = 0; ip < num_ports; ip = ip + 1)
	    begin
	       
	       req_ip_op[ip*num_ports +: num_ports] = {num_ports{1'b0}};
	       
	       for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
		 begin
		    
		    req_ip_ivc[ip*num_vcs+ivc]
		      = ($dist_uniform(seed, 0, 99) < buffer_occupancy);
		    req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports +: num_ports]
		      = {num_ports{1'b0}};
		    req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports+
				  $dist_uniform(seed, 0, num_ports-1)]
		      = req_ip_ivc[ip*num_vcs+ivc];
		    req_ip_op[ip*num_ports +: num_ports]
		      = req_ip_op[ip*num_ports +: num_ports] |
			req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports +: num_ports];
		    req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs +: num_vcs]
		      = {num_vcs{1'b0}};
		    req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs+
				   $dist_uniform(seed, 0, num_vcs-1)]
		      = req_ip_ivc[ip*num_vcs+ivc];
		    
		 end
	       
	    end

	  max_ip_op = augment_alloc(req_ip_op, {num_ports*num_ports{1'b0}});
	  flow_ideal = get_flow(max_ip_op);
	  grant_ideal = grant_ideal + flow_ideal;
		     
       end

   integer grant_actual[0:num_archs-1];
   
   // assume infinite buffers for now
   wire [0:num_ports*num_vcs-1]      cred_op_ovc;
   assign cred_op_ovc = {num_ports*num_vcs{1'b1}};
   
   generate
      
      genvar 			     arch;
      for(arch = 0; arch < num_archs; arch = arch + 1)
	begin:archs
	   
	   wire [0:num_ports*num_vcs-1]   gnt_ip_ivc;
	   wire [0:num_ports*num_ports-1] gnt_ip_op;
	   
	   sw_alloc
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .reset_type(reset_type),
	       .architecture(arch))
	   alloc
	     (.clk(clk),
	      .reset(reset),
	      .req_ip_ivc_op(req_ip_ivc_op),
	      .req_ip_ivc_ovc(req_ip_ivc_ovc),
	      .cred_op_ovc(cred_op_ovc),
	      .gnt_ip_ivc(gnt_ip_ivc),
	      .gnt_ip_op(gnt_ip_op));

	   wire [0:num_ports*num_ports-1] gnt_op_ip;
	   interleaver
	     #(.width(num_ports*num_ports),
	       .num_blocks(num_ports))
	   gnt_intl
	     (.data_in(gnt_ip_op),
	      .data_out(gnt_op_ip));
	   
	   integer 			  flow_actual;
	   integer 			  l;
	   integer 			  bad_alloc;
	   
	   initial
	   begin

	      grant_actual[arch] = 0;
	      
	      #(2*Tclk);
	      
	      #(warmup_cycles*Tclk);
	      
	      forever
		begin
		   for(l = 0; l < num_ports; l = l + 1)
		     begin
			bad_alloc = 0;
			if(!zero_or_one_hot(gnt_ip_op[l*num_ports+:num_ports]))
			  bad_alloc = bad_alloc | 1;
			if(!zero_or_one_hot(gnt_op_ip[l*num_ports+:num_ports]))
			  bad_alloc = bad_alloc | 2;
		     end
		   if(|(gnt_ip_op & ~req_ip_op))
		     bad_alloc = bad_alloc | 4;
		   flow_actual = get_flow(gnt_ip_op);
		   grant_actual[arch] = grant_actual[arch] + flow_actual;
		   if(flow_actual > flow_ideal)
		     bad_alloc = bad_alloc | 8;
		   if(bad_alloc != 0)
		     begin
			$display("SIM: ERROR: Assertion failed for arch=%d!",
				 arch);
			$display("SIM: Allocation error code %d > 0",
				 bad_alloc);
			$display("SIM: Requests:");
			for(l = 0; l < num_ports; l = l + 1)
			  $display("SIM: %b", req_ip_op[l*num_ports +: num_ports]);
			$display("SIM: Grants:");
			for(l = 0; l < num_ports; l = l + 1)
			  $display("SIM: %b", gnt_ip_op[l*num_ports +: num_ports]);
			$display("SIM: Augmented:");
			for(l = 0; l < num_ports; l = l + 1)
			  $display("SIM: %b", max_ip_op[l*num_ports +: num_ports]);
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
	   $display("SIM: num_ports,num_vcs,occupancy,architecture,flow,match_prob");
	   $display("SIM: %0d,%0d,%0d,%0d,%0d,%0d", num_ports, num_vcs,
		    buffer_occupancy, -1, grant_ideal, 100);
	   for(k = 0; k < num_archs; k = k + 1)
	     $display("SIM: %0d,%0d,%0d,%0d,%0d,%0d",
		      num_ports, num_vcs, buffer_occupancy, k, grant_actual[k],
		      100 * grant_actual[k] / grant_ideal);
	end
      else
	begin
	   $display("SIM: simulation completed");
      
	   $display("SIM: flow analysis:");
	   $display("SIM: arch=       augm, flow=%d", grant_ideal);
	   for(k = 0; k < num_archs; k = k + 1)
	     $display("SIM: arch=%d, flow=%d (%d%%)",
		      k, grant_actual[k], 100 * grant_actual[k] / grant_ideal);
	end
      
      $finish;
      
   end
   
endmodule
