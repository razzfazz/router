$Id$
// wavefron allocator variant which uses wraparound (forming a false 
// combinational loop) as described in Dally et al, "Principles and Practices of
// Interconnection Networks"
module wf_alloc_core_loop
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   // try to recover from errors
   parameter error_recovery = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // reset value for priority pointer
   localparam [0:num_ports-1] prio_init = {1'b1, {(num_ports-1){1'b0}}};
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // request matrix
   input [0:num_ports*num_ports-1] req;
   
   // grant matrix
   output [0:num_ports*num_ports-1] gnt;
   wire [0:num_ports*num_ports-1] gnt;
   
   // Need to make sure priority is one-hot, otherwise conflicting grants can be
   // generated!
   wire [0:num_ports-1] 	  prio_s, prio_q;
   wire 			  prio_bad;
   assign prio_bad = ~^prio_q;
   wire [0:num_ports-1] 	  prio_fixed;
   assign prio_fixed = (error_recovery && prio_bad) ? prio_init : prio_q;
   assign prio_s = update ?
		   {prio_fixed[num_ports-1], prio_fixed[0:num_ports-2]} :
		   prio_fixed;
   dff
     #(.width(num_ports),
       .reset_type(reset_type),
       .reset_value(prio_init))
   prioq
     (.clk(clk),
      .reset(reset),
      .d(prio_s),
      .q(prio_q));
   
   wire [0:num_ports*num_ports-1] x_pri;
   wire [0:num_ports*num_ports-1] y_pri;
   
   generate
      
      genvar 			  row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   genvar col;
	   for(col = 0; col < num_ports; col = col + 1)
	     begin:cols
		
		wire req_in;
		assign req_in = req[row*num_ports+col];
		
		wire x_pri_in;
		assign x_pri_in
		  = x_pri[row*num_ports + ((col+num_ports-1)%num_ports)] |
		    prio_q[(row+col)%num_ports];
		
		wire y_pri_in;
		assign y_pri_in
		  = y_pri[((row+num_ports-1)%num_ports)*num_ports + col] |
		    prio_q[(row+col)%num_ports];
		
		wire gnt_out;
		assign gnt_out = req_in & x_pri_in & y_pri_in;
		assign gnt[row*num_ports+col] = gnt_out;
		
		wire x_pri_out;
		assign x_pri_out = x_pri_in & ~gnt_out;
		assign x_pri[row*num_ports+col] = x_pri_out;
		
		wire y_pri_out;
		assign y_pri_out = y_pri_in & ~gnt_out;
		assign y_pri[row*num_ports+col] = y_pri_out;
		
	     end
	end
      
   endgenerate
   
endmodule
