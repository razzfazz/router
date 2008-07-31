module crossbar
  (ctrl_ip_op, data_ip, data_op);
   
   
   parameter num_ports = 5;
   parameter width = 32;
   
   /*
    0: use tristate buses
    1: use multiplexers
    */
   parameter crossbar_type = 0;
   
   
   input [0:num_ports*num_ports-1] ctrl_ip_op;
   input [0:num_ports*width-1] data_ip;
   output wire [0:num_ports*width-1] data_op;
   
   
   wire [0:num_ports*num_ports-1]  ctrl_op_ip;
   interleaver
     #(.width(num_ports),
       .num_blocks(num_ports))
   ctrl_intl
     (.data_in(ctrl_ip_op),
      .data_out(ctrl_op_ip));
   
   generate
      
      genvar 			   op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:width-1] out;
	   
	   case(crossbar_type)
	     0:
	       begin
		  
		  genvar ip;
		  for(ip = 0; ip < num_ports; ip = ip + 1)
		    begin:ips
		       
		       wire [0:width-1] in;
		       assign in = data_ip[ip*width:(ip+1)*width-1];
		       
		       wire 		ctrl;
		       assign ctrl = ctrl_op_ip[op*num_ports+ip];
		       
		       assign out = ctrl ? in : {width{1'bz}};
		       
		    end
		  
	       end
	     1:
	       begin
		  
		  wire [0:num_ports-1] ctrl;
		  assign ctrl = ctrl_op_ip[op*num_ports:(op+1)*num_ports-1];
		  
		  select_1ofn
		    #(.width(width),
		      .num_ports(num_ports))
		  out_mux
		    (.select(ctrl),
		     .data_in(data_ip),
		     .data_out(out));
		  
	       end
	   endcase
	   
	   assign data_op[op*width:(op+1)*width-1] = out;
	   
	end
      
   endgenerate
   
endmodule
