// generic FIFO buffer built from registers
module fifo
  (clk, reset, full, data_in, push, empty, data_out, pop, error);
   
`include "constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of entries
   parameter depth = 4;
   
   // width of each entry
   parameter width = 8;
   
   // select implementation variant
   parameter fifo_type = `FIFO_TYPE_INDEXED;
   
   // include checker logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // width required for insertion pointer
   localparam insert_ptr_width = clogb(depth+1);
   
   // reset value for insertion pointer
   localparam [0:insert_ptr_width-1] insert_ptr_reset_value = depth;
   
   // width required for read/write pointers
   localparam rw_ptr_width = clogb(depth);
   
   input clk;
   input reset;
   
   // all entries occupied
   output full;
   wire full;
   
   // input data
   input [0:width-1] data_in;
   
   // write data from data_in into shift register
   input push;
   
   // no entries occupied
   output empty;
   wire empty;
   
   // output data (head element)
   output [0:width-1] data_out;
   wire [0:width-1] data_out;
   
   // remove head element from shift register
   input pop;
   
   // internal error condition detected
   output error;
   wire 	    error;
   
   genvar 	    level;
   
   generate
      
      case(fifo_type)
	`FIFO_TYPE_SHIFTING:
	  begin
	     
	     wire [0:insert_ptr_width-1] insert_ptr, insert_ptr_early,
					 insert_ptr_next, insert_ptr_prev;
	     mod_ctr
	       #(.num_values(depth),
		 .reset_type(reset_type),
		 .reset_value(insert_ptr_reset_value))
	     insert_ptr_ctr
	       (.clk(clk),
		.reset(reset),
		.incr(push),
		.decr(pop),
		.load(1'b0),
		.load_value({insert_ptr_width{1'b0}}),
		.value(insert_ptr),
		.early_value(insert_ptr_early),
		.next_value(insert_ptr_next),
		.prev_value(insert_ptr_prev));
	     
	     assign full = (insert_ptr == 0);
	     assign empty = (insert_ptr == depth);
	     
	     wire [0:(depth+1)*width-1] data;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:shifting_levels
		  
		  wire capture;
		  assign capture = push && (level + 1 == insert_ptr + pop);
		  
		  wire shift;
		  assign shift = pop;
		  
		  wire [0:width-1] data_s, data_q;
		  assign data_s = capture ?
				  data_in :
				  shift ?
				  data[level*width:(level+1)*width-1] :
				  data_q;
		  dff
		    #(.width(width),
		      .reset_type(reset_type))
		  dataq
		    (.clk(clk),
		     .reset(reset),
		     .d(data_s),
		     .q(data_q));
		  
		  assign data[(level+1)*width:(level+2)*width-1] = data_q;
		  
	       end
	     
	     assign data_out = data[depth*width:(depth+1)*width-1];
	     
	     wire 		   error_underflow;
	     assign error_underflow = empty & pop;
	     
	     wire 		   error_overflow;
	     assign error_overflow = full & push;
	     
	     wire [0:1] 	   errors_in, errors_out;
	     assign errors_in = {error_underflow,
				 error_overflow};
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
	     
	  end
	`FIFO_TYPE_INDEXED:
	  begin

	     wire [0:rw_ptr_width-1] read_ptr, write_ptr;
	     wire 		     empty_early, full_early;
	     fifo_ctrl
	       #(.depth(depth),
		 .checker_enable(checker_enable),
		 .checker_capture_mode(checker_capture_mode),
		 .reset_type(reset_type))
	     ctrl
	       (.clk(clk),
		.reset(reset),
		.push(push),
		.pop(pop),
		.write_addr(write_ptr),
		.read_addr(read_ptr),
		.empty(empty),
		.empty_early(empty_early),
		.full(full),
		.full_early(full_early),
		.error(error));
	     
	     wire [0:depth*width-1]  data;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:indexed_levels
		  
		  wire capture;
		  assign capture = push && (level == write_ptr);

		  wire [0:width-1] data_s, data_q;
		  assign data_s = capture ? data_in : data_q;
		  dff
		    #(.width(width),
		      .reset_type(reset_type))
		  dataq
		    (.clk(clk),
		     .reset(reset),
		     .d(data_s),
		     .q(data_q));
		  
		  assign data[level*width:(level+1)*width-1] = data_q;
		  
	       end
	     
	     mux_nto1
	       #(.num_ports(depth),
		 .width(width))
	     data_mux
	       (.select(read_ptr),
		.data_in(data),
		.data_out(data_out));
	     
	  end
      endcase
      
   endgenerate
   
endmodule
