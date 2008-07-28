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
`include "sim_functions.v"
   
   localparam addr_width = clogb(num_buffers);
   
   reg clk;
   reg reset;
   
   wire push;
   wire pop;
   wire [0:addr_width-1] write_addr;
   wire [0:addr_width-1] read_addr;
   wire 		 empty;
   
   fifo_ctrl
     #(.depth(num_buffers),
       .reset_type(reset_type))
   ffc
     (.clk(clk),
      .reset(reset),
      .push(push),
      .pop(pop),
      .write_addr(write_addr),
      .read_addr(read_addr),
      .empty(empty));
   
   wire free;
   wire free_early;
   
   credit_tracker
     #(.num_credits(num_buffers),
       .reset_type(reset_type))
   ct
     (.clk(clk),
      .reset(reset),
      .debit(push),
      .credit(pop),
      .clear(1'b0),
      .free(free),
      .free_early(free_early));

   reg [0:data_width-1] write_data;
   wire [0:data_width-1] read_data;

   regfile
     #(.width(data_width),
       .depth(num_buffers))
   rf
     (.clk(clk),
      .write_enable(push),
      .write_address(write_addr),
      .write_data(write_data),
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

   assign push = ~reset & flag_in & free;
   assign pop = ~reset & flag_out & ~empty;

   wire pop_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   popq
     (.clk(clk),
      .reset(reset),
      .d(pop),
      .q(pop_q));

   wire [0:addr_width-1] read_addr_q;
   dff
     #(.width(addr_width),
       .reset_type(reset_type))
   read_addrq
     (.clk(clk),
      .reset(reset),
      .d(read_addr),
      .q(read_addr_q));

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
	if(pop_q)
	  $display($time, " READ:  %x=%x.", read_addr_q, read_data);
	if(pop_q & is_x(read_data))
	  $display($time, " ERROR: read X value");
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
