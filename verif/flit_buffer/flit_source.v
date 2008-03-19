module flit_source
  #(parameter initial_seed = 0,
    parameter flit_rate = 50,
    parameter flit_width = 64,
    parameter num_vcs = 4)
   (clk, reset, ready, valid, vc, data);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   
   input clk;
   input reset;
   input [0:num_vcs-1] ready;
   output wire valid;
   output wire [0:vc_width-1] vc;
   output wire [0:flit_width-1] data;
   
   integer 			seed = initial_seed;

   reg 				random_valid;
   reg [0:vc_width-1] 		random_vc;
   wire 			generate_packet;
   assign generate_packet = ready[random_vc] && random_valid;

   reg [0:flit_width-1] 	random_data;
   assign data = generate_packet ? random_data : {flit_width{1'b0}};
   assign vc = generate_packet ? random_vc : {vc_width{1'b0}};
   assign valid = generate_packet;
   
   integer 			i;
   always @(posedge clk)
     begin
	for(i = 0; i < flit_width; i = i + 1)
	  random_data[i] <= ($dist_uniform(seed, 0, 99) < 50);
	random_vc <= $dist_uniform(seed, 0, num_vcs-1);
	random_valid <= ($dist_uniform(seed, 0, 99) < flit_rate);
     end
   
endmodule
