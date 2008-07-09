module testbench
  #(parameter Tclk = TCLK,
    parameter num_ports = NUM_PORTS,
    parameter hold_type = HOLD_TYPE,
    parameter reset_type = RESET_TYPE,
    parameter mean_delay = MEAN_DELAY,
    parameter fixed_delay = FIXED_DELAY,
    parameter hold_requests = HOLD_REQUESTS,
    parameter runtime = RUNTIME,
    parameter output_as_csv = OUTPUT_AS_CSV,

    /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: wavefront, rotate inputs for priority
    3: wavefront, replicated logic for priority
    4: diagonal propagation arbiter (DPA) */
    parameter architecture = ARCHITECTURE)
   ();
   
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
   
   function integer one_hot(input [0:num_ports-1] vector);
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
	 one_hot = &(vector ^ vec_sub1 ^ vec_sub1rev);
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
/*	 $display(">>>augment_alloc");
	 $display("Requests:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("%b", requests[i*num_ports +: num_ports]);
	 $display("Grants:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("%b", grants[i*num_ports +: num_ports]);*/
	 done = 1'b0;
	 requests = requests & ~grants;
	 while(!done)
	   begin
/*	      $display("begin while loop");*/
	      done = 1'b1;
	      for(i = 0; i < num_ports; i = i + 1)
		begin
