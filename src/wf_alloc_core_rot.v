// $Id$
// wavefront allocator variant which rotates inputs and outputs based on 
// priority
module wf_alloc_core_rot
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   // try to recover from errors
   parameter error_recovery = 0; // FIXME: actually implement this
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   localparam prio_width = clogb(num_ports);
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // request matrix
   input [0:num_ports*num_ports-1] req;
   
   // grant matrix
   output [0:num_ports*num_ports-1] gnt;
   wire [0:num_ports*num_ports-1] gnt;
   
   wire [0:num_ports*num_ports-1] y;
   
   wire [0:prio_width-1] 	  prio_next, prio_q;
   incr
     #(.width(prio_width),
       .min_value(0),
       .max_value(num_ports-1))
   prio_incr
     (.data_in(prio_q),
      .data_out(prio_next));
   
   wire [0:prio_width-1] 	  prio_s;
   assign prio_s = update ? prio_next : prio_q;
   dff
     #(.width(prio_width),
       .reset_type(reset_type))
   prioq
     (.clk(clk),
      .reset(reset),
      .d(prio_s),
      .q(prio_q));
   
   generate
      
      genvar 			  row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   wire [0:num_ports-1] 	req_row;
	   assign req_row = req[row*num_ports:(row+1)*num_ports-1];
	   
	   wire [0:prio_width-1] 	current_row;
	   assign current_row = row;
	   
	   wire [0:num_ports-1] 	req_tmp;
	   rotator
	     #(.width(num_ports),
	       .rotate_dir(`ROTATE_DIR_RIGHT))
	   req_tmp_rot
	     (.amount(current_row),
	      .data_in(req_row),
	      .data_out(req_tmp));
	   
	   wire [0:num_ports-1] 	req_in;
	   rotator
	     #(.width(num_ports),
	       .rotate_dir(`ROTATE_DIR_LEFT))
	   req_in_rot
	     (.amount(prio_q),
	      .data_in(req_tmp),
	      .data_out(req_in));
	   
	   wire [0:num_ports-1] 	x_in, y_in;
	   wire [0:num_ports] 		x_out, y_out;
	   
	   assign x_in = x_out[0:num_ports-1];
	   assign y_in = y[((row+num_ports)%num_ports)*num_ports:
			   ((row+num_ports)%num_ports+1)*num_ports-1];
	   
	   assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
	   assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
	   
	   wire [0:num_ports-1] 	gnt_out;
	   assign gnt_out = req_in & x_in & y_in;
	   
	   assign y[((row+num_ports+1)%num_ports)*num_ports:
		    ((row+num_ports+1)%num_ports+1)*num_ports-1]
		    = y_out[0:num_ports-1];
	   
	   wire [0:num_ports-1] 	gnt_tmp;
	   rotator
	     #(.width(num_ports),
	       .rotate_dir(`ROTATE_DIR_RIGHT))
	   gnt_tmp_rot
	     (.amount(prio_q),
	      .data_in(gnt_out),
	      .data_out(gnt_tmp));
	   
	   wire [0:num_ports-1] 	gnt_row;
	   rotator
	     #(.width(num_ports),
	       .rotate_dir(`ROTATE_DIR_LEFT))
	   gnt_row_rot
	     (.amount(current_row),
	      .data_in(gnt_tmp),
	      .data_out(gnt_row));
	   
	   assign gnt[row*num_ports:(row+1)*num_ports-1] = gnt_row;
	   
	end
      
   endgenerate
   
endmodule
