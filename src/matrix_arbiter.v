// $Id$
// generic matrix arbiter
module matrix_arbiter
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of inputs ports
   parameter num_ports = 32;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // update port priorities
   input update;
   
   // request vector
   input [0:num_ports-1] req;
   
   // grant vector
   output [0:num_ports-1] gnt;
   wire [0:num_ports-1] gnt;
   
   // port priority matrix
   wire [0:num_ports*num_ports-1] prio;
   
   generate
      
      genvar 			  row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   // lower triangle has inverted values of transposed upper triangle
	   genvar col;
	   for(col = 0; col < row; col = col + 1)
	     begin:cols
		assign prio[row*num_ports+col] = ~prio[col*num_ports+row];
	     end
	   
	   // diagonal has all ones
	   assign prio[row*num_ports+row] = 1'b1;
	   
	   // upper triangle has actual registers
	   if(row < num_ports-1)
	     begin
		wire [(row+1):num_ports-1] prio_s, prio_q;
		assign prio_s
		  = update ?
		    (prio_q | gnt[(row+1):num_ports-1]) &
		    ~{(num_ports-row-1){gnt[row]}} :
		    prio_q;
		dff
		  #(.width(num_ports-row-1),
		    .offset(row+1),
		    .reset_type(reset_type),
		    .reset_value({(num_ports-row-1){1'b1}}))
		prioq
		  (.clk(clk),
		   .reset(reset),
		   .d(prio_s),
		   .q(prio_q));
		assign prio[row*num_ports+row+1:(row+1)*num_ports-1] = prio_q;
	     end
	   
	   // grant requests if we have priority over all other requestors
	   assign gnt[row]
		    = req[row] &
		      (&(prio[row*num_ports:(row+1)*num_ports-1] | ~req));
	   
	end
      
   endgenerate
   
endmodule
