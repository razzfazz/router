module complex_alloc_sw(CLK, RST, req_ip_ivc_op, gnt_ip_ivc, gnt_ip_op);
   
   /* supported architectures:
    0: separable, input-first, RR arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, RR arbiters
    3: separable, output-first, matrix arbiters
    4: mux inputs based on prio, round-robin arbiters in final stage
    5: mux inputs based on prio, matrix arbiters in final stage
    6: replicate logic for prios, round-robin arbiters in final stage
    7: replicate logic for prios, matrix arbiters in final stage
    8: diagonal propagation arbiter, round-robin arbiters in final stage
    9: diagonal propagation arbiter, matrix arbiters in final stage
    10: rotate inputs based on prio, round-robin arbiters in final stage
    11: rotate inputs based on prio, matrix arbiters in final stage */
   parameter architecture = 0;
   
`include "constants.v"
`include "globals.v"
`include "functions.v"
`include "config.v"
    
   parameter reset_type = reset_type_async;
   
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output [0:num_ports*num_ports-1] gnt_ip_op;
   
   wire clk = CLK;
   wire reset;
   
   dff
     #(.width(1),
       .reset_type(0))
   resetq
     (.clk(clk),
      .d(RST),
      .q(reset));
   
   sw_alloc
     #(.reset_type(reset_type),
       .allocator_type(architecture >> 1),
       .arbiter_type(architecture & 1))
   alloc
     (.clk(clk),
      .reset(reset),
      .sw_req_ip_ivc_op(req_ip_ivc_op),
      .sw_gnt_ip_ivc(gnt_ip_ivc),
      .sw_gnt_ip_op(gnt_ip_op));
   
endmodule
