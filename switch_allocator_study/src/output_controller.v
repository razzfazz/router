module output_controller
  #(parameter num_vcs = 2,
    parameter use_clock_gating = 1)
   (input     clk,
    input     reset,
    
    input [0:num_vcs-1] cred_in,
    output [0:data_width-1] data_out,

    // [sort order: input VC,output port,output VC]
    output [0:num_vcs*num_ports*num_vcs-1] vc_alloc_req,
    input [0:num_vcs*num_ports*num_vcs-1]  vc_alloc_gnt,
    
    // [sort order: input VC,output port]
    output [0:num_vcs*num_ports-1] 	   sw_alloc_req,
    input [0:num_vcs*num_ports-1] 	   sw_alloc_gnt,

    // [sort order: input VC]
    output [0:num_vcs-1] 	   cred_out);

endmodule

    