/*		   $display("begin for loop (i=%d)", i);*/
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
/*			$display("checking port %d", i);*/
			results = find_aug_path(i, {num_ports{1'b0}}, requests, grants);
			if(|results)
			  begin
			     requests = requests ^ results;
			     grants = grants ^ results;
			     done = 1'b0;
			     i = num_ports;
/*			     $display("found path; restarting");
			     $display("New request matrix:");
			     for(k = 0; k < num_ports; k = k + 1)
			       $display("%b", requests[k*num_ports +: num_ports]);
			     $display("New grant matrix:");
			     for(k = 0; k < num_ports; k = k + 1)
			       $display("%b", grants[k*num_ports +: num_ports]);*/
			  end
		     end
/*		   $display("end for loop");*/
		end
/*	      $display("end while loop");*/
	   end
	 augment_alloc = grants;
/*	 $display("Augmented:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("%b", augment_alloc[i*num_ports +: num_ports]);
	 $display("<<<augment_alloc");*/
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
/*	 $display(">>>find_aug_path");
	 $display("port_select=%d, ports_ignore=%b", port_select, ports_ignore);
	 $display("Requests:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("%b", requests[i*num_ports +: num_ports]);
	 $display("Grants:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("%b", grants[i*num_ports +: num_ports]);*/
	 find_aug_path = {num_ports*num_ports{1'b0}};
	 done = 1'b0;
	 for(i = 0; (i < num_ports) && !done; i = i + 1)
	   begin

/*	      $display("checking input port %d", i);*/
	      
	      // check if there is an unsatisfied request from this input port
	      if(requests[i*num_ports+port_select] && !ports_ignore[i])
		begin

		   find_aug_path[i*num_ports+port_select] = 1'b1;

		   if(!(|grants[i*num_ports +: num_ports]))
		     begin

/*			$display("input port %d has not been granted to anybody so far; terminating", i);*/
			
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

/*			     $display("input port %d was previously granted to output port %d; recursing", i, j);*/
			     
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
/*	 $display("Result:");
	 for(i = 0; i < num_ports; i = i + 1)
	   $display("%b", find_aug_path[i*num_ports +: num_ports]);
	 $display("<<<find_aug_path");*/
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

   wire [0:num_ports*num_ports-1] req_ip_op;
   wire [0:num_ports*num_ports-1] gnt_ip_op;

   wire [0:num_ports*32-1] 	  error_count_s;
   reg [0:num_ports*32-1] 	  error_count_q;
   
   wire [0:num_ports*32-1]	  avg_latency;
   wire [0:num_ports*32-1] 	  avg_rate;
   wire [0:num_ports*32-1] 	  avg_match;
  
   genvar 			  i;

   
   generate
      for(i = 0; i < num_ports; i = i + 1)
	begin:drvs
	   
	   wire [0:num_ports-1] req_op;
	   wire [0:num_ports-1] gnt_op;
	   wire [0:31] 		drv_avg_latency;
	   wire [0:31] 		drv_avg_rate;
	   wire [0:31] 		drv_avg_match;
	   wire 		drv_error_bad_alloc;
	   wire [0:31] 		drv_error_count_s;
	   wire [0:31] 		drv_error_count_q;

	   assign gnt_op = gnt_ip_op[i*num_ports:(i+1)*num_ports-1];
	   
	   driver
	     #(.mean_delay(mean_delay),
	       .fixed_delay(fixed_delay),
	       .hold_requests(hold_requests),
	       .initial_seed(i),
	       .num_ports(num_ports))
	   drv
	     (.clk(clk),
	      .reset(reset),
	      .req(req_op),
	      .gnt(gnt_op),
	      .avg_latency(drv_avg_latency),
	      .avg_match(drv_avg_match),
	      .avg_rate(drv_avg_rate));

	   assign avg_latency[i*32:(i+1)*32-1] = drv_avg_latency;
	   assign avg_rate[i*32:(i+1)*32-1] = drv_avg_rate;
	   assign avg_match[i*32:(i+1)*32-1] = drv_avg_match;
	   assign req_ip_op[i*num_ports:(i+1)*num_ports-1] = req_op;
	   
	   assign drv_error_bad_alloc = |(gnt_op & ~req_op) ||
					!zero_or_one_hot(gnt_op);

	   assign drv_error_count_q = error_count_q[i*32:(i+1)*32-1];
	   assign drv_error_count_s = reset ?
				      {num_ports{1'b0}} :
				      (drv_error_count_q + drv_error_bad_alloc);
	   assign error_count_s[i*32:(i+1)*32-1] = drv_error_count_s;
	   
	end
   endgenerate
   

   simple_alloc
     #(.num_ports(num_ports),
       .reset_type(reset_type),
       .hold_type(hold_type),
       .architecture(architecture))
   alloc
     (.CLK(clk),
      .RST(reset),
      .req_ip_op(req_ip_op),
      .gnt_ip_op(gnt_ip_op));

   reg [0:num_ports*num_ports-1] max_ip_op;
   
   always@(posedge clk)
     begin
	error_count_q <= error_count_s;
     end

   
   integer k, l, m;

   integer mean_latency = 0;
   integer mean_rate = 0;
   integer mean_match = 0;

   integer grant_actual = 0;
   integer grant_ideal = 0;

   integer flow_ideal = 0;
   integer flow_actual = 0;
	   
   initial
   begin
      
      reset = 1'b1;
      
      #(2*Tclk)
      
      reset = 1'b0;

      for(k = 0; k < runtime; k = k + 1)
	begin
	   #(Tclk);
	   max_ip_op = augment_alloc(req_ip_op, gnt_ip_op);
	   flow_ideal = get_flow(max_ip_op);
	   flow_actual = get_flow(gnt_ip_op);
	   grant_ideal = grant_ideal + flow_ideal;
	   grant_actual = grant_actual + flow_actual;
	   if(|(max_ip_op & ~req_ip_op) || (flow_actual > flow_ideal))
	     begin
		$display("ERROR: Assertion failed!");
		$display("Requests:");
		for(l = 0; l < num_ports; l = l + 1)
		  $display("%b", req_ip_op[l*num_ports +: num_ports]);
		$display("Grants:");
		for(l = 0; l < num_ports; l = l + 1)
		  $display("%b", gnt_ip_op[l*num_ports +: num_ports]);
		$display("Augmented:");
		for(l = 0; l < num_ports; l = l + 1)
		  $display("%b", max_ip_op[l*num_ports +: num_ports]);
		$display("");
	      end
	end

      $display("flow analysis: actual=%d, ideal=%d (%d%%)",
	       grant_actual, grant_ideal, 100 * grant_actual / grant_ideal);
      $display("");
      
      if(output_as_csv)
	begin
	   $display("driver,latency,rate,match,errors");
	   for(k = 0; k < num_ports; k = k + 1)
	     begin
		$display("%0d,%0f,%0f,%0f,%0d",
			 k,
			 avg_latency[k*32 +: 32] * 0.0001,
			 avg_rate[k*32 +: 32] * 0.0001,
			 avg_match[k*32 +: 32] * 0.0001,
			 error_count_q[k*32 +: 32]);
		mean_latency = mean_latency + avg_latency[k*32 +: 32];
		mean_rate = mean_rate + avg_rate[k*32 +: 32];
		mean_match = mean_match + avg_match[k*32 +: 32];
	     end
	   $display("mean,%0f,%0f,%0f",
		    mean_latency * 0.0001 / num_ports,
		    mean_rate * 0.0001 / num_ports,
		    mean_match * 0.0001 / num_ports);
	end
      else
	begin
	   $display(" driver | latency  |   rate   |   match  |  errors  ");
	   $display("----------------------------------------------------");
	   for(k = 0; k < num_ports; k = k + 1)
	     begin
		$display(" %6d | %8.3f | %8.3f | %8.3f | %8d ",
			 k,
			 avg_latency[k*32 +: 32] * 0.0001,
			 avg_rate[k*32 +: 32] * 0.0001,
			 avg_match[k*32 +: 32] * 0.0001,
			 error_count_q[k*32 +: 32]);
		mean_latency = mean_latency + avg_latency[k*32 +: 32];
		mean_rate = mean_rate + avg_rate[k*32 +: 32];
		mean_match = mean_match + avg_match[k*32 +: 32];
	     end
	   $display("  mean  | %8.3f | %8.3f | %8.3f |",
		    mean_latency * 0.0001 / num_ports,
		    mean_rate * 0.0001 / num_ports,
		    mean_match * 0.0001 / num_ports);
	   $display("----------------------------------------------------");
	end

      $finish;
      
   end
   
endmodule
