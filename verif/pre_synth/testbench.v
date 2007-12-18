module testbench
  #(parameter Tclk = 6,
    parameter num_ports = 5,
    parameter use_clock_gating = 0,
    parameter use_allocator_type = 1, // 0 = separable, 1 = wavefront, 2 = grant all
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter mean_delay = 1,
    parameter fixed_delay = 1,
    parameter hold_requests = 0,
    parameter runtime = 100000)
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
   
   
   generate
   
      if(use_allocator_type == 0)
	begin

	   // [sort order: input port,output port]
	   wire [0:num_ports*num_ports-1] req1_ip_op;
	   wire [0:num_ports*num_ports-1] gnt1_ip_op;   
	   wire [0:num_ports*num_ports-1] gnt2_ip_op;   

	   assign req1_ip_op = req_ip_op;

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
		    .use_arbiter_type(use_arbiter_type),
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
		    .use_arbiter_type(use_arbiter_type),
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

	   assign gnt_ip_op = gnt2_ip_op;
	   
	end
      else if(use_allocator_type == 1)
	begin

	   assign update = |req_ip_op;
	     
	   wf_alloc
	     #(.num_ports(num_ports),
	       .use_clock_gating(use_clock_gating))
	   alloc
	     (.clk(clk),
	      .reset(reset),
	      .update(update),
	      .req(req_ip_op),
	      .gnt(gnt_ip_op));
	   
	end // if (use_allocator_type == 1)
      else if(use_allocator_type == 2)
	begin
	   assign gnt_ip_op = req_ip_op;
	end
      
   endgenerate


   always@(posedge clk)
     begin
	error_count_q <= error_count_s;
     end

   
   integer k;
	   
   initial
   begin
      
      reset = 0'b1;
      
      #(2*Tclk)
      
      reset = 0'b0;
      
      #(runtime*Tclk);

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
	end
      $display("----------------------------------------------------");
      
      $finish;
      
   end
   
endmodule
