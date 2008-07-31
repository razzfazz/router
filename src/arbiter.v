module arbiter
  (clk, reset, update, req, gnt);
   
`include "constants.v"
   
   parameter num_ports = 32;
   
   parameter reset_type = reset_type_async;
   
   /*
    0: round-robin arbiter
    1: matrix arbiter
    */
   parameter arbiter_type = 0;
   
   parameter [0:num_ports-1] mask = {num_ports{1'b1}};
   
   function integer pop_count(input [0:num_ports-1] arg);
      integer i;
      begin
	 pop_count = 0;
	 for(i = 0; i < num_ports; i = i + 1)
	   pop_count = pop_count + arg[i];
      end
   endfunction
   
   localparam width = pop_count(mask);
   
   
   input clk;
   input reset;
   input update;
   input [0:num_ports-1] req;
   
   output [0:num_ports-1] gnt;
   
   wire [0:num_ports-1] gnt;
   
   generate

      if(width > 1)
	begin
	   wire [0:width-1] 	req_int;
	   
	   if(width < num_ports)
	     begin
		extractor
		  #(.width(num_ports),
		    .mask(mask))
		req_int_extr
		  (.data_in(req),
		   .data_out(req_int));
	     end
	   else
	     begin
		assign req_int = req;
	     end
	   
	   wire [0:width-1] 	gnt_int;
	   
	   case(arbiter_type)
	     0:
	       begin
		  rr_arbiter
		    #(.num_ports(width),
		      .reset_type(reset_type))
		  arb
		    (.clk(clk),
		     .reset(reset),
		     .update(update),
		     .req(req_int),
		     .gnt(gnt_int));
	       end
	     1:
	       begin
		  matrix_arbiter
		    #(.num_ports(width),
		      .reset_type(reset_type))
		  arb
		    (.clk(clk),
		     .reset(reset),
		     .update(update),
		     .req(req_int),
		     .gnt(gnt_int));
	       end
	   endcase
	   
	   if(width < num_ports)
	     begin
		spreader
		  #(.width(num_ports),
		    .mask(mask))
		gnt_sprd
		  (.data_in(gnt_int),
		   .data_out(gnt));
	     end
	   else
	     begin
		assign gnt = gnt_int;
	     end
	end
      else
	begin
	   assign gnt = req & mask;
	end
      
   endgenerate
   
endmodule
