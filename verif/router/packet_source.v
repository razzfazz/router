module packet_source
  (clk, reset, active, flit_valid, flit_head, flit_tail, flit_vc, flit_data,
   elig_ovc, free_ovc);
   
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
   output [0:vc_idx_width-1] flit_vc;
   output [0:data_width-1] flit_data;
   
   input [0:num_vcs-1] elig_ovc;
   input [0:num_vcs-1] free_ovc;
   
   wire flit_valid;
   wire flit_head;
   wire flit_tail;
   wire [0:vc_idx_width-1] flit_vc;
   wire [0:data_width-1]   flit_data;
   
   
   integer 		  seed = initial_seed;
   
   integer i;
   
   reg 	   new_packet;   
   reg 	   is_adaptive;
   reg 	   is_reply;
   reg [0:data_width-1] random_data;
   reg [0:vc_idx_width-1] random_vc;
   reg [0:addr_width-1]   random_next_addr;
   reg [0:addr_width-1]   random_final_addr;
   always @(posedge clk)
     begin
	new_packet
	  = ($dist_uniform(seed, 0, 99) < (packet_rate / packet_length)) &&
	    active;
	is_adaptive = ($dist_uniform(seed, 0, 99) < adaptive_rate);
	is_reply = $dist_uniform(seed, 0, 1);
	for(i = 0; i < data_width; i = i + 1)
	  random_data[i] = $dist_uniform(seed, 0, 1);
	random_vc = $dist_uniform(seed, 0, num_vcs-1);
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
   
   
   wire 			  packet_sent;
   
   wire [0:packet_count_width-1]  packet_count_s, packet_count_q;
   assign packet_count_s
     = packet_count_q - packet_sent + new_packet;
   dff
     #(.width(packet_count_width),
       .reset_type(reset_type))
   packet_countq
     (.clk(clk),
      .reset(reset),
      .d(packet_count_s),
      .q(packet_count_q));
   
   wire 			  packet_count_zero;
   assign packet_count_zero = ~|packet_count_q;
   
   wire 			  flit_count_max;
   wire 			  flit_count_zero;
   
   wire [0:num_vcs-1] 		  vc_dec;
   
   wire 			  free;
   assign free = |(vc_dec & free_ovc);
   
   wire 			  vc_allocated;
   
   wire 			  flit_sent;
   assign flit_sent = ~packet_count_zero & vc_allocated & free;
   
   assign packet_sent = flit_count_zero & flit_sent;
   
   generate
      
      if(packet_length > 1)
	begin
	   wire [0:flit_count_width-1] flit_count_s, flit_count_q;
	   assign flit_count_s = packet_sent ?
				 (packet_length - 1'b1) :
				 (flit_count_q - flit_sent);
	   dff
	     #(.width(flit_count_width),
	       .reset_type(reset_type),
	       .reset_value(packet_length - 1'b1))
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
   
   wire 			  elig;
   assign elig = |(vc_dec & elig_ovc);
   
   wire 			  vc_allocated_q;
   
   assign vc_allocated = vc_allocated_q | (elig & flit_count_max);
   
   wire 			  vc_allocated_s;
   assign vc_allocated_s = vc_allocated & ~packet_sent;
   dff
     #(.width(1),
       .reset_type(reset_type))
   vc_allocatedq
     (.clk(clk),
      .reset(reset),
      .d(vc_allocated_s),
      .q(vc_allocated_q));
   
   wire [0:vc_idx_width-1] 	  vc_s, vc_q;
   assign vc_s = packet_sent ? random_vc : vc_q;
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   vcq
     (.clk(clk),
      .reset(reset),
      .d(vc_s),
      .q(vc_q));
   
   decoder
     #(.num_ports(num_vcs))
   vc_dec_dec
     (.data_in(vc_q),
      .data_out(vc_dec));
   
   wire [0:data_width-1] 	  data_s, data_q;
   assign data_s = flit_sent ?
		   (packet_sent ?
		    set_route_info(random_data, 
				   create_route_info(random_next_addr,
						     random_final_addr)) :
		    random_data) :
		   data_q;
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   
   wire [0:addr_width-1] 	  final_addr_s, final_addr_q;
   assign final_addr_s = packet_sent ? random_final_addr : final_addr_q;
   dff
     #(.width(addr_width),
       .reset_type(reset_type))
   final_addrq
     (.clk(clk),
      .reset(reset),
      .d(final_addr_s),
      .q(final_addr_q));
   
   
   assign flit_valid = flit_sent;
   assign flit_head = flit_count_max;
   assign flit_tail = flit_count_zero;
   assign flit_vc = vc_q;
   assign flit_data = data_q;
   
endmodule
