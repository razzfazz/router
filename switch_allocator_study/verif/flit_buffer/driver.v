module driver
  #(parameter mean_delay = 5,
    parameter fixed_delay = 0,
    parameter hold_requests = 1,
    parameter initial_seed = 0,
    parameter num_ports = 1)
   (input     clk,
    input     reset,
    output wire [0:num_ports-1] req,
    input [0:num_ports-1]       gnt,
    output reg [0:31] 		avg_latency,
    output reg [0:31] 		avg_rate,
    output reg [0:31] 		avg_match);
   
   integer 			seed = initial_seed;
   integer 			delay;
   integer 			start_delay;
   
   reg [0:num_ports-1] 		req_int;
   
   assign req = req_int & {num_ports{~reset}};
   
   integer 			requests;
   integer 			cycles;
   integer 			wait_cycles;
   integer                      match;
   
   wire 			error = |(gnt & ~req_int);
   
initial
  begin
     
     req_int = {num_ports{1'b0}};
     requests = 0;
     wait_cycles = 0;
     match = 0;
     cycles = 0;
     avg_latency = 0;
     avg_rate = 0;
     avg_match = 0;

     @(posedge clk);

     forever
       begin
	  while(reset)
	    @(posedge clk);
	  if(fixed_delay)
	    begin
	       start_delay = mean_delay;
	    end
	  else
	    begin
	       start_delay = $dist_exponential(seed, mean_delay);
	    end
	  for(delay = start_delay; delay > 0; delay = delay - 1)
	    begin
	       @(posedge clk);
	       cycles = cycles + !reset;
	    end
	  req_int = $dist_uniform(seed, 1, 2 ** num_ports - 1);
	  requests = requests + !reset;
	  @(posedge clk);
	  cycles = cycles + !reset;
	  match = match + |(req_int & gnt);
	  while(~|(req_int & gnt) && hold_requests)
	    begin
	       @(posedge clk);
	       cycles = cycles + !reset;
	       wait_cycles = wait_cycles + !reset;
	    end
	  req_int = {num_ports{1'b0}};
	  avg_latency = 10000 * wait_cycles / requests;
	  avg_rate = 10000 * requests / cycles;
	  avg_match = 10000 * match / requests;
       end

  end
endmodule
