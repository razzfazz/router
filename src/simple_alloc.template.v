module simple_alloc(CLK, RST, req_ip, req_ip_op, gnt_ip_op);

   parameter num_ports = NUM_PORTS;
   parameter use_clock_gating = USE_CLOCK_GATING;
   parameter use_architecture = USE_ARCHITECTURE;

   input CLK;
   input RST;

   // [sort order: input port]   
   input [0:num_ports-1] req_ip;

   // [sort order: input port,output port]
   input [0:num_ports*num_ports-1] req_ip_op;
   output [0:num_ports*num_ports-1] gnt_ip_op;
   
   wire 			     clk = CLK;
   wire 			     reset;
   
   dff
     #(.width(1))
   resetq
     (.clk(clk),
      .reset(1'b0),
      .enable(1'b0),
      .d(RST),
      .q(reset));

   genvar 			     i;
   
   generate

      if((use_architecture == 0) || (use_architecture == 1))
	begin

	   // [sort order: input port,output port]
	   wire [0:num_ports*num_ports-1] req1_ip_op;
	   wire [0:num_ports*num_ports-1] gnt1_ip_op;   
	   wire [0:num_ports*num_ports-1] gnt2_ip_op;   

	   assign req1_ip_op = req_ip_op;

	   // first stage arbiters
	   for(i = 0; i < num_ports; i = i + 1)
	     begin:input_ports

		wire [0:num_ports-1] req1_op;
		wire [0:num_ports-1] gnt1_op;
		wire [0:num_ports-1] gnt2_op;

		assign req1_op = req1_ip_op[i*num_ports:(i+1)*num_ports-1];
		assign gnt2_op = gnt2_ip_op[i*num_ports:(i+1)*num_ports-1];
		
		wire 		     update;

		assign update = |gnt2_op;
	   
		arbiter
		  #(.num_ports(num_ports),
		    .use_arbiter_type(use_architecture),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(req1_op),
		   .gnt(gnt1_op));

		assign gnt1_ip_op[i*num_ports:(i+1)*num_ports-1] = gnt1_op;
		
	     end

	   // [sort order: input port,output port]
	   wire [0:num_ports*num_ports-1] req2_ip_op;

	   assign req2_ip_op = gnt1_ip_op;

	   // [sort order: output port,input port]
	   wire [0:num_ports*num_ports-1] req2_op_ip;
   
	   interleaver
	     #(.width(num_ports*num_ports),
	       .num_blocks(num_ports))
	   req2_intl
	     (.data_in(req2_ip_op),
	      .data_out(req2_op_ip));

	   // [sort order: output port,input port]
	   wire [0:num_ports*num_ports-1] gnt2_op_ip;

	   // second stage arbiters
	   for(i = 0; i < num_ports; i = i + 1)
	     begin:output_ports
		
		wire [0:num_ports-1] req2_ip;
		wire [0:num_ports-1] gnt2_ip;

		assign req2_ip = req2_op_ip[i*num_ports:(i+1)*num_ports-1];
		
		wire 		     update;
		
		assign update = |req2_ip;
	   
		arbiter
		  #(.num_ports(num_ports),
		    .use_arbiter_type(use_architecture),
		    .use_clock_gating(use_clock_gating))
		arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update),
		   .req(req2_ip),
		   .gnt(gnt2_ip));

		assign gnt2_op_ip[i*num_ports:(i+1)*num_ports-1] = gnt2_ip;
		
	     end
	   
	   interleaver
	     #(.width(num_ports*num_ports),
	       .num_blocks(num_ports))
	   gnt2_intl
	     (.data_in(gnt2_op_ip),
	      .data_out(gnt2_ip_op));

	   assign gnt_ip_op = gnt2_ip_op;
	   
	end
      else if((use_architecture == 2) || (use_architecture == 3))
	begin

	   wire update;
	   
	   assign update = |req_ip;
	     
	   wf_alloc
	     #(.num_ports(num_ports),
	       .use_clock_gating(use_clock_gating),
	       .use_architecture(use_architecture-2))
	   alloc
	     (.clk(clk),
	      .reset(reset),
	      .update(update),
	      .req(req_ip_op),
	      .gnt(gnt_ip_op));
	   
	end
      
   endgenerate

endmodule
