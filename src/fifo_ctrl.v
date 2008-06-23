module fifo_ctrl
   (clk, reset, push, pop, write_addr, read_addr, empty);
   
   
`include "functions.v"
`include "constants.v"
   
   
   parameter depth = 8;
   
   // see dff.v for supported values
   parameter reset_type = reset_type_async;
   
   localparam idx_width = clogb(depth);
   
   
   input clk;
   input reset;
   
   input push;
   input pop;
   
   output [0:idx_width-1] write_addr;
   output [0:idx_width-1] read_addr;
   
   output empty;
   
   wire [0:idx_width-1] read_ptr, read_ptr_next;
   mod_ctr
     #(.num_values(depth),
       .reset_type(reset_type))
   read_ptr_ctr
     (.clk(clk),
      .reset(reset),
      .incr(pop),
      .value(read_ptr),
      .next_value(read_ptr_next));
   
   wire [0:idx_width-1] write_ptr, write_ptr_next;
   mod_ctr
     #(.num_values(depth),
       .reset_type(reset_type))
   write_ptr_ctr
     (.clk(clk),
      .reset(reset),
      .incr(push),
      .value(write_ptr),
      .next_value(write_ptr_next));
   
   wire 		almost_empty;
   assign almost_empty = (read_ptr_next == write_ptr);
   
   wire 		empty_s, empty_q;
   assign empty_s = (empty_q | (almost_empty & pop)) & ~push;
   
   dff
     #(.width(1),
       .reset_type(reset_type),
       .reset_value(1'b1))
   emptyq
     (.clk(clk),
      .reset(reset),
      .d(empty_s),
      .q(empty_q));

   assign read_addr = read_ptr;
   assign write_addr = write_ptr;
   assign empty = empty_q;

endmodule
