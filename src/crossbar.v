// confiurable crossbar module
module crossbar
  (ctrl_ip_op, data_ip, data_op);
   
`include "constants.v"
   
   // number of input/output ports
   parameter num_ports = 5;
   
   // width per port
   parameter width = 32;
   
   // select implementation variant
   parameter crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // control signals (request matrix)
   input [0:num_ports*num_ports-1] ctrl_ip_op;
   
   // vector of input data
   input [0:num_ports*width-1] data_ip;
   
   // vector of output data
   output [0:num_ports*width-1] data_op;
   wire [0:num_ports*width-1] data_op;
   
   wire [0:num_ports*num_ports-1] ctrl_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   ctrl_intl
     (.data_in(ctrl_ip_op),
      .data_out(ctrl_op_ip));
   
   generate
      
      genvar 			  op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:width-1] out;
	   
	   case(crossbar_type)
	     `CROSSBAR_TYPE_TRISTATE:
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
	     `CROSSBAR_TYPE_MUX:
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
