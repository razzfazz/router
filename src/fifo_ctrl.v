// simple FIFO controller
module fifo_ctrl
   (clk, reset, push, pop, write_addr, read_addr, empty, empty_early, full,
    full_early, error);
   
`include "constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of entries in FIFO
   parameter depth = 8;
   
   // include error checker
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required to select an individual buffer entry
   localparam idx_width = clogb(depth);
   
   input clk;
   input reset;
   
   // write (add) an element
   input push;
   
   // read (remove) an element
   input pop;
   
   // address to write current input element to
   output [0:idx_width-1] write_addr;
   wire [0:idx_width-1] write_addr;
   
   // address to read next output element from
   output [0:idx_width-1] read_addr;
   wire [0:idx_width-1] read_addr;
   
   // buffer empty indication
   output empty;
   wire 		empty;
   
   // buffer empty indication (one cycle early)
   output empty_early;
   wire 		empty_early;
   
   // buffer full indication
   output full;
   wire 		full;
   
   // buffer full indication (one cycle early)
   output full_early;
   wire 		full_early;
   
   // internal error condition detected
   output error;
   wire 		error;
   
   wire [0:idx_width-1] read_ptr, read_ptr_early, read_ptr_next,
			read_ptr_prev;
   mod_ctr
     #(.num_values(depth),
       .reset_type(reset_type))
   read_ptr_ctr
     (.clk(clk),
      .reset(reset),
      .incr(pop),
      .decr(1'b0),
      .load(1'b0),
      .load_value({idx_width{1'b0}}),
      .value(read_ptr),
      .early_value(read_ptr_early),
      .next_value(read_ptr_next),
      .prev_value(read_ptr_prev));
   
   wire [0:idx_width-1] write_ptr, write_ptr_early, write_ptr_next,
			write_ptr_prev;
   mod_ctr
     #(.num_values(depth),
       .reset_type(reset_type))
   write_ptr_ctr
     (.clk(clk),
      .reset(reset),
      .incr(push),
      .decr(1'b0),
      .load(1'b0),
      .load_value({idx_width{1'b0}}),
      .value(write_ptr),
      .early_value(write_ptr_early),
      .next_value(write_ptr_next),
      .prev_value(write_ptr_prev));
   
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
   assign full = (read_ptr == write_ptr) && !empty_q;
   assign full_early = (read_ptr_early == write_ptr_early) && !empty_s;
   
   wire 		error_underflow;
   assign error_underflow = empty & pop;
   
   wire 		error_overflow;
   assign error_overflow = full & push;
   
   wire [0:1] 		errors_in;
   assign errors_in = {error_underflow,
		       error_overflow};
   
   wire [0:1] 		errors_out;
   checker
     #(.num_errors(2),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out;
   
endmodule
