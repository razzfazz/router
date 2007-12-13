module wf_alloc_blk
  #(
    
    // number of input/output ports
    // each input can bid for any combination of outputs
    parameter num_ports = 8

    )
   (
    input [0:num_ports*num_ports-1] req,
    output [0:num_ports*num_ports-1] gnt
    );
   
   wire [0:num_ports*num_ports-1] y;
   
   genvar 			  row, col;
   
   generate

      for(row = 0; row < num_ports; row = row + 1)
	begin:rows

	   wire [0:num_ports-1] x_in, y_in;
	   wire [0:num_ports]   x_out, y_out;
	   wire [0:num_ports-1] req_in;
	   wire [0:num_ports-1] gnt_out;

	   assign x_in = x_out[0:num_ports-1];
	   assign y_in = y[((row+num_ports)%num_ports)*num_ports:
			   ((row+num_ports)%num_ports+1)*num_ports-1];
	   assign req_in = req[row*num_ports:(row+1)*num_ports-1];

	   assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
	   assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
	   assign gnt_out = req_in & x_in & y_in;
	   
	   assign y[((row+num_ports+1)%num_ports)*num_ports:
		    ((row+num_ports+1)%num_ports+1)*num_ports-1]
		    = y_out[0:num_ports-1];
	   assign gnt[row*num_ports:(row+1)*num_ports-1]
		    = gnt_out;
	   
	end
   endgenerate
   
endmodule
