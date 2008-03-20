module wf_alloc
  #(// number of input/output ports
    // each input can bid for any combination of outputs
    parameter num_ports = 8,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1,
    
    /* supported architectures:
     0: rotate inputs/outputs based on priority
     1: replicate logic per priority
     2: diagonal propagation arbiter (DPA, see Hurt99) */
    parameter architecture = 0)
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

   generate

      case(architecture)
	0:
	  begin
	     
	     wire [0:num_ports-1] prio_s, prio_q;
	     if(hold_type == 0)
	       assign prio_s = update ?
			       {prio_q[num_ports-1], prio_q[0:num_ports-2]} :
			       prio_q;
	     else if((hold_type == 1) || (hold_type == 2))
	       assign prio_s = {prio_q[num_ports-1], prio_q[0:num_ports-2]};
	     
	     dff
	       #(.width(num_ports),
		 .reset_type(reset_type),
		 .reset_value({1'b1, {(num_ports-1){1'b0}}}),
		 .hold_type(hold_type))
	     prioq
	       (.clk(clk),
		.reset(reset),
		.enable(update),
		.d(prio_s),
		.q(prio_q));
	     
	     // [sort order: input port,output port]
	     wire [0:num_ports*num_ports-1] y;
	     
	     genvar 			    row;
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
		  
		  genvar 		 col;
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
				   (2*num_ports-row-col-1)%num_ports+
				   num_ports-1];
		       
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
	1:
	  begin
	     
	     wire [0:num_ports-1] 		    prio_s, prio_q;

	     if(hold_type == 0)
	       assign prio_s = update ?
			       {prio_q[num_ports-1], prio_q[0:num_ports-2]} :
			       prio_q;
	     else if((hold_type == 1) || (hold_type == 2))
	       assign prio_s = {prio_q[num_ports-1], prio_q[0:num_ports-2]};
	     
	     dff
	       #(.width(num_ports),
		 .reset_type(reset_type),
		 .reset_value({1'b1, {(num_ports-1){1'b0}}}),
		 .hold_type(hold_type))
	     prioq
	       (.clk(clk),
		.reset(reset),
		.enable(update),
		.d(prio_s),
		.q(prio_q));
	     
	     // [sort order: input port,output port,priority group]
	     wire [0:num_ports*num_ports*num_ports-1] gnt_by_prio;
	     
	     genvar 				      prio;
	     for(prio = 0; prio < num_ports; prio = prio + 1)
	       begin:prios
		  
		  // [sort order: input port,output port]
		  wire [0:num_ports*num_ports-1] req_int;
		  wire [0:num_ports*num_ports-1] gnt_int;
		  wire [0:num_ports*num_ports-1] y;
		  
		  genvar 			 row;		
		  for(row = 0; row < num_ports; row = row + 1)
		    begin:rows
		       
		       wire [0:num_ports-1] x_in, y_in;
		       wire [0:num_ports]   x_out, y_out;
		       wire [0:num_ports-1] req_in;
		       wire [0:num_ports-1] gnt_out;
		       
		       assign x_in = x_out[0:num_ports-1];
		       assign y_in
			 = y[((row+num_ports)%num_ports)*num_ports:
			     ((row+num_ports)%num_ports+1)*num_ports-1];
		       assign req_in = req_int[row*num_ports:
					       (row+1)*num_ports-1];
		       
		       assign x_out = {1'b1, (~y_in | ~req_in) & x_in};
		       assign y_out = {1'b1, (~x_in | ~req_in) & y_in};
		       assign gnt_out = req_in & x_in & y_in;
		       
		       assign y[((row+num_ports+1)%num_ports)*num_ports:
				((row+num_ports+1)%num_ports+1)*num_ports-1]
				= y_out[0:num_ports-1];
		       assign gnt_int[row*num_ports:(row+1)*num_ports-1]
				= gnt_out;
		       
		       genvar 		    col;
		       for(col = 0; col < num_ports; col = col + 1)
			 begin:cols
			    
			    assign req_int[row*num_ports+col] 
				     = req[((prio+row)%num_ports)*num_ports +
					   (num_ports-row+col)%num_ports];
			    assign gnt_by_prio[((prio+row)%num_ports)*
					       num_ports +
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
	2:
	  begin
	     
	     wire [0:2*num_ports-2] prio_s, prio_q;

	     wire reset_prio;
	     assign reset_prio = reset || ~|prio_q[0:num_ports-2];
	     
	     if(hold_type == 0)
	       assign prio_s = update ?
			       reset_prio ?
			       {{num_ports{1'b1}}, {(num_ports-1){1'b0}}} :
			       {1'b0, prio_q[0:2*num_ports-3]} :
			       prio_q;
	     else if((hold_type == 1) || (hold_type == 2))
	       assign prio_s = reset_prio ?
			       {{num_ports{1'b1}}, {(num_ports-1){1'b0}}} :
			       {1'b0, prio_q[0:2*num_ports-3]};
	     
	     dff
	       #(.width(2*num_ports-1),
		 .reset_type(reset_type),
		 .reset_value({{num_ports{1'b1}}, {(num_ports-1){1'b0}}}),
		 .hold_type(hold_type))
	     prioq
	       (.clk(clk),
		.reset(reset),
		.enable(update),
		.d(prio_s),
		.q(prio_q));
	     
	     wire [0:num_ports*(2*num_ports-2)-1] x;
	     
	     genvar 				  col;
	     for(col = 0; col < num_ports; col = col + 1)
	       begin:cols
		  
		  wire [0:2*num_ports-2] x_in, y_in;
		  wire [0:2*num_ports-2] x_out, y_out;
		  wire [0:2*num_ports-2] req_in;
		  wire [0:2*num_ports-2] gnt_out;
		  
		  assign x_in = {1'b1, x[col*(2*num_ports-2):
					 (col+1)*(2*num_ports-2)-2]};
		  assign y_in = {1'b1, y_out[0:2*num_ports-3]};
		  assign x_out = (x_in & ~(y_in & req_in)) | ~prio_q;
		  assign y_out = (y_in & ~(x_in & req_in)) | ~prio_q;
		  assign gnt_out = req_in & x_in & y_in & prio_q;
		  assign x[((col+1)%num_ports)*(2*num_ports-2):
			   ((col+1)%num_ports+1)*(2*num_ports-2)-1]
			   = x_out[0:2*num_ports-3];
		  
		  genvar 		 row;
		  for(row = 0; row < num_ports-1; row = row + 1)
		    begin:rows
		       
		       assign req_in[row]
				= req[((num_ports-col+row)%num_ports)*
				      num_ports + col];
		       assign req_in[row+num_ports]
				= req[((num_ports-col+row)%num_ports)*
				      num_ports + col];
		       assign gnt[((num_ports-col+row)%num_ports)*num_ports+col]
				= gnt_out[row] | gnt_out[row+num_ports];
		    end
		  
		  assign req_in[num_ports-1]
			   = req[((2*num_ports-1-col)%num_ports)*num_ports+col];
		  assign gnt[((2*num_ports-1-col)%num_ports)*num_ports+col]
			   = gnt_out[num_ports-1];
		  
	       end	     
	     
	  end      

      endcase
      
   endgenerate
   
endmodule
