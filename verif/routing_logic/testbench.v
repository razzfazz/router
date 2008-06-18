module testbench
  ();
   
   parameter reset_type = 1;
   parameter Tclk = 2;
   
`include "config.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   reg 	   clk;
   reg 	   reset;
   
   wire    req;
   wire    gnt;

   assign req = 1'b1;
   
   reg [0:route_info_width-1] route_info;
   wire [0:route_info_width-1] next_route_info;
   reg [0:routing_class_idx_width-1] routing_class;
   wire [0:routing_class_idx_width-1] next_routing_class;
   wire [0:num_ports-1] 	      next_port;
   
   routing_logic
     #(.reset_type(reset_type),
       .address(address))
   rl
     (.clk(clk),
      .reset(reset),
      .req(req),
      .route_info(route_info),
      .routing_class(routing_class),
      .gnt(gnt),
      .next_route_info(next_route_info),
      .next_routing_class(next_routing_class),
      .next_port(next_port));
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end

   wire [0:routing_class_idx_width-1] routing_class_next;
   assign routing_class_next = routing_class + gnt;
   
   wire [0:route_info_width-1] route_info_next;
   assign route_info_next
     = {2{route_info[0:addr_width-1] + (&routing_class & gnt)}};
   
   always @(posedge clk)
     begin
	route_info <= route_info_next & {route_info_width{~reset}};
	routing_class <= routing_class_next & {routing_class_idx_width{~reset}};
     end
   
   always @(negedge clk)
     begin
	$display($time, " next address (in)   = %b",
		 get_next_address(route_info));
	$display($time, " final address (in)  = %b",
		 get_final_address(route_info));
	$display($time, " routing class (in)  = %b",
		 routing_class);
	$display($time, " port    = %b (%1d)",
		 next_port, num_ports - encode(next_port) - 1);
	$display($time, " next address (out)  = %b",
		 get_next_address(next_route_info));
	$display($time, " final address (out) = %b",
		 get_final_address(next_route_info));
	$display($time, " routing class (out) = %b",
		 next_routing_class);
	if(~^next_port)
	  begin
	     $display($time, " ERROR: multiple ports generated!");
	     $stop;
	  end
	if(is_x(next_port))
	  begin
	     $display($time, " ERROR: X-value in generated port!");
	     $stop;
	  end
     end
   
   initial
   begin
      reset = 1'b1;
      
      #(Tclk);
      
      reset = 1'b0;
      
      while(~&{route_info[0:addr_width-1], routing_class}) 
	#(Tclk);
      
      $finish;
   end
   
endmodule
