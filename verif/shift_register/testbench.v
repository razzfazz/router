module testbench
  #(parameter num_buffers = 8,
    parameter data_width = 16,
    parameter reset_type = 1,
    parameter Tclk = 2,
    parameter runtime = 1000,
    parameter rate_in = 50,
    parameter rate_out = 50, 
    parameter initial_seed = 0)
   ();

`include "functions.v"

   reg clk;
   reg reset;
   
   wire push;
   wire pop;
   wire full;
   wire empty;
   reg [0:data_width-1] write_data;
   wire [0:data_width-1] read_data;
   
   shift_register
     #(.depth(num_buffers),
       .width(data_width),
       .reset_type(reset_type))
   sr
     (.clk(clk),
      .reset(reset),
      .full(full),
      .data_in(write_data),
      .push(push),
      .empty(empty),
      .data_out(read_data),
      .pop(pop));
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end

   wire [0:data_width-1] write_data_next;
   
   assign write_data_next = reset ? {data_width{1'b0}} : (write_data + push);
   
   reg drain;
   reg flag_in, flag_out;

   assign push = ~reset & flag_in & ~full;
   assign pop = ~reset & flag_out & ~empty;
   
   integer seed = initial_seed;

   always @(posedge clk)
     begin
	flag_in <= ~drain && ($dist_uniform(seed, 0, 99) < rate_in);
	flag_out <= ($dist_uniform(seed, 0, 99) < rate_out);
	write_data <= write_data_next;
     end

   always @(negedge clk)
     begin
	if(push)
	  $display($time, " WRITE: %x.", write_data);
	if(pop)
	  $display($time, " READ:  %x.", read_data);
     end
   
   initial
   begin
      reset = 1'b1;
      drain = 1'b0;

      #(Tclk);

      reset = 1'b0;

      #(runtime*Tclk);

      drain = 1'b1;

      while(!empty)
	#(Tclk);
      
      $finish;
   end
      
endmodule
