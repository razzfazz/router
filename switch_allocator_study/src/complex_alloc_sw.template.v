module complex_alloc_sw(CLK, RST, req_ip_ivc_op, req_ip_ivc_ovc, cred_op_ovc,
			gnt_ip_ivc, gnt_ip_op);
   
   parameter num_ports = NUM_PORTS;
   parameter num_vcs = NUM_VCS;

   // see dff.v for supported values
   parameter reset_type = RESET_TYPE;
   
   /* supported architectures:
    0: separable, input-first, RR arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, RR arbiters
    3: separable, output-first, matrix arbiters
    4: rotate inputs based on prio, round-robin arbiters in final stage
    5: rotate inputs based on prio, matrix arbiters in final stage
    6: replicate logic for prios, round-robin arbiters in final stage
    7: replicate logic for prios, matrix arbiters in final stage
    8: diagonal propagation arbiter, round-robin arbiters in final stage
    9: diagonal propagation arbiter, matrix arbiters in final stage */
   parameter architecture = ARCHITECTURE;
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   input [0:num_ports*num_vcs-1] cred_op_ovc;
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
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .reset_type(reset_type),
       .architecture(architecture))
   alloc
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op(req_ip_ivc_op),
      .req_ip_ivc_ovc(req_ip_ivc_ovc),
      .cred_op_ovc(cred_op_ovc),
      .gnt_ip_ivc(gnt_ip_ivc),
      .gnt_ip_op(gnt_ip_op));
   
endmodule
