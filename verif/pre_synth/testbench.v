module testbench
  #(
    parameter Tclk = 6,
    parameter width = 4,
    parameter mean_delay = 2,
    parameter runtime = 100000)
   ();
   
   function integer pop_count(input [0:width-1] x);
      integer i;
      begin
	 pop_count = 0;
	 for(i = 0; i < width; i = i + 1)
	   begin
              pop_count = pop_count + x[i];
	   end
      end
   endfunction
   
   reg 		    reset;
   reg 		    clk;
   wire 	    update = 1'b1;
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end

   wire [0:width*width-1] req;
   wire [0:width*width-1] gnt;

   wire [0:width*width-1] gnt_for_port;
   wire [0:width-1] 	  any_gnt;
   wire [0:width*32-1] 	  error_count_s;
   reg [0:width*32-1] 	  error_count_q;
   
   wire [0:width*32-1]	  avg_latency;
   wire [0:width*32-1] 	  avg_rate;
   
   wf_alloc #(.num_ports(4)) wfa(.clk(clk),
				 .reset(reset),
				 .update(update),
				 .req(req),
				 .gnt(gnt));

   genvar 		  i, j;
   
   generate
      for(i = 0; i < width; i = i + 1)
	begin:drvs
	   wire [0:width-1] drv_req;
	   wire [0:width-1] drv_gnt = gnt[i*width:(i+1)*width-1];
	   wire [0:31] 	    drv_avg_latency;
	   wire [0:31] 	    drv_avg_rate;
	   wire             drv_error_no_alloc;
	   wire [0:31] 	    drv_error_count;
	   
	   driver #(.mean_delay(mean_delay), .initial_seed(i), .width(width))
	   drv(.clk(clk), .reset(reset), .req(drv_req), .gnt(drv_gnt), .avg_latency(drv_avg_latency), .avg_rate(drv_avg_rate));

	   assign 	    avg_rate[i*32:(i+1)*32-1] = drv_avg_rate;
	   assign 	    avg_latency[i*32:(i+1)*32-1] = drv_avg_latency;
	   assign 	    req[i*width:(i+1)*width-1] = drv_req;
	   
	   for(j = 0; j < width; j = j + 1)
	     begin:per_port
		assign gnt_for_port[j*width+i] = drv_gnt[j];
	     end

	   assign      any_gnt[i] = |gnt_for_port[i*width:(i+1)*width-1];

	   assign      drv_error_no_alloc = ~|drv_gnt & |(drv_req & ~any_gnt);

	   assign      error_count_s[i*32:(i+1)*32-1] = (reset ?
							 {width{1'b0}} :
							 (error_count_q[i*32:(i+1)*32-1] + drv_error_no_alloc));

	   assign      drv_error_count = error_count_s[i*32:(i+1)*32-1];
	   
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

      $display(" driver |   rate   | latency  |  errors  ");
      $display("-----------------------------------------");
      for(k = 0; k < width; k = k + 1)
	begin
	   $display(" %6d | %8.3f | %8.3f | %8d ",
		  k,
		  avg_rate[k*32 +: 32] * 0.0001,
		  avg_latency[k*32 +: 32] * 0.0001,
		    error_count_q[k*32 +: 32]);
	end
      $display("-----------------------------------------");
      
      $finish;
      
   end
   
endmodule
