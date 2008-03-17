module matrix_arbiter
  #(parameter num_ports = 32,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1)
   (input     clk,
    input     reset,
    input     update,
    input [0:num_ports-1] req,
    output wire [0:num_ports-1] gnt);
   
   wire [0:num_ports*num_ports-1] prio_s, prio_q;
   
   genvar 			  row, col;
   genvar 			  i;
   generate
      
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   for(col = 0; col < num_ports; col = col + 1)
	     begin:cols
		if(row < col)
		  begin
		     dff
		       #(.width(1),
			 .offset(col),
			 .reset_type(reset_type),
			 .reset_value(1'b1),
			 .hold_type(hold_type))
		     prioq
		       (.clk(clk),
			.reset(reset),
			.enable(update),
			.d(prio_s[row*num_ports+col]),
			.q(prio_q[row*num_ports+col]));
		  end
		else if(row == col)
		  assign prio_q[row*num_ports+col] = 1'b1;
		else
		  assign prio_q[row*num_ports+col] = ~prio_q[col*num_ports+row];

		if(hold_type == 1)
		  assign prio_s[row*num_ports+col]
			   = (prio_q[row*num_ports+col] | (gnt[col] & update)) &
			     !(gnt[row] & update);
		else if((hold_type == 0) || (hold_type == 2))
		  assign prio_s[row*num_ports+col]
			   = (prio_q[row*num_ports+col] | gnt[col]) & !gnt[row];
		
	     end
	end

      for(i = 0; i < num_ports; i = i + 1)
	begin:gnts
	   assign gnt[i] = req[i] & 
			   (&(prio_q[i*num_ports:(i+1)*num_ports-1] | ~req));
	end
      
   endgenerate
   
endmodule
