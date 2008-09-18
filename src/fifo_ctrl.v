module fifo_ctrl
   (clk, reset, push, pop, write_addr, read_addr, empty, empty_early, error);
   
`include "functions.v"
`include "constants.v"
   
   parameter depth = 8;
   
   parameter error_checker_mode = 1;
   parameter error_capture_mode = 0;
   
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
   output empty_early;
   
   output error;
   
   wire [0:idx_width-1] write_addr;
   wire [0:idx_width-1] read_addr;
   
   wire 		empty;
   wire 		empty_early;
   
   wire 		error;
   
   
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

   wire 		read_ptr_p_s, read_ptr_p_q;
   assign read_ptr_p_s = pop ? ^read_ptr_next : read_ptr_p_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   read_ptr_pq
     (.clk(clk),
      .reset(reset),
      .d(read_ptr_p_s),
      .q(read_ptr_p_q));
   
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
   
   wire 		write_ptr_p_s, write_ptr_p_q;
   assign write_ptr_p_s = push ? ^write_ptr_next : write_ptr_p_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   write_ptr_pq
     (.clk(clk),
      .reset(reset),
      .d(write_ptr_p_s),
      .q(write_ptr_p_q));
   
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
   assign empty_early = empty_s;
   
   wire 		full;
   assign full = (read_ptr == write_ptr) && !empty_q;
   
   wire [0:3] 		errors_in;
   assign errors_in = {empty & pop,
		       full & push,
		       ^read_ptr ^ read_ptr_p_q,
		       ^write_ptr ^ write_ptr_p_q};
   
   wire [0:3] 		errors_out;
   checker
     #(.num_errors(4),
       .checker_mode(error_checker_mode),
       .capture_mode(error_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out;
   
endmodule
