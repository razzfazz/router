module packet_sink
  #(parameter initial_seed = 0,
    parameter flit_rate = 50,
    parameter flit_width = 64,
    parameter num_vcs = 4)
   (clk, reset, valid, data, ready, vc);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   
   input clk;
   input reset;
   input [0:num_vcs-1] valid;
   input [0:flit_width-1] data;
   output wire ready;
   output wire [0:vc_width-1] vc;

   integer 		      seed = initial_seed;
   
   reg 			      random_valid;
   wire 		      sink_packet;
   assign sink_packet = |valid && random_valid;
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
   
   wire [0:flit_width-1]      data_s, data_q;
   assign data_s = sink_packet ? data : data_q;
   dff
     #(.width(flit_width),
       .reset_type(1))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   
   wire [0:vc_width-1] 	      vc_s, vc_q;
   assign vc_s = sink_packet ? vc : vc_q;
   dff
     #(.width(vc_width),
       .reset_type(1))
   vcq
     (.clk(clk),
      .reset(reset),
      .d(vc_s),
      .q(vc_q));
   
   wire 		      valid_s, valid_q;
   assign valid_s = sink_packet;
   dff
     #(.width(1),
       .reset_type(1))
   validq
     (.clk(clk),
      .reset(reset),
      .d(valid_s),
      .q(valid_q));
   
   always @(posedge clk)
     random_valid = ($dist_uniform(seed, 0, 99) < flit_rate);
   
endmodule
