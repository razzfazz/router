module driver
  #(  parameter mean_delay = 5,
      parameter initial_seed = 0)
   (   input clk,
       input reset,
       input gnt,
       output wire req);

   integer    seed = initial_seed;
   integer    delay;

   reg 	      req_int;

   assign     req = req_int & ~reset;

   integer    requests;
   integer    cycles;
   integer    wait_cycles;
   integer    avg_latency;
   integer    avg_rate;
   
initial
  begin
     
     req_int = 0'b0;
     requests = 0;
     wait_cycles = 0;
     cycles = 0;
     avg_latency = 0;
     avg_rate = 0;
     
     @(posedge clk);

     forever
       begin
	  for(delay = $dist_exponential(seed, mean_delay);
	      delay > 0;
	      delay = delay - 1)
	    begin
	       @(posedge clk);
	       cycles = cycles + 1;
	    end
	  @(posedge clk);
	  cycles = cycles + 1;
	  req_int = 0'b1;
	  requests = requests + 1;
	  @(posedge clk);
	  cycles = cycles + 1;
	  while(gnt != 0'b1)
	    begin
	       @(posedge clk);
	       wait_cycles = wait_cycles + 1;
	       cycles = cycles + 1;
	    end
	  req_int = 0'b0;
	  avg_latency = 10000 * wait_cycles / requests;
	  avg_rate = 10000 * requests / cycles;
       end

  end
endmodule
