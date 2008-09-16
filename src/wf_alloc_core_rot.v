module wf_alloc_core_rot
  (clk, reset, update, req, gnt);
   
   
`include "constants.v"
`include "functions.v"
   
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   parameter [0:num_ports*num_ports-1] mask = {num_ports*num_ports{1'b1}};
   
   parameter reset_type = reset_type_async;
   
   parameter error_recovery = 0;
   
   localparam prio_width = clogb(num_ports);
   
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // requests
   input [0:num_ports*num_ports-1] req;
   
   // grants
   output [0:num_ports*num_ports-1] gnt;
   
   wire [0:num_ports*num_ports-1] gnt;
   
   wire [0:num_ports*num_ports-1] y;
   
   wire [0:num_ports*num_ports-1] req_msk;
   assign req_msk = req & mask;
   
   wire [0:prio_width-1] 	  current_prio;
   wire [0:prio_width-1] 	  next_prio;
   mod_ctr
     #(.num_values(num_ports),
       .reset_type(reset_type))
   prio_ctr
     (.clk(clk),
      .reset(reset),
      .incr(update),
      .value(current_prio),
      .next_value(next_prio));
   
   generate
      
      genvar 			  row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   wire [0:num_ports-1] 	req_row;
	   assign req_row = req_msk[row*num_ports:(row+1)*num_ports-1];
	   
	   wire [0:prio_width-1] 	current_row;
	   assign current_row = row;
	   
	   wire [0:num_ports-1] 	req_tmp;
	   rotator
	     #(.width(num_ports),
	       .direction(1))
	   req_tmp_rot
	     (.amount(current_row),
	      .data_in(req_row),
	      .data_out(req_tmp));
	   
	   wire [0:num_ports-1] 	req_in;
	   rotator
	     #(.width(num_ports),
	       .direction(0))
	   req_in_rot
	     (.amount(current_prio),
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
	       .direction(1))
	   gnt_tmp_rot
	     (.amount(current_prio),
	      .data_in(gnt_out),
	      .data_out(gnt_tmp));
	   
	   wire [0:num_ports-1] 	gnt_row;
	   rotator
	     #(.width(num_ports),
	       .direction(0))
	   gnt_row_rot
	     (.amount(current_row),
	      .data_in(gnt_tmp),
	      .data_out(gnt_row));
	   
	   assign gnt[row*num_ports:(row+1)*num_ports-1] = gnt_row;
	   
	end
      
   endgenerate
   
endmodule
