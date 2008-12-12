module wf_alloc_base
  (req, gnt);
   
   
   parameter num_ports = 8;
   
   
   input [0:num_ports*num_ports-1] req;
   output wire [0:num_ports*num_ports-1] gnt;
   
   
   wire [0:num_ports*(num_ports-1)-1] 	 x_pri;
   wire [0:num_ports*(num_ports-1)-1] 	 y_pri;
   
   generate
      
      genvar 				 row;
      for(row = 0; row < num_ports; row = row + 1)
	begin:rows
	   
	   assign x_pri[row*(num_ports-1)] = ~req[row*num_ports];
	   assign y_pri[row*(num_ports-1)] = ~req[row*num_ports];
	   assign gnt[row*num_ports] = req[row*num_ports];
	   
	   genvar col;
	   for(col = 1; col < num_ports; col = col + 1)
	     begin:cols
		
		wire x_in;
		assign x_in
		  = x_pri[row*(num_ports-1)+col-1];
		
		wire y_in;
		assign y_in
		  = y_pri[((row+num_ports-1)%num_ports)*(num_ports-1)+col-1];
		
		wire gnt_b;
		assign gnt_b
		  = ~(req[row*num_ports+col] & x_in & y_in);
		
		assign gnt[row*num_ports+col] = ~gnt_b;
		
		if(col < num_ports-1)
		  begin
		     assign x_pri[row*(num_ports-1)+col] = x_in & gnt_b;
		     assign y_pri[row*(num_ports-1)+col] = y_in & gnt_b;
		  end
		
	     end
	   
	end
      
   endgenerate
   
endmodule
