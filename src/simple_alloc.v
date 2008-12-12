module simple_alloc
   (CLK, RST, req_ip_op, gnt_ip_op);
   
   
`include "config.v"
`include "constants.v"
   
   
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: separable, input-first, round-robin arbiters
    1: separable, input-first, matrix arbiters
    2: wavefront, mux inputs for priority
    3: wavefront, replicated logic for priority
    4: wavefront, diagonal propagation arbiter
    5: wavefront, rotate inputs for priority */
   parameter architecture = 0;
   
   
   input CLK;
   input RST;
   
   input [0:num_ports*num_ports-1] req_ip_op;
   output [0:num_ports*num_ports-1] gnt_ip_op;
   
   
   wire clk = CLK;
   wire reset;
   
   dff
     #(.width(1),
       .reset_type(0))
   resetq
     (.clk(clk),
      .d(RST),
      .q(reset));

   generate

      case(architecture)
	0, 1:
	  begin
	     
	     wire [0:num_ports*num_ports-1] req1_ip_op;
	     assign req1_ip_op = req_ip_op;
	     
	     wire [0:num_ports*num_ports-1] gnt1_ip_op;   
	     wire [0:num_ports*num_ports-1] gnt2_ip_op;   
	     
	     // first stage arbiters
	     genvar 			    i;
	     for(i = 0; i < num_ports; i = i + 1)
	       begin:input_ports
		  
		  wire [0:num_ports-1] req1_op;		  
		  assign req1_op = req1_ip_op[i*num_ports:(i+1)*num_ports-1];
		  
		  wire [0:num_ports-1] gnt2_op;
		  assign gnt2_op = gnt2_ip_op[i*num_ports:(i+1)*num_ports-1];
		  
		  wire 		       update;
		  assign update = |gnt2_op;
		  
		  wire [0:num_ports-1] gnt1_op;
		  arbiter
		    #(.num_ports(num_ports),
		      .reset_type(reset_type),
		      .arbiter_type(architecture))
		  arb
		    (.clk(clk),
		     .reset(reset),
		     .update(update),
		     .req(req1_op),
		     .gnt(gnt1_op));
		  
		  assign gnt1_ip_op[i*num_ports:(i+1)*num_ports-1] = gnt1_op;
		  
	       end
	     
	     wire [0:num_ports*num_ports-1] req2_ip_op;
	     assign req2_ip_op = gnt1_ip_op;
	     
	     wire [0:num_ports*num_ports-1] req2_op_ip;
	     interleaver
	       #(.width(num_ports*num_ports),
		 .num_blocks(num_ports))
	     req2_intl
	       (.data_in(req2_ip_op),
		.data_out(req2_op_ip));
	     
	     wire [0:num_ports*num_ports-1] gnt2_op_ip;
	     
	     // second stage arbiters
	     for(i = 0; i < num_ports; i = i + 1)
	       begin:output_ports
		  
		  wire [0:num_ports-1] req2_ip;
		  assign req2_ip = req2_op_ip[i*num_ports:(i+1)*num_ports-1];
		  
		  wire 		       update;
		  assign update = |req2_ip;
		  
		  wire [0:num_ports-1] gnt2_ip;
		  arbiter
		    #(.num_ports(num_ports),
		      .reset_type(reset_type),
		      .arbiter_type(architecture))
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
	2, 3, 4, 5:
	  begin
	     
	     wire update;
	     assign update = |req_ip_op;
	     
	     wf_alloc
	       #(.num_ports(num_ports),
		 .reset_type(reset_type),
		 .allocator_type(architecture-2))
	     alloc
	       (.clk(clk),
		.reset(reset),
		.update(update),
		.req(req_ip_op),
		.gnt(gnt_ip_op));
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
