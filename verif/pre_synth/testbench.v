module testbench
  #(
    parameter Tclk = 6,
    parameter width = 4,
    parameter mean_delay = 10)
   ();
   
   function integer pop_count(input [0:width-1] x);
      integer i;
      begin
	 pop_count = 0;
	 for(i = 0; i < width; i = i + 1)
	   begin
              pop_count = pop_count + x[i];
	   end
      end
   endfunction
   
   wire [0:width-1] req_rr;
   wire [0:width-1] req_matrix;
   wire [0:width-1] gnt_rr;
   wire [0:width-1] gnt_matrix;
   
   reg 		    reset;
   reg 		    clk;
   wire 	    update = 1'b1;
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   rr_arbiter #(.width(width)) arb_rr(.clk(clk),
				      .reset(reset),
				      .update(update),
				      .req(req_rr),
				      .gnt(gnt_rr));
   matrix_arbiter #(.width(width)) arb_matrix(.clk(clk),
					      .reset(reset),
					      .update(update),
					      .req(req_matrix), 
					      .gnt(gnt_matrix));
   
   wire error_rr = (pop_count(gnt_rr) > 1) || 
        (|(req_rr)) & ~(|(req_rr & gnt_rr));
   wire error_matrix = (pop_count(gnt_matrix) > 1) || 
        (|(req_matrix)) & ~(|(req_matrix & gnt_matrix));
   wire error = error_rr | error_matrix;
   
   wire error_q;
   wire error_s = (error_q & ~reset) | error;
   dff #(.width(1)) error_ff(.clk(clk), .d(error_s), .q(error_q));
   
   genvar i;
   generate
      for(i = 0; i < width; i = i + 1)
	begin:rr_drvs
	   driver #(.mean_delay(mean_delay), .initial_seed(i))
	   drv(.clk(clk), .reset(reset), .gnt(gnt_rr[i]), .req(req_rr[i]));
	end
      for(i = 0; i < width; i = i + 1)
	begin:matrix_drvs
	   driver #(.mean_delay(mean_delay), .initial_seed(i))
	   drv(.clk(clk), .reset(reset), .gnt(gnt_matrix[i]),
	       .req(req_matrix[i]));
	end
   endgenerate

   initial
   begin
      
      reset = 0'b1;
      
      #(2*Tclk)
      
      reset = 0'b0;
      
      #(1000000*Tclk);
      
      $finish;
      
   end
   
endmodule
