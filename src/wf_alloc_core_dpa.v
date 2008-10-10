// wavefron allocator variant implementing a Diagonal Propagation Arbiter as
// described in Hurt et al, "Design and Implementation of High-Speed Symmetric 
// Crossbar Schedulers"
module wf_alloc_core_dpa
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   // number of input/output ports
   // each input can bid for any combination of outputs
   parameter num_ports = 8;
   
   // try to recover from errors
   parameter error_recovery = 0;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   // reset value for priority pointer
   localparam [0:(2*num_ports-1)-1] prio_init
     = {{num_ports{1'b1}}, {(num_ports-1){1'b0}}};
   
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
   wire [0:(2*num_ports-1)-1] 	  prio_s, prio_q;
   wire 			  prio_bad;
   assign prio_bad = ^prio_q ^ ^prio_init;
   
   wire 			  reset_prio;
   assign reset_prio = ~|prio_q[0:(num_ports-1)-1] ||
		       (error_recovery && prio_bad);
   
   assign prio_s = update ?
		   (reset_prio ?
		    prio_init :
		    {1'b0, prio_q[0:(2*num_ports-1)-2]}) :
		   prio_q;
   dff
     #(.width(2*num_ports-1),
       .reset_type(reset_type),
       .reset_value(prio_init))
   prioq
     (.clk(clk),
      .reset(reset),
      .d(prio_s),
      .q(prio_q));
   
   wire [0:num_ports*(2*num_ports-2)-1] x;
   
   generate
      
      genvar 				col;
      for(col = 0; col < num_ports; col = col + 1)
	begin:cols
	   
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
			 = req[((num_ports-col+row)%num_ports)*num_ports + col];
		assign req_in[row+num_ports]
			 = req[((num_ports-col+row)%num_ports)*num_ports + col];
		assign gnt[((num_ports-col+row)%num_ports)*num_ports+col]
			 = gnt_out[row] | gnt_out[row+num_ports];
	     end
	   
	   assign req_in[num_ports-1]
		    = req[((2*num_ports-1-col)%num_ports)*num_ports+col];
	   assign gnt[((2*num_ports-1-col)%num_ports)*num_ports+col]
		    = gnt_out[num_ports-1];
	   
	end	     
      
   endgenerate
   
endmodule
