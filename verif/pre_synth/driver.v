module driver
  #(
    parameter mean_delay = 5,
    parameter initial_seed = 0,
    parameter width = 1)
   (
    input     clk,
    input     reset,
    input [0:width-1] gnt,
    output wire [0:width-1] req);
   
   integer 		    seed = initial_seed;
   integer 		    delay;
   
   reg [0:width-1] 	    req_int;

   assign 		    req = req_int & {width{~reset}};

   integer 		    requests;
   integer 		    cycles;
   integer 		    wait_cycles;
   integer 		    avg_latency;
   integer 		    avg_rate;

   wire 		    error = |(gnt & ~req_int);
   
initial
  begin
     
     req_int = {width{1'b0}};
     requests = 0;
     wait_cycles = 0;
     cycles = 0;
     avg_latency = 0;
     avg_rate = 0;
     
     @(posedge clk);

     forever
       begin
	  while(reset)
	    @(posedge clk);
	  for(delay = $dist_exponential(seed, mean_delay);
	      delay > 0;
	      delay = delay - 1)
	    begin
	       @(posedge clk);
	       cycles = cycles + !reset;
	    end
	  @(posedge clk);
	  cycles = cycles + !reset;
	  req_int = $dist_uniform(seed, 1, 2 ** width - 1);
	  requests = requests + !reset;
	  @(posedge clk);
	  cycles = cycles + !reset;
	  while(!(|(req_int & gnt)))
	    begin
	       @(posedge clk);
	       wait_cycles = wait_cycles + !reset;
	       cycles = cycles + !reset;
	    end
	  req_int = {width{1'b0}};
	  avg_latency = 10000 * wait_cycles / requests;
	  avg_rate = 10000 * requests / cycles;
       end

  end
endmodule
