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

   wire [0:width*width-1] req;
   wire [0:width*width-1] gnt;
   
   wf_alloc #(.num_ports(4)) wfa(.clk(clk),
				 .reset(reset),
				 .update(update),
				 .req(req),
				 .gnt(gnt));
   
   genvar i;
   generate
      for(i = 0; i < width; i = i + 1)
	begin:drvs
	   wire [0:width-1] drv_req;
	   wire [0:width-1] drv_gnt = gnt[i*width:(i+1)*width-1];
	   
	   driver #(.mean_delay(mean_delay), .initial_seed(i), .width(width))
	   drv(.clk(clk), .reset(reset), .gnt(drv_gnt), .req(drv_req));

	   assign req[i*width:(i+1)*width-1] = drv_req;
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
