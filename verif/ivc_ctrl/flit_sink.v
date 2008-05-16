module flit_sink
  #(parameter initial_seed = 0,
    parameter flit_rate = 50,
    parameter num_vcs = 4)
   (clk, reset, valid, ready, vc);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   
   input clk;
   input reset;
   input [0:num_vcs-1] valid;
   output wire ready;
   output wire [0:vc_width-1] vc;

   integer 		      seed = initial_seed;
   
   reg 			      random_ready;
   wire 		      sink_packet;
   assign sink_packet = |valid && random_ready;
   
   wire [0:num_vcs-1] 	      sink_vc_1hot;
   arbiter
     #(.num_ports(num_vcs))
   sink_vc_sel
     (.clk(clk),
      .reset(reset),
      .update(sink_packet),
      .req(valid),
      .gnt(sink_vc_1hot));
   
   wire [0:vc_width-1] 	      sink_vc_encoded;
   assign sink_vc_encoded = encode(sink_vc_1hot);
   
   assign vc = (num_vcs - 1) - sink_vc_encoded;
   assign ready = sink_packet;
   
   always @(posedge clk)
     random_ready <= ($dist_uniform(seed, 0, 99) < flit_rate);
   
endmodule
