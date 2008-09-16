module wf_alloc_core_mux
  (clk, reset, update, req, gnt);
   
   
`include "constants.v"
   
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   parameter [0:num_ports*num_ports-1] mask = {num_ports*num_ports{1'b1}};
   
   parameter reset_type = reset_type_async;
   
   parameter error_recovery = 0;
   
   localparam [0:num_ports-1] prio_init = {1'b1, {(num_ports-1){1'b0}}};
   
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // requests
   input [0:num_ports*num_ports-1] req;
   
   // grants
   output [0:num_ports*num_ports-1] gnt;
   
   wire [0:num_ports*num_ports-1] gnt;

   // Need to make sure this stays one-hot, as bit errors can lead to
   // conflicting grants being generated!
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
   
   wire [0:num_ports*num_ports-1] req_msk;
   assign req_msk = req & mask;
   
   wire [0:num_ports*num_ports-1] y;
   
   generate
      
      genvar 			  row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   wire [0:num_ports-1] x_in, y_in;
	   wire [0:num_ports] 	x_out, y_out;
	   
	   assign x_in = x_out[0:num_ports-1];
	   assign y_in = y[((row+num_ports)%num_ports)*num_ports:
			   ((row+num_ports)%num_ports+1)*num_ports-1];
	   
	   wire [0:num_ports-1] req_in;
	   
	   assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
	   assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
	   
	   wire [0:num_ports-1] gnt_out;
	   assign gnt_out = req_in & x_in & y_in;
	   
	   assign y[((row+num_ports+1)%num_ports)*num_ports:
		    ((row+num_ports+1)%num_ports+1)*num_ports-1]
		    = y_out[0:num_ports-1];
	   
	   wire [0:num_ports-1] gnt_row;
	   
	   assign gnt[row*num_ports:(row+1)*num_ports-1] = gnt_row;
	   
	   wire [0:num_ports-1] req_row;
	   assign req_row = req_msk[row*num_ports:(row+1)*num_ports-1];
	   
	   wire [0:2*num_ports-1] req_dup;
	   assign req_dup = {2{req_row}};
	   
	   wire [0:2*num_ports-1] gnt_dup;
	   
	   genvar 		  col;
	   for(col = 0; col < num_ports; col = col + 1)
	     begin:cols
		
		wire [0:num_ports-1] req_rot;
		assign req_rot
		  = req_dup[(col+num_ports-row)%num_ports:
			    (col+num_ports-row)%num_ports+num_ports-1];
		
		select_1ofn
		  #(.width(1),
		    .num_ports(num_ports))
		req_sel
		  (.select(prio_q),
		   .data_in(req_rot),
		   .data_out(req_in[col]));
		
		// need to reverse the grant vector
		assign gnt_dup[num_ports-col-1] = gnt_out[col];
		assign gnt_dup[2*num_ports-col-1] = gnt_out[col];
		
		wire [0:num_ports-1] gnt_rot;
		assign gnt_rot
		  = gnt_dup[(2*num_ports-row-col-1)%num_ports:
			    (2*num_ports-row-col-1)%num_ports+
			    num_ports-1];
		
		select_1ofn
		  #(.width(1),
		    .num_ports(num_ports))
		gnt_sel
		  (.select(prio_q),
		   .data_in(gnt_rot),
		   .data_out(gnt_row[col]));
		
	     end		
	end
      
   endgenerate
   
endmodule
