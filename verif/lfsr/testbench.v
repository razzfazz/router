module testbench
   ();
   
`include "c_constants.v"
   
//   parameter width = 4;
   parameter width = 16;
   
   // feedback polynomial
//   parameter [0:width-1] feedback = 4'b1001;
//   parameter [0:width-1] feedback = 4'b1100;
   parameter [0:width-1] feedback = 16'b1000000000010110;
   
   // feedback matrix for fully unrolled LFSR (i.e., width iterations at once)
/*   parameter [0:width*width-1] ufeedback = {4'b1101,
					    4'b1111,
					    4'b1110,
					    4'b1110};*/
/*   parameter [0:width*width-1] ufeedback = {4'b1000,
					    4'b0100,
					    4'b0010,
					    4'b1101};*/
   parameter [0:width*width-1] ufeedback = {16'b1100000000010110,
					    16'b0110000000001011,
					    16'b1011000000010011,
					    16'b1101100000011111,
					    16'b1110110000011001,
					    16'b1111011000011010,
					    16'b0111101100001101,
					    16'b1011110110010000,
					    16'b0101111011001000,
					    16'b0010111101100100,
					    16'b0001011110110010,
					    16'b0000101111011001,
					    16'b1000010111111010,
					    16'b0100001011111101,
					    16'b1010000101101000,
					    16'b1101000010100010};
   
   parameter Tclk = 2;
   localparam runtime = (1 << width) + 1;
   
   reg clk;
   reg reset;
   reg load;
   reg run;
   reg [0:width-1] d;
   
   // a regular LFSR (cycles through all 2^width-1 non-zero values)
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
   
   // a complete LFSR / CFSR (cycles through all 2^width possible values)
   wire [0:width-1] cfsr_q;
   c_lfsr
     #(.width(width),
       .complete(1))
   cfsr
     (.clk(clk),
      .reset(reset),
      .load(load),
      .run(run),
      .feedback(feedback),
      .d(d),
      .q(cfsr_q));
   
   // an unrolled LFSR (cycles through all 2^width-1 non-zero values with a 
   // stride of width (compared to a regular LFSR)
   wire [0:width-1] ulfsr_q;
   c_lfsr
     #(.width(width),
       .complete(0),
       .generalized(1))
   ulfsr
     (.clk(clk),
      .reset(reset),
      .load(load),
      .run(run),
      .feedback(ufeedback),
      .d(d),
      .q(ulfsr_q));
   
   // an unrolled CFSR (cycles through all 2^width possible values with a stride
   // of width (compared to regular CFSR)
   wire [0:width-1] ucfsr_q;
   c_lfsr
     #(.width(width),
       .complete(1),
       .generalized(1))
   ucfsr
     (.clk(clk),
      .reset(reset),
      .load(load),
      .run(run),
      .feedback(ufeedback),
      .d(d),
      .q(ucfsr_q));
   
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
      d = {{(width-1){1'b0}}, 1'b1};
      
      #(Tclk);
      
      load = 1'b0;
      run = 1'b1;
      d = {width{1'b0}};
      
      for(i = 0; i < runtime; i = i + 1)
	begin
	   $display("%8d | %b (%x) | %b (%x) | %b (%x) | %b (%x)", i, lfsr_q, lfsr_q, cfsr_q, cfsr_q, ulfsr_q, ulfsr_q, ucfsr_q, ucfsr_q);
	   #(Tclk);
	end
      
      $finish;
   end
   
endmodule
