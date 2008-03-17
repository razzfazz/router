module rr_arbiter
  #(parameter num_ports = 32,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1)
   (input     clk,
    input     reset,
    input     update,
    input [0:num_ports-1] req,
    output wire [0:num_ports-1] gnt);
   
   wire [0:num_ports-1] 	req_rev;
   wire [0:num_ports-2] 	prev_q;
   
   wire [0:num_ports-1] 	gnt_unqual;
   assign gnt_unqual = req_rev & -req_rev;
   
   wire [0:num_ports-2] 	mask;
   assign mask = prev_q - {{num_ports-2{1'b0}}, 1'b1};
   
   wire [0:num_ports-2] 	req_qual;
   assign req_qual = req_rev[0:num_ports-2] & ~mask;
   
   wire [0:num_ports-2] 	gnt_qual;
   assign gnt_qual = req_qual & -req_qual;
   
   wire [0:num_ports-1] 	gnt_rev;
   assign gnt_rev = |req_qual ? {gnt_qual, 1'b0} : gnt_unqual;

   wire [0:num_ports-2] 	prev_s;

   generate   

      if(hold_type == 0)
	assign prev_s = update ? gnt_rev[1:num_ports-1] : prev_q;
      else if((hold_type == 1) || (hold_type == 2))
	assign prev_s = gnt_rev[1:num_ports-1];
      
      genvar 			i;
      for(i = 0; i < num_ports; i = i + 1)
	begin:connect
	   assign req_rev[i] = req[(num_ports-1)-i];
	   assign gnt[i] = gnt_rev[(num_ports-1)-i];
	end
      
      dff
	#(.width(num_ports-1),
	  .reset_type(reset_type),
	  .hold_type(hold_type))
      prevq
	(.clk(clk),
	 .reset(reset),
	 .enable(update),
	 .d(prev_s),
	 .q(prev_q));
   
   endgenerate
   
endmodule
