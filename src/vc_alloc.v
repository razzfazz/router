module vc_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_output_first = 0,
    parameter use_allocator_type = 0) // 0 = separable
   (input     clk,
    input     reset,
    
    // I/O to input controller
    // [sort order: input port,input VC,ouput port]
    input [0:num_ports*num_vcs*num_ports*num_vcs-1] req,
    output [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt,

    // bit mask representing available output VCs
    // [sort order: output port,output VC]
    input [0:num_ports*num_vcs-1] vc_mask);
   
   generate

      if(use_allocator_type == 0)
	begin
	   vc_alloc_separable
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .use_arbiter_type(use_arbiter_type),
	       .use_output_first(use_output_first))
	   sep_alloc
	     (.clk(clk),
	      .reset(reset),
	      .req(req),
	      .gnt(gnt),
	      .vc_state(vc_state));
	end
      
   endgenerate
   
endmodule
