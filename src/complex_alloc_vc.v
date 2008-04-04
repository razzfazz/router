module complex_alloc_vc(CLK, RST, req_ip_ivc_op, req_ip_ivc_ovc, elig_op_ovc,
			gnt_ip_ivc, gnt_ip_ivc_ovc);
   
   parameter num_ports = 5;
   parameter num_vcs = 2;

   // see dff.v for supported values
   parameter reset_type = 1;
   parameter hold_type = 1;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: separable, output-first, round-robin arbiters
    3: separable, output-first, matrix arbiters */
   parameter architecture = 0;
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_vcs*num_ports-1] req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] req_ip_ivc_ovc;
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   output [0:num_ports*num_vcs-1] gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_vcs-1] gnt_ip_ivc_ovc;
   
   wire clk = CLK;
   wire reset;
   
   dff
     #(.width(1),
       .reset_type(0),
       .hold_type(0))
   resetq
     (.clk(clk),
      .d(RST),
      .q(reset));
   
   vc_alloc
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .reset_type(reset_type),
       .hold_type(hold_type),
       .architecture(architecture))
   alloc
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op(req_ip_ivc_op),
      .req_ip_ivc_ovc(req_ip_ivc_ovc),
      .elig_op_ovc(elig_op_ovc),
      .gnt_ip_ivc(gnt_ip_ivc),
      .gnt_ip_ivc_ovc(gnt_ip_ivc_ovc));
   
endmodule
