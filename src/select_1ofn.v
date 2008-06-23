module select_1ofn
  (select, data_in, data_out);
   
   
   parameter width = 32;
   parameter num_ports = 4;
   
   
   input [0:num_ports-1] select;
   input [0:num_ports*width-1] data_in;
   output wire [0:width-1] data_out;
   
   
   generate
      
      genvar 		   i;
      for(i = 0; i < width; i = i + 1)
	begin:width_loop
	   
	   wire [0:num_ports-1] port_bits;
	   
	   genvar 		j;
	   for(j = 0; j < num_ports; j = j + 1)
	     begin:ports_loop
		assign port_bits[j] = data_in[i+j*width] & select[j];
	     end
	   
	   assign data_out[i] = |port_bits;
	   
	end
      
   endgenerate
   
endmodule
