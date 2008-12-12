module ivc_ctrl
  (clk, reset, valid_in, data_in, head_in, tail_in, vc_req_op, vc_req_ovc,
   vc_gnt, vc_gnt_ovc, sw_req_op, sw_req_nonspec_op, sw_req_ovc, sw_gnt,
   data_out, vc_out, head_out, tail_out);
   
   
`include "config.v"
`include "constants.v"
   
   
   parameter reset_type = reset_type_async;
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   localparam buff_addr_width = clogb(num_buffers-1);
   
   
   input clk;
   input reset;
   
   input valid_in;
   input [0:data_width-1] data_in;
   input head_in;
   input tail_in;
   
   output wire [0:num_ports-1] vc_req_op;
   output wire [0:num_vcs-1]   vc_req_ovc;
   input vc_gnt;
   input [0:num_vcs-1] vc_gnt_ovc;
   
   output wire [0:num_ports-1] sw_req_op;
   output wire [0:num_ports-1] sw_req_nonspec_op;
   output wire [0:num_vcs-1]   sw_req_ovc;
   input sw_gnt;
   
   output wire [0:data_width-1] data_out;
   output wire [0:vc_idx_width-1] vc_out;
   output wire 			  head_out;
   output wire 			  tail_out;
   
   
   // --------------------------------------------------------------------------
   // -- track VC allocation status
   // --------------------------------------------------------------------------
   
   wire 			  vc_alloc_hold_q;
   wire 			  vc_allocated;
   assign vc_allocated = vc_gnt | vc_alloc_hold_q;
   
   wire 			  tail_q;
   wire 			  vc_alloc_hold_s;
   assign vc_alloc_hold_s = vc_allocated & ~(tail_q & sw_gnt);
   
   dff
     #(.width(1),
       .reset_type(reset_type))
   vc_alloc_holdq
     (.clk(clk),
      .reset(reset),
      .d(vc_alloc_hold_s),
      .q(vc_alloc_hold_q));
   
   
   // --------------------------------------------------------------------------
   // -- pipeline stall control
   // --------------------------------------------------------------------------
   
   wire 			  valid_q;
   wire 			  stall;
   assign stall = valid_q & ~(vc_allocated & sw_gnt);
   
   
   // --------------------------------------------------------------------------
   // -- flit buffer
   // --------------------------------------------------------------------------
   
   wire 			  empty;
   
   wire 			  push;
   assign push = valid_in && !(empty && !stall);
   
   wire 			  pop;
   assign pop = !empty && !stall;
   
   wire [0:buff_addr_width-1] 	  write_addr, read_addr;
   fifo_ctrl
     #(.depth(num_buffers-1),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push(push),
      .pop(pop),
      .write_addr(write_addr),
      .read_addr(read_addr),
      .empty(empty));
   
   wire [0:data_width-1] 	  buff_data;
   wire 			  buff_head;
   wire 			  buff_tail;
   regfile
     #(.width(data_width + 2),
       .depth(num_buffers-1),
       .internal_bypass(0))
   fbf
     (.clk(clk),
      .write_enable(valid_in),
      .write_address(write_addr),
      .write_data({data_in, head_in, tail_in}),
      .read_address(read_addr),
      .read_data({buff_data, buff_head, buff_tail}));
   
   
   // --------------------------------------------------------------------------
   // -- flit data flow
   // --------------------------------------------------------------------------
   
   wire 			  next_valid;
   assign next_valid = ~empty | valid_in;
   
   wire [0:data_width-1] 	  next_data;
   assign next_data = empty ? data_in : buff_data;
   
   wire [0:data_width-1] 	  data_s, data_q;
   assign data_s = stall ? data_q : next_data;
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   
   assign data_out = data_q;
   
   
   wire 			  next_head;
   assign next_head = empty ? head_in : buff_head;
   
   wire 			  head_s, head_q;
   assign head_s = stall ? head_q : next_head;
   dff
     #(.width(1),
       .reset_type(reset_type))
   headq
     (.clk(clk),
      .reset(reset),
      .d(head_s),
      .q(head_q));
   
   assign head_out = head_q;
   
   
   wire 			  next_tail;
   assign next_tail = empty ? tail_in : buff_tail;
   
   wire 			  tail_s;
   assign tail_s = stall ? tail_q : next_tail;
   dff
     #(.width(1),
       .reset_type(reset_type))
   tailq
     (.clk(clk),
      .reset(reset),
      .d(tail_s),
      .q(tail_q));
   
   assign tail_out = tail_q;
   
   assign valid_out = vc_allocated & sw_gnt;
   
   
   // --------------------------------------------------------------------------
   // -- routing logic
   // --------------------------------------------------------------------------
   
   wire 			  route_req;
   assign route_req = (next_valid & next_head) & ~stall;
   
   wire [0:route_info_width-1] 	  route_info;
   assign route_info = next_data[0:route_info_width-1];
   
   wire 			  route_gnt;
   wire [0:num_ports-1] 	  route_port;
   wire [0:route_info_width-1] 	  next_route_info;
   routing_logic
     #(.address(address))
   rtl
     (.clk(clk),
      .reset(reset),
      .req(route_req),
      .pkt_class(pkt_class),
      .pkt_address(pkt_address),
      .gnt(route_gnt),
      .op(route_port),
      .ovc_mask(route_ovc_mask));
   
   
   // --------------------------------------------------------------------------
   // -- routing info
   // --------------------------------------------------------------------------
   
   wire [0:num_ports-1] 	  port_s, port_q;
   assign port_s = route_gnt ? route_port : port_q;
   dff
     #(.width(num_ports),
       .reset_type(reset_type))
   portq
     (.clk(clk),
      .reset(reset),
      .d(port_s),
      .q(port_q));
   
   assign vc_req_op = port_q;
   assign sw_req_op = port_q;
   
   wire [0:num_ports-1] 	  nonspec_port_s, nonspec_port_q;
   assign nonspec_port_s = port_s & {num_ports{vc_alloc_hold_s}};
   dff
     #(.width(num_ports),
       .reset_type(reset_type))
   nonspec_portq
     (.clk(clk),
      .reset(reset),
      .d(nonspec_port_s),
      .q(nonspec_port_q));
   
   assign sw_req_nonspec_op = nonspec_port_q;
   
   wire [0:num_vcs-1] 		  vc_mask_s, vc_mask_q;
   assign vc_mask_s = route_req ?
		      route_ovc_mask :
		      (vc_gnt ? vc_gnt_ovc : vc_mask_q);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vc_maskq
     (.clk(clk),
      .reset(reset),
      .d(vc_mask_s),
      .q(vc_mask_q));
   
   assign vc_req_ovc = vc_mask_q & ~{num_vcs{vc_alloc_hold_q}};
   assign sw_req_ovc = vc_mask_q;
   
   encoder
     #(.num_ports(num_vcs))
   vc_enc
     (.data_in(vc_mask_q),
      .data_out(vc_out));
   
endmodule
