module testbench
  #(parameter width = 4,
    parameter [0:width-1] feedback = 4'b1001,
    parameter Tclk = 2,
    parameter runtime = 20)
   ();
   
`include "c_constants.v"
   
   reg clk;
   reg reset;
   reg load;
   reg run;
   reg [0:width-1] d;

   wire [0:width-1] lfsr_q;
   
   c_lfsr
     #(.width(width))
   lfsr
     (.clk(clk),
      .reset(reset),
      .load(load),
      .run(run),
      .feedback(feedback),
      .d(d),
      .q(lfsr_q));
   
   wire [0:width-1] cfsr_q;

   c_cfsr
     #(.width(width))
   cfsr
     (.clk(clk),
      .reset(reset),
      .load(load),
      .run(run),
      .feedback(feedback),
      .d(d),
      .q(cfsr_q));
   
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
      reset = 1'b1;
      
      #(Tclk);
      
      reset = 1'b0;
      load = 1'b1;
      run = 1'b0;
      d = 'd1;
      
      #(Tclk);
      
      load = 1'b0;
      run = 1'b1;
      d = 'dx;
      
      for(i = 0; i < runtime; i = i + 1)
	begin
	   #(Tclk);
	   $display($time, " LFSR: %b (%x), CFSR: %b (%x).", lfsr_q, lfsr_q, cfsr_q, cfsr_q);
	end
      
      $finish;
   end
   
endmodule
