module complex_alloc_vc(CLK, RST, req_ip_ivc_op, req_ip_ivc_ovc, gnt_ip_ivc_ovc, gnt_op_ovc);
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, round-robin arbiters
    3: separable, output-first, matrix arbiters */
   parameter architecture = 0;
   
`include "constants.v"
`include "globals.v"
`include "functions.v"
`include "config.v"
   
   parameter reset_type = reset_type_async;
   
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] gnt_op_ovc;
   
   wire clk = CLK;
   wire reset;
   
   dff
     #(.width(1),
       .reset_type(0))
   resetq
     (.clk(clk),
      .d(RST),
      .q(reset));
   
   vc_alloc
     #(.reset_type(reset_type),
       .allocator_type(architecture >> 1),
       .arbiter_type(architecture & 1))
   alloc
     (.clk(clk),
      .reset(reset),
      .vc_req_ip_ivc_op(req_ip_ivc_op),
      .vc_req_ip_ivc_ovc(req_ip_ivc_ovc),
      .vc_gnt_ip_ivc_ovc(gnt_ip_ivc_ovc),
      .vc_gnt_op_ovc(gnt_op_ovc));
   
endmodule
