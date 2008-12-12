module packet_source
  (clk, reset, active, flit_valid, flit_head, flit_tail, flit_data, vc_req,
   vc_gnt, sw_req, sw_gnt);
   
`include "functions.v"
`include "config.v"
`include "config_utils.v"
`include "constants.v"
   
   parameter reset_type = reset_type_async;
   parameter packet_length = 1;
   parameter packet_rate = 0;
   parameter initial_seed = 0;
   parameter adaptive_rate = 0;
   parameter packet_count_width = 32;
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   parameter walk_addresses = 0;
   localparam flit_count_width = clogb(packet_length);
   
   input clk;
   input reset;
   
   input active;
   
   output flit_valid;
   output flit_head;
   output flit_tail;
   output [0:data_width-1] flit_data;
   
   output vc_req;
   input vc_gnt;

   output sw_req;
   input sw_gnt;
   
   reg flit_valid;
   reg flit_head;
   reg flit_tail;
   reg [0:data_width-1] flit_data;
   
   reg 			vc_req;
   reg 			sw_req;
   
   integer 		seed = initial_seed;
   
   reg 			incr_packet_count;   
   reg 			decr_packet_count;
   
   wire [0:packet_count_width-1] packet_count_s, packet_count_q;
   assign packet_count_s
     = packet_count_q - decr_packet_count + incr_packet_count;
   dff
     #(.width(packet_count_width),
       .reset_type(reset_type),
       .reset_value(1))
   packet_countq
     (.clk(clk),
      .reset(reset),
      .d(packet_count_s),
      .q(packet_count_q));
   
   wire 			 packet_count_zero;
   assign packet_count_zero = ~|packet_count_q;
   
   reg 				 active_s;
   wire 			 active_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   activeq
     (.clk(clk),
      .reset(reset),
      .d(active_s),
      .q(active_q));
   
   reg 				 load_flit_count;
   reg 				 decr_flit_count;
   wire 			 flit_count_max;
   wire 			 flit_count_zero;
   
   generate
      
      if(packet_length > 1)
	begin
	   wire [0:flit_count_width-1] flit_count_s, flit_count_q;
	   assign flit_count_s = load_flit_count ?
				 (packet_length - 1'b1) :
				 (flit_count_q - decr_flit_count);
	   dff
	     #(.width(flit_count_width),
	       .reset_type(reset_type))
	   flit_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_count_s),
	      .q(flit_count_q));

	   assign flit_count_max = (flit_count_q == (packet_length - 1'b1));
	   assign flit_count_zero = ~|flit_count_q;
	end
      else
	begin
	   assign flit_count_max = 1'b1;
	   assign flit_count_zero = 1'b1;
	end
      
   endgenerate
   
   integer i;
   
   reg 	   is_adaptive;
   reg 	   is_reply;
   reg [0:data_width-1] random_data;
   reg [0:addr_width-1] random_next_addr;
   reg [0:addr_width-1] random_final_addr;
   always @(posedge clk)
     begin
	incr_packet_count
	  = ($dist_uniform(seed, 0, 99) < (packet_rate / packet_length)) &&
	    active;
	is_adaptive = ($dist_uniform(seed, 0, 99) < adaptive_rate);
	is_reply = $dist_uniform(seed, 0, 1);
	for(i = 0; i < data_width; i = i + 1)
	  random_data[i] = $dist_uniform(seed, 0, 1);
	if(walk_addresses)
	  random_next_addr
	    = reset ?
	      0 :
	      (random_next_addr + 1 + (random_next_addr + 1 == address));
	else
	  random_next_addr
	    = address + $dist_uniform(seed, 1, 2**addr_width-1);
	random_final_addr
	  = is_adaptive ?
	    address + $dist_uniform(seed, 1, 2**addr_width-1) :
	    random_next_addr;
     end
   
   reg vc_allocated_s;
   wire vc_allocated_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocatedq
     (.clk(clk),
      .reset(reset),
      .d(vc_allocated_s),
      .q(vc_allocated_q));
   
   always @(*)
     begin
	if(active_q)
	  begin
	     if(flit_count_max)
	       begin
		  vc_req = ~vc_allocated_q;
		  sw_req = vc_gnt | vc_allocated_q;
	       end
	     else
	       begin
		  vc_req = 1'b0;
		  sw_req = 1'b1;
	       end
	     flit_valid = sw_gnt;
	     flit_data = sw_gnt ?
			 flit_count_max ?
			 set_route_info(random_data,
					create_route_info(random_next_addr,
							  random_final_addr)) :
			 random_data :
			 {data_width{1'b0}};
	     flit_head = sw_gnt & flit_count_max;
	     flit_tail = sw_gnt & flit_count_zero;
	     active_s = ~packet_count_zero | ~(sw_gnt & flit_count_zero);
	     vc_allocated_s = (vc_gnt | vc_allocated_q) &
			      ~(sw_gnt & flit_count_zero);
	     load_flit_count = sw_gnt & flit_count_zero & ~packet_count_zero;
	     decr_flit_count = sw_gnt & ~flit_count_zero;
	     decr_packet_count = sw_gnt & flit_count_zero & ~packet_count_zero;
	  end
	else
	  begin
	     vc_req = 1'b0;
	     sw_req = 1'b0;
	     flit_valid = 1'b0;
	     flit_data = {data_width{1'b0}};
	     flit_head = 1'b0;
	     flit_tail = 1'b0;
	     active_s = ~packet_count_zero;
	     vc_allocated_s = 1'b0;
	     load_flit_count = ~packet_count_zero;
	     decr_flit_count = 1'b0;
	     decr_packet_count = ~packet_count_zero;
	  end
     end
   
endmodule
