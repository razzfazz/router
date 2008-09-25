module wf_alloc_base
  (req_ip_op, gnt_ip_op);
   
   
   parameter num_ports = 8;
   
   parameter [0:num_ports*num_ports-1] mask = {num_ports*num_ports{1'b1}};
   
   
   input [0:num_ports*num_ports-1] req_ip_op;
   
   output [0:num_ports*num_ports-1] gnt_ip_op;
   
   wire [0:num_ports*num_ports-1] gnt_ip_op;
   
   wire [0:num_ports*num_ports-1] x_pri_out_ip_op;
   wire [0:num_ports*num_ports-1] y_pri_out_ip_op;
   
   generate
      
      genvar 				 row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   genvar col;
	   for(col = 0; col < num_ports; col = col + 1)
	     begin:cols

		if(col == 0)
		  begin
		     if(ignore_same_port && (row == 0))
		       begin
			  assign x_pri_out_ip_op[0] = 1'b1;
			  assign y_pri_out_ip_op[0] = 1'b1;
			  assign gnt_ip_op[0] = 1'b0;
		       end
		     else
		       begin
			  assign x_pri_out_ip_op[row*num_ports]
				   = ~req_ip_op[row*num_ports];
			  assign y_pri_out_ip_op[row*num_ports]
				   = ~req_ip_op[row*num_ports];
			  assign gnt_ip_op[row*num_ports]
				   = req_ip_op[row*num_ports];
		       end
		  end
		else
		  begin
		     if(ignore_same_port && (row == col))
		       begin
			  assign x_pri_out_ip_op[row*num_ports+col]
				   = x_pri_out_ip_op[row*num_ports+col-1];
			  assign y_pri_out_ip_op[row*num_ports+col]
				   = y_pri_out_ip_op[((row+num_ports-1)%
						      num_ports)*num_ports+
						     col-1];
		       end
		     else
		       begin
			  wire x_in;
			  assign x_in
			    = x_pri_out_ip_op[row*num_ports+col-1];
			  
			  wire y_in;
			  assign y_in
			    = y_pri_out_ip_op[((row+num_ports-1)%num_ports)*
					      num_ports+col-1];
			  
			  wire gnt_b;
			  if(row == col)
			    assign gnt_b = ~(req_ip_op[row*num_ports+col] &
					     x_in & y_in);
			  else
			    assign gnt_b = 1'b1;
			  
			  assign gnt_ip_op[row*num_ports+col] = ~gnt_b;
			  
			  assign x_pri_out_ip_op[row*num_ports+col]
				   = x_in & gnt_b;
			  assign y_pri_out_ip_op[row*num_ports+col]
				   = y_in & gnt_b;
			  
		       end
		  end
		
	     end
	   
	end
      
   endgenerate
   
endmodule
