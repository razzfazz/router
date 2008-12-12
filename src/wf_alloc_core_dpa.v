module wf_alloc_core_dpa
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   parameter [0:num_ports*num_ports-1] mask = {num_ports*num_ports{1'b1}};
   
   parameter reset_type = reset_type_async;
   
   
   input clk;
   input reset;
   
   // update arbitration priorities
   input update;
   
   // requests
   input [0:num_ports*num_ports-1] req;
   
   // grants
   output [0:num_ports*num_ports-1] gnt;
   
   wire [0:num_ports*num_ports-1] gnt;
   
   wire [0:(2*num_ports-1)-1] 	  prio_s, prio_q;
   
   wire 			  reset_prio;
   assign reset_prio = ~|prio_q[num_ports:(2*num_ports-1)-1];
   
   assign prio_s = update ?
		   reset_prio ?
		   {{(num_ports-1){1'b0}}, {num_ports{1'b1}}} :
		   {prio_q[1:(2*num_ports-1)-1], 1'b0} :
		   prio_q;
   dff
     #(.width(2*num_ports-1),
       .reset_type(reset_type),
       .reset_value({{(num_ports-1){1'b0}}, {num_ports{1'b1}}}))
   prioq
     (.clk(clk),
      .reset(reset),
      .d(prio_s),
      .q(prio_q));
   
   wire [0:num_ports*(2*num_ports-2)-1] x;
   wire [0:num_ports*num_ports-1] 	req_msk;
   
   generate
      
      genvar 				col;
      for(col = 0; col < num_ports; col = col + 1)
	begin:cols
	   
	   assign req_msk[col*num_ports:(col+1)*num_ports-1]
		    = req[col*num_ports:(col+1)*num_ports-1] &
		      mask[col*num_ports:(col+1)*num_ports-1];
	   
	   wire [0:(2*num_ports-1)-1] x_in, y_in;
	   wire [0:(2*num_ports-1)-1] x_out, y_out;
	   wire [0:(2*num_ports-1)-1] req_in;
	   wire [0:(2*num_ports-1)-1] gnt_out;
	   
	   assign x_in = {1'b1, x[col*(2*num_ports-2):
				  (col+1)*(2*num_ports-2)-1]};
	   assign y_in = {1'b1, y_out[0:(2*num_ports-2)-1]};
	   assign x_out = (x_in & ~(y_in & req_in)) | ~prio_q;
	   assign y_out = (y_in & ~(x_in & req_in)) | ~prio_q;
	   assign gnt_out = req_in & x_in & y_in & prio_q;
	   assign x[((col+1)%num_ports)*(2*num_ports-2):
		    ((col+1)%num_ports+1)*(2*num_ports-2)-1]
		    = x_out[0:(2*num_ports-2)-1];
	   
	   genvar 		      row;
	   for(row = 0; row < num_ports-1; row = row + 1)
	     begin:rows
		
		assign req_in[row]
			 = req_msk[((num_ports-col+row)%num_ports)*
				   num_ports + col];
		assign req_in[row+num_ports]
			 = req_msk[((num_ports-col+row)%num_ports)*
				   num_ports + col];
		assign gnt[((num_ports-col+row)%num_ports)*num_ports+col]
			 = gnt_out[row] | gnt_out[row+num_ports];
	     end
	   
	   assign req_in[num_ports-1]
		    = req_msk[((2*num_ports-1-col)%num_ports)*num_ports+col];
	   assign gnt[((2*num_ports-1-col)%num_ports)*num_ports+col]
		    = gnt_out[num_ports-1];
	   
	end	     
      
   endgenerate
   
endmodule
