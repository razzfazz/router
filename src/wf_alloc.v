module wf_alloc
  #(// number of input/output ports
    // each input can bid for any combination of outputs
    parameter num_ports = 8,
    
    // enable clock gating?
    parameter use_clock_gating = 1,

    /* supported architectures:
     0: rotate inputs based on priority
     1: replicate logic for priorities */
    parameter use_architecture = 0)
   (input     clk,
    input     reset,

    // update arbitration priorities
    input     update,

    // requests
    // [sort order: input port,output port]
    input [0:num_ports*num_ports-1] req,

    // grants
    // [sort order: input port,output port]
    output [0:num_ports*num_ports-1] gnt);

   wire 				    clk_gated;
   
   wire [0:num_ports-1] 		    prio_s, prio_q;
   
   assign prio_s = {prio_q[num_ports-1], prio_q[0:num_ports-2]};
   
   generate
      
      // generate gated clocks
      if(use_clock_gating)
	begin
	   
	   wire act;
		
	   assign act = update;
		
	   clkgate clk_gate_blk
	     (.clk(clk),
	      .act(act),
	      .clk_gated(clk_gated));
		
	   dff
	     #(.width(num_ports),
	       .reset_type(1),
	       .reset_value({1'b1, {(num_ports-1){1'b0}}}))
	   prioq
	     (.clk(clk_gated),
	      .reset(reset),
	      .d(prio_s),
	      .q(prio_q));
   	end
      else
	begin
	   assign clk_gated = clk;

	   dff
	     #(.width(num_ports),
	       .reset_type(1),
	       .reset_value({1'b1, {(num_ports-1){1'b0}}}),
	       .use_enable(1))
	   prioq
	     (.clk(clk_gated),
	      .reset(reset),
	      .enable(update),
	      .d(prio_s),
	      .q(prio_q));
	end

   endgenerate

   generate

      if(use_architecture == 0)
	begin

	   // [sort order: input port,output port]
	   wire [0:num_ports*num_ports-1] y;

	   genvar 			  row;
	   
	   for(row = 0; row < num_ports; row = row + 1)
	     begin:rows
		
		wire [0:num_ports-1] x_in, y_in;
		wire [0:num_ports]   x_out, y_out;
		
		assign x_in = x_out[0:num_ports-1];
		assign y_in = y[((row+num_ports)%num_ports)*num_ports:
				((row+num_ports)%num_ports+1)*num_ports-1];
		
		wire [0:num_ports-1] req_in;
		
		assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
		assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
		
		wire [0:num_ports-1] gnt_out;
		
		assign gnt_out = req_in & x_in & y_in;
		
		assign y[((row+num_ports+1)%num_ports)*num_ports:
			 ((row+num_ports+1)%num_ports+1)*num_ports-1]
			 = y_out[0:num_ports-1];
		
		wire [0:num_ports-1] gnt_row;
		
		assign gnt[row*num_ports:(row+1)*num_ports-1] = gnt_row;
		
		wire [0:num_ports-1] req_row;
		
		assign req_row = req[row*num_ports:(row+1)*num_ports-1];
		
		wire [0:2*num_ports-1] req_dup;
		
		assign req_dup = {2{req_row}};
		
		wire [0:2*num_ports-1] gnt_dup;
		
		genvar 		       col;
		
		for(col = 0; col < num_ports; col = col + 1)
		  begin:cols
		     
		     wire [0:num_ports-1] req_rot;
		     
		     assign req_rot
		       = req_dup[(col+num_ports-row)%num_ports:
				 (col+num_ports-row)%num_ports+num_ports-1];
		     
		     select_1ofn
		       #(.width(1),
			 .num_ports(num_ports))
		     req_sel
		       (.select(prio_q),
			.data_in(req_rot),
			.data_out(req_in[col]));
		     
		     // need to reverse the grant vector
		     assign gnt_dup[num_ports-col-1] = gnt_out[col];
		     assign gnt_dup[2*num_ports-col-1] = gnt_out[col];
		     
		     wire [0:num_ports-1] gnt_rot;
		     
		     assign gnt_rot
		       = gnt_dup[(2*num_ports-row-col-1)%num_ports:
				 (2*num_ports-row-col-1)%num_ports+num_ports-1];
		     
		     select_1ofn
		       #(.width(1),
			 .num_ports(num_ports))
		     gnt_sel
		       (.select(prio_q),
			.data_in(gnt_rot),
			.data_out(gnt_row[col]));
		     
		  end		
	     end
	end
    else if(use_architecture == 1)
	begin

	   // [sort order: input port,output port,priority group]
	   wire [0:num_ports*num_ports*num_ports-1] gnt_by_prio;

	   genvar 				    prio;
	   
	   for(prio = 0; prio < num_ports; prio = prio + 1)
	     begin:prios
		
		// [sort order: input port,output port]
		wire [0:num_ports*num_ports-1] req_int;
		wire [0:num_ports*num_ports-1] gnt_int;
		wire [0:num_ports*num_ports-1] y;

		genvar 			       row;
		
		for(row = 0; row < num_ports; row = row + 1)
		  begin:rows
		     
		     wire [0:num_ports-1] x_in, y_in;
		     wire [0:num_ports]   x_out, y_out;
		     wire [0:num_ports-1] req_in;
		     wire [0:num_ports-1] gnt_out;
		     
		     assign x_in = x_out[0:num_ports-1];
		     assign y_in = y[((row+num_ports)%num_ports)*num_ports:
				     ((row+num_ports)%num_ports+1)*num_ports-1];
		     assign req_in = req_int[row*num_ports:(row+1)*num_ports-1];
		     
		     assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
		     assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
		     assign gnt_out = req_in & x_in & y_in;
		     
		     assign y[((row+num_ports+1)%num_ports)*num_ports:
			      ((row+num_ports+1)%num_ports+1)*num_ports-1]
			      = y_out[0:num_ports-1];
		     assign gnt_int[row*num_ports:(row+1)*num_ports-1]
			      = gnt_out;
		
		     genvar 		  col;
		     
		     for(col = 0; col < num_ports; col = col + 1)
		       begin:cols
			  
			  assign req_int[row*num_ports+col] 
				   = req[((prio+row)%num_ports)*num_ports +
					 (num_ports-row+col)%num_ports];
			  assign gnt_by_prio[((prio+row)%num_ports)*num_ports +
					     (num_ports-row+col)%num_ports +
					     prio*num_ports*num_ports]
				   = gnt_int[row*num_ports+col];
			  
		       end
		  end
	     end
	   
	   select_1ofn
	     #(.width(num_ports*num_ports),
	       .num_ports(num_ports))
	   gnt_sel
	     (.select(prio_q),
	      .data_in(gnt_by_prio),
	      .data_out(gnt));
	   
	end
      
   endgenerate

endmodule
