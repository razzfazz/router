// simple FIFO controller
module fifo_ctrl
   (clk, reset, push, pop, write_addr, read_addr, empty, empty_early, error);
   
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
   
   // internal error condition detected
   output error;
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
