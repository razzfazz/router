module complex_alloc_sw(CLK, RST, req_ip_ivc_op_ovc, cred_op_ovc, gnt_ip_ivc, gnt_ip_op);
   
   parameter num_ports = 8;
   parameter num_vcs = 2;
   parameter use_clock_gating = 0;
   
   /* supported architectures:
    0: separable, input-first, RR arbiters
    1: separable, output-first, RR arbiters
    2: separable, input-first, matrix arbiters
    3: separable, output-first, matrix arbiters
    4: wavefront, RR arbiters
    5: wavefront, matrix arbiters */
   parameter use_architecture = 0;
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_vcs*num_ports*num_vcs-1] req_ip_ivc_op_ovc;
   input [0:num_ports*num_vcs-1] cred_op_ovc;
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output [0:num_ports*num_ports-1] gnt_ip_op;
   
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
   
   sw_alloc
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .use_clock_gating(use_clock_gating),
       .use_architecture(use_architecture))
   alloc
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op_ovc(req_ip_ivc_op_ovc),
      .cred_op_ovc(cred_op_ovc),
      .gnt_ip_ivc(gnt_ip_ivc),
      .gnt_ip_op(gnt_ip_op));
   
endmodule
