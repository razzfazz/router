module sw_alloc
  #(
    parameter num_ports = 8,
    parameter num_vcs = 4,
    parameter use_matrix_arb = 1
    )
   (
    input     clk,
    input     reset,
    input [0:num_ports*num_vcs*num_ports-1] req,
    output [0:num_ports*num_vcs*num_ports-1] gnt
    );

   wire [0:num_ports*num_ports-1] 	     ;
	     
   genvar 				     i;
   generate
      for(i = 0; i < num_ports; i = i + 1)
	begin:input_ports
	   wire [0:num_ports-1] req_p;
	   or_n #(.width(num_ports), .inputs(num_vcs)) 
	   or_blk (.data_in(req[i*num_ports*num_vcs:(i+1)*num_ports*num_vcs-1]),
		   .data_out(req_p));
	   arbiter #(.width(num_ports), .use_matrix_arb(use_matrix_arb))
	   arb_blk (.clk(clk), .reset(reset), .update(
	end
   endgenerate
endmodule
