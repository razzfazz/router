module complex_alloc_vc(CLK, RST, req_ip_ivc_op_ovc, elig_op_ovc, gnt_ip_ivc_op_ovc, gnt_ip_ivc);
   
   parameter num_ports = NUM_PORTS;
   parameter num_vcs = NUM_VCS;
   parameter use_clock_gating = USE_CLOCK_GATING;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters */
   parameter use_architecture = USE_ARCHITECTURE;
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc;
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   output [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_ip_ivc_op_ovc;
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   
   wire 			     clk = CLK;
   wire 			     reset;
   
   dff
     #(.width(1),
       .reset_type(0),
       .use_enable(0))
   resetq
     (.clk(clk),
      .d(RST),
      .q(reset));
   
   vc_alloc
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .use_clock_gating(use_clock_gating),
       .use_architecture(use_architecture))
   alloc
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op_ovc(req_ip_ivc_op_ovc),
      .elig_op_ovc(elig_op_ovc),
      .gnt_ip_ivc_op_ovc(gnt_ip_ivc_op_ovc),
      .gnt_ip_ivc(gnt_ip_ivc));
   
endmodule
