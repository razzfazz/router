module testbench
  #(parameter Tclk = 6,
    parameter num_ports = 20,
    parameter use_clock_gating = 1,
    parameter use_allocator_type = 2, // 0 = separable, 1 = wavefront, 2 = grant all
    parameter use_arbiter_type = 0, // 0 = RR, 1 = matrix
    parameter mean_delay = 8,
    parameter fixed_delay = 0,
    parameter hold_requests = 1,
    parameter runtime = 100000,
    parameter output_as_csv = 1)
   ();
   
   function integer pop_count(input [0:num_ports-1] x);
      integer i;
      begin
	 pop_count = 0;
	 for(i = 0; i < num_ports; i = i + 1)
	   begin
              pop_count = pop_count + x[i];
	   end
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

   // [sort order: input port,output port]
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
	   
	   assign drv_error_bad_alloc = |(gnt_op & ~req_op);

	   assign drv_error_count_q = error_count_q[i*32:(i+1)*32-1];
	   assign drv_error_count_s = reset ?
				      {num_ports{1'b0}} :
				      (drv_error_count_q + drv_error_bad_alloc);
	   assign error_count_s[i*32:(i+1)*32-1] = drv_error_count_s;
	   
	end
   endgenerate
   

   allocator
     #(.num_ports(num_ports),
       .use_clock_gating(use_clock_gating),
       .use_allocator_type(use_allocator_type),
       .use_arbiter_type(use_arbiter_type))
   alloc
     (.CLK(clk),
      .RST(reset),
      .req(req_ip_op),
      .gnt(gnt_ip_op));

   
   always@(posedge clk)
     begin
	error_count_q <= error_count_s;
     end

   
   integer k;

   integer mean_latency = 0;
   integer mean_rate = 0;
   integer mean_match = 0;
   
	   
   initial
   begin
      
      reset = 0'b1;
      
      #(2*Tclk)
      
      reset = 0'b0;
      
      #(runtime*Tclk);

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
