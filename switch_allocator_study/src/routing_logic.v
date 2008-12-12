module routing_logic
  #(parameter addr_width = 8,
    parameter address = 0,
    parameter use_clock_gating = 1)
   (input clk,
    input reset,
    input req,
    input [0:addr_width-1] dest,
    output gnt,

    // [sort order: output port,output VC]
    output [0:num_ports*num_vcs-1] route_info);

endmodule