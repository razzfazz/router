module wf_alloc_core_rep
  (clk, reset, update, req, gnt);
   
   
`include "constants.v"
   
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   parameter reset_type = reset_type_async;
   
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // requests
   input [0:num_ports*num_ports-1] req;
   
   // grants
   output wire [0:num_ports*num_ports-1] gnt;
   
   
   wire [0:num_ports-1] 		 prio_s, prio_q;
   
   assign prio_s = update ? {prio_q[1:num_ports-1], prio_q[0]} : prio_q;
   dff
     #(.width(num_ports),
       .reset_type(reset_type),
       .reset_value({{(num_ports-1){1'b0}}, 1'b1}))
   prioq
     (.clk(clk),
      .reset(reset),
      .d(prio_s),
      .q(prio_q));
   
   wire [0:num_ports*num_ports*num_ports-1] gnt_by_prio;
   
   generate
      
      genvar 				    prio;
      for(prio = 0; prio < num_ports; prio = prio + 1)
	begin:prios
	   
	   wire [0:num_ports*num_ports-1] req_int;
	   wire [0:num_ports*num_ports-1] gnt_int;
	   wire [0:num_ports*num_ports-1] y;
	   
	   genvar 			  row;		
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:rows
		
		wire [0:num_ports-1] x_in, y_in;
		wire [0:num_ports]   x_out, y_out;
		wire [0:num_ports-1] req_in;
		wire [0:num_ports-1] gnt_out;
		
		assign x_in = x_out[0:num_ports-1];
		assign y_in
		  = y[((row+num_ports)%num_ports)*num_ports:
		      ((row+num_ports)%num_ports+1)*num_ports-1];
		assign req_in = req_int[row*num_ports:
					(row+1)*num_ports-1];
		
		assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
		assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
		assign gnt_out = req_in & x_in & y_in;
		
		assign y[((row+num_ports+1)%num_ports)*num_ports:
			 ((row+num_ports+1)%num_ports+1)*num_ports-1]
			 = y_out[0:num_ports-1];
		assign gnt_int[row*num_ports:(row+1)*num_ports-1]
			 = gnt_out;
		
		genvar 		     col;
		for(col = 0; col < num_ports; col = col + 1)
		  begin:cols
		     
		     assign req_int[row*num_ports+col] 
			      = req[((prio+row)%num_ports)*num_ports +
				    (num_ports-row+col)%num_ports];
		     assign gnt_by_prio[((prio+row)%num_ports)*
					num_ports +
					(num_ports-row+col)%num_ports +
					prio*num_ports*num_ports]
			      = gnt_int[row*num_ports+col];
		     
		  end
	     end
	end
      
   endgenerate
   
   select_1ofn
     #(.width(num_ports*num_ports),
       .num_ports(num_ports))
   gnt_sel
     (.select(prio_q),
      .data_in(gnt_by_prio),
      .data_out(gnt));
   
endmodule
