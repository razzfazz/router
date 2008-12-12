module wf_alloc_core_rot
  (clk, reset, update, req, gnt);
   
   
`include "constants.v"
`include "functions.v"
   
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   parameter reset_type = reset_type_async;
   localparam port_width = clogb(num_ports);
   
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // requests
   input [0:num_ports*num_ports-1] req;
   
   // grants
   output wire [0:num_ports*num_ports-1] gnt;
   
   
   wire [0:num_ports*num_ports-1] 	 y;
   
   generate
      
      genvar 				 row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   wire [0:port_width-1] prio_s, prio_q;
	   if(2 ** port_width == num_ports)
	     begin
		// in this case, we have natural wraparound
		assign prio_s = update ? (prio_q - 1'b1) : prio_q;
	     end
	   else
	     begin
		// here we need explicit wraparound
		assign prio_s = update ?
				(~|prio_q ?
				 (num_ports - 1'b1) :
				 (prio_q - 1'b1)) :
				prio_q;
	     end
	   dff
	     #(.width(port_width),
	       .reset_type(reset_type),
	       .reset_value(num_ports-row-1))
	   prioq
	     (.clk(clk),
	      .reset(reset),
	      .d(prio_s),
	      .q(prio_q));
	   
	   wire [0:num_ports-1] 	req_row;
	   assign req_row = req[row*num_ports:(row+1)*num_ports-1];
	   
	   wire [0:num_ports-1] 	req_in;
	   
	   rotator
	     #(.width(num_ports),
	       .direction(0))
	   req_rot
	     (.data_in(req_row),
	      .select(prio_q),
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
	   
	   wire [0:num_ports-1] 	gnt_row;
	   
	   rotator
	     #(.width(num_ports),
	       .direction(1))
	   gnt_rot
	     (.data_in(gnt_out),
	      .select(prio_q),
	      .data_out(gnt_row));
	   
	   assign gnt[row*num_ports:(row+1)*num_ports-1] = gnt_row;
	   
	end
      
   endgenerate
   
endmodule
