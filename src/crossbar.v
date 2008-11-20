// $Id$
// configurable crossbar module
module crossbar
  (ctrl_ip_op, data_in_ip, data_out_op);
   
`include "constants.v"
   
   // number of input/output ports
   parameter num_in_ports = 5;
   parameter num_out_ports = 5;
   
   // width per port
   parameter width = 32;
   
   // select implementation variant
   parameter crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // control signals (request matrix)
   input [0:num_in_ports*num_out_ports-1] ctrl_ip_op;
   
   // vector of input data
   input [0:num_in_ports*width-1] data_in_ip;
   
   // vector of output data
   output [0:num_out_ports*width-1] data_out_op;
   wire [0:num_out_ports*width-1] data_out_op;
   
   wire [0:num_out_ports*num_in_ports-1] ctrl_op_ip;
   interleaver
     #(.width(num_in_ports*num_out_ports),
       .num_blocks(num_in_ports))
   ctrl_intl
     (.data_in(ctrl_ip_op),
      .data_out(ctrl_op_ip));
   
   generate
      
      genvar 				 op;
      for(op = 0; op < num_out_ports; op = op + 1)
	begin:ops
	   
	   wire [0:width-1] data_out;
	   
	   case(crossbar_type)
	     
	     `CROSSBAR_TYPE_TRISTATE:
	       begin
		  
		  genvar ip;
		  for(ip = 0; ip < num_in_ports; ip = ip + 1)
		    begin:ips
		       
		       wire [0:width-1] in;
		       assign in = data_in_ip[ip*width:(ip+1)*width-1];
		       
		       wire 		ctrl;
		       assign ctrl = ctrl_op_ip[op*num_in_ports+ip];
		       
		       assign data_out = ctrl ? in : {width{1'bz}};
		       
		    end
		  
	       end
	     
	     `CROSSBAR_TYPE_MUX:
	       begin
		  
		  wire [0:num_in_ports-1] ctrl_ip;
		  assign ctrl_ip
		    = ctrl_op_ip[op*num_in_ports:(op+1)*num_in_ports-1];
		  
		  select_1ofn
		    #(.width(width),
		      .num_ports(num_in_ports))
		  out_mux
		    (.select(ctrl_ip),
		     .data_in(data_in_ip),
		     .data_out(data_out));
		  
	       end
	     
	   endcase
	   
	   assign data_out_op[op*width:(op+1)*width-1] = data_out;
	   
	end
      
   endgenerate
   
endmodule
