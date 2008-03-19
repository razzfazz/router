module packet_source
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

   wire 			valid_q;
   wire [0:vc_width-1] 		vc_q;
   wire 			generate_packet;
   assign generate_packet = !valid_q || ready[vc_q];

   reg [0:flit_width-1] 	random_data;
   wire [0:flit_width-1] 	data_s, data_q;
   assign data_s = generate_packet ? random_data : data_q;
   dff
     #(.width(flit_width),
       .reset_type(1))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   assign data = data_q;

   reg [0:vc_width-1] 		random_vc;
   wire [0:vc_width-1] 		vc_s;
   assign vc_s = generate_packet ? random_vc : vc_q;
   dff
     #(.width(vc_width),
       .reset_type(1))
   vcq
     (.clk(clk),
      .reset(reset),
      .d(vc_s),
      .q(vc_q));
   assign vc = vc_q;

   reg 				random_valid;
   wire 			valid_s;
   assign valid_s = generate_packet ? random_valid : valid_q;
   dff
     #(.width(1),
       .reset_type(1))
   validq
     (.clk(clk),
      .reset(reset),
      .d(valid_s),
      .q(valid_q));
   assign valid = valid_q;

   integer 			i;
   always @(posedge clk)
     begin
	for(i = 0; i < flit_width; i = i + 1)
	  random_data[i] <= ($dist_uniform(seed, 0, 99) < 50);
	random_vc <= $dist_uniform(seed, 0, num_vcs-1);
	random_valid = ($dist_uniform(seed, 0, 99) < flit_rate);
     end
   
endmodule
