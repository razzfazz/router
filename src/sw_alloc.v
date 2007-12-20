module sw_alloc
  #(parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_arbiter_type = 1, // 0 = RR, 1 = matrix
    parameter use_clock_gating = 1,
    parameter use_output_first = 0,
    parameter use_allocator_type = 0) // 0 = separable
   (input     clk,
    input     reset,
    
    // requests and grant signals to input controller
    // [sort order: input port,input VC,ouput port]
    // [each input VC at each input port can request at most one output port]
    input [0:num_ports*num_vcs*num_ports-1] req,
    output wire [0:num_ports*num_vcs*num_ports-1] gnt);
    
   generate
      
      if(use_allocator_type == 0)
	begin
	   sw_alloc_separable
	     #(.num_ports(num_ports),
	       .num_vcs(num_vcs),
	       .use_arbiter_type(use_arbiter_type),
	       .use_clock_gating(use_clock_gating),
	       .use_output_first(use_output_first))
	   sep_alloc
	     (.clk(clk),
	      .reset(reset),
	      .req(req),
	      .gnt(gnt));
	end
      
   endgenerate
   
endmodule
