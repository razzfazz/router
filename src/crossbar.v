module crossbar
  #(parameter num_ports = 5,
    parameter width = 32,
    parameter use_muxes = 0)
   (
    // [sort order: input port,bits]
    input [0:num_ports*width-1] data_in,
    
    // [sort order: input port,output port]
    input [0:num_ports*num_ports-1] ctrl_in,
    
    // [sort order: output port,bits]
    output [0:num_ports*width-1] data_out);

   genvar i;

   wire [0:num_ports*num_ports-1] ctrl_op_ip;

   interleaver
     #(.width(num_ports),
       .num_blocks(num_ports))
   ctrl_intl
     (.data_in(ctrl_in),
      .data_out(ctrl_op_ip));

   generate	   
      for(i = 0; i < num_ports; i = i + 1)
	begin:output_ports
	
	   wire [0:width-1] out;

	   if(use_muxes)
	     begin
		
		wire [0:num_ports-1] ctrl;

		assign ctrl = ctrl_op_ip[i*num_ports:(i+1)*num_ports-1];
	   
		select_1ofn
		  #(.width(width),
		    .num_ports(num_ports))
		out_mux
		  (.select(ctrl),
		   .data_in(data_in),
		   .data_out(out));
		
	     end
	   else
	     begin

		genvar j;
		
		for(j = 0; j < num_ports; j = j + 1)
		  begin:input_ports
		     
		     wire [0:width-1] in;

		     assign in = data_in[j*width:(j+1)*width-1];

		     wire ctrl;

		     assign ctrl = ctrl_op_ip[i*num_ports+j];
		     
		     assign out = ctrl ? in : {width{1'bz}};

		  end

	     end

	   assign data_out[i*width:(i+1)*width-1] = out;
	   
	end
   endgenerate
   
endmodule