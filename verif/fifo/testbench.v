`default_nettype none

module testbench
  ();
   
`include "c_functions.v"
`include "c_constants.v"
   
   parameter num_buffers = 8;
   parameter data_width = 16;
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   parameter reset_type = `RESET_TYPE_ASYNC;
   parameter Tclk = 2;
   parameter runtime = 1000;
   parameter rate_in = 50;
   parameter rate_out = 50; 
   parameter initial_seed = 0;
   
   localparam addr_width = clogb(num_buffers);
   
   reg clk;
   reg reset;
   
   wire push;
   wire pop;
   wire [0:addr_width-1] write_addr;
   wire [0:addr_width-1] read_addr;
   wire 		 fc_almost_empty;
   wire 		 fc_empty;
   wire 		 fc_almost_full;
   wire 		 fc_full;
   wire [0:1] 		 fc_errors;
   
   c_fifo_ctrl
     #(.depth(num_buffers),
       .reset_type(reset_type))
   fc
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .push(push),
      .pop(pop),
      .write_addr(write_addr),
      .read_addr(read_addr),
      .almost_empty(fc_almost_empty),
      .empty(fc_empty),
      .almost_full(fc_almost_full),
      .full(fc_full),
      .errors(fc_errors));
   
   wire 		 ft_almost_empty;
   wire 		 ft_empty;
   wire 		 ft_almost_full;
   wire 		 ft_full;
   wire [0:1] 		 ft_errors;
   
   c_fifo_tracker
     #(.depth(num_buffers),
       .reset_type(reset_type))
   ft
     (.clk(clk),
      .reset(reset),
      .active(1'b1),
      .push(push),
      .pop(pop),
      .almost_empty(ft_almost_empty),
      .empty(ft_empty),
      .almost_full(ft_almost_full),
      .full(ft_full),
      .errors(ft_errors));

   reg [0:data_width-1] write_data;
   wire [0:data_width-1] read_data;

   c_regfile
     #(.width(data_width),
       .depth(num_buffers),
       .regfile_type(regfile_type))
   rf
     (.clk(clk),
      .active(1'b1),
      .write_enable(push),
      .write_address(write_addr),
      .write_data(write_data),
      .read_enable(pop),
      .read_address(read_addr),
      .read_data(read_data));
   
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

   assign push = ~reset & flag_in & ~fc_full;
   assign pop = ~reset & flag_out & ~fc_empty;
   
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
	  $display($time, " WRITE: %x=%x.", write_addr, write_data);
	if(pop)
	  $display($time, " READ:  %x=%x.", read_addr, read_data);
	if(pop & (^read_data === 1'bx))
	  $display($time, " ERROR: read X value");
	if((fc_almost_empty ^ ft_almost_empty) |
	   (fc_empty ^ ft_empty) |
	   (fc_almost_full ^ ft_almost_full) |
	   (fc_full ^ ft_full))
	  $display($time, " ERROR: c_fifo_ctrl and c_fifo_tracker mismatch");
     end
   
   initial
   begin
      reset = 1'b1;
      drain = 1'b0;

      #(Tclk);

      reset = 1'b0;

      #(runtime*Tclk);

      drain = 1'b1;

      while(!fc_empty)
	#(Tclk);
      
      $finish;
   end
      
endmodule
