module testbench
  ();
   
   parameter Tclk = 2;
   parameter runtime = 100;
   parameter initial_seed = 0;
   
`include "functions.v"
`include "config.v"
`include "constants.v"
   
   parameter reset_type = reset_type_async;
   parameter dedicated_cred_ivc_regs = 1;
   parameter buffer_free_threshold = 1;
   
   reg clk;
   reg reset;
   reg cred_valid;
   reg [0:vc_idx_width-1] cred_vc;
   reg [0:num_vcs-1] 	  vc_gnt_ovc;
   reg 			  flit_valid;
   reg [0:vc_idx_width-1] flit_vc;
   reg 			  flit_tail;
   wire [0:num_vcs-1] 	  elig_ovc;
   wire [0:num_vcs-1] 	  free_ovc;
   wire [0:num_vcs-1] 	  free_plus1_ovc;
   wire [0:num_vcs-1] 	  free_ivc;
   
   op_ctrl
     #(.reset_type(reset_type),
       .dedicated_cred_ivc_regs(dedicated_cred_ivc_regs),
       .buffer_free_threshold(buffer_free_threshold))
   opc
     (.clk(clk),
      .reset(reset),
      .cred_valid(cred_valid),
      .cred_vc(cred_vc),
      .vc_gnt_ovc(vc_gnt_ovc),
      .flit_valid(flit_valid),
      .flit_vc(flit_vc),
      .flit_tail(flit_tail),
      .elig_ovc(elig_ovc),
      .free_ovc(free_ovc),
      .free_plus1_ovc(free_plus1_ovc),
      .free_ivc(free_ivc));

   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end

   integer i;
   
   initial
   begin

      #(Tclk-1);
      
      reset = 1'b1;

      #(3*Tclk);

      reset = 1'b0;
      flit_valid = 1'b0;
      cred_valid = 1'b0;
      vc_gnt_ovc = {num_vcs{1'b0}};

      
      #(Tclk);
      
      vc_gnt_ovc[0] = 1'b1;

      #(Tclk);

      vc_gnt_ovc[0] = 1'b0;
      
      flit_valid = 1'b1;
      flit_vc = {vc_idx_width{1'b0}};
      flit_tail = 1'b0;

      #(7*Tclk);

      flit_tail = 1'b1;

      #(Tclk);

      flit_valid = 1'b0;
      
      #(runtime*Tclk);

      $finish;
   end
   
endmodule
