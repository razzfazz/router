`default_nettype none

module testbench
  ();
  
`include "c_constants.v"
`include "c_functions.v"
   
   parameter num_ports = 4;
   parameter num_priorities = 4;
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   parameter Tclk = 2;
   parameter runtime = 1000;
   parameter rate = 50;
   parameter initial_seed = 0;
   
   localparam prio_width = clogb(num_priorities);
   
   reg clk;
   
   always
     begin
	clk <= 1'b1;
	#(Tclk/2);
	clk <= 1'b0;
	#(Tclk/2);
     end
   
   reg reset;
   
   initial
     begin
	
	reset = 1'b1;
	
	#(Tclk);
	
	reset = 1'b0;
	
	#(Tclk);
	
	#(runtime*Tclk);
	
	$finish;
	
     end
   
   reg [0:num_ports-1] req;
   reg [0:num_ports*prio_width-1] priorities;
   
   integer 			  i;
   integer 			  seed = initial_seed;
   
   always @(posedge clk, posedge reset)
     begin
	
	for(i = 0; i < num_ports; i = i + 1)
	  begin
	     
	     req[i] <= ($dist_uniform(seed, 0, 99) < rate);
	     priorities[i*prio_width +: prio_width]
	       <= $dist_uniform(seed, 0, num_priorities - 1);
	     
	  end
	
     end
   
   wire [0:num_ports-1] 	  sel;
   c_prio_sel
     #(.num_ports(num_ports),
       .num_priorities(num_priorities))
   psel
     (.priorities(priorities),
      .enable(req),
      .select(sel));
   
   wire 			  update;
   assign update = |req;
   
   wire [0:num_ports-1] 	  gnt;
   c_prio_arbiter
     #(.num_ports(num_ports),
       .num_priorities(num_priorities),
       .arbiter_type(arbiter_type),
       .reset_type(reset_type))
   parb
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .update(update),
      .priorities(priorities),
      .req(req),
      .gnt(gnt));
   
   wire [0:num_ports-1] 	  error;
   assign error = gnt & ~sel;
   
   always @(negedge clk)
     begin
	
	if(|error)
	  begin
	     
	     $display($time, " ERROR:");
	     $display($time, "  sel=%b", sel);
	     $display($time, "  gnt=%b", gnt);
	     $display($time, "  err=%b", error);
	     
	     for(i = 0; i < num_ports; i = i + 1)
	       begin
		  $display($time, " %d = %b %b", i, req[i], 
			   priorities[i*prio_width +: prio_width]);
	       end
	     
	     $stop;
	     
	  end
	
     end
   
endmodule
