module switch_alloc_input_block
  #(  parameter num_vcs = 4,
      parameter use_matrix_arb = 1)
   (   input clk,
       input reset,
       
       input [0:num_vcs-1] ivc_sai_req,
       input [0:num_ports-1] ivc_sai_ports[0:num_vcs-1],
       output [0:num_vcs-1] sai_ivc_gnt,

       input [0:num_ports-1] sao_sai_gnt,
       output [0:num_ports-1] sai_sao_req);

   wire [0:num_vcs-1] 	      in_stg_gnt;
   wire 		      update = |sao_sai_gnt;
   
   arbiter #(.width(num_vcs), .use_matrix_arb(use_matrix_arb)) 
   arb (.clk(clk), .reset(reset), .update(update), .req(req), .gnt(in_stg_gnt));
   
endmodule
