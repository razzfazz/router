module ivc_ctrl
  (clk, reset, data_in, type_in, vc_req_op, vc_req_ovc, vc_gnt, vc_gnt_ovc,
   sw_req_op, sw_req_nonspec_op, sw_req_ovc, sw_gnt, data_out, vc_out,
   type_out);
   
   // see dff.v for supported values
   parameter reset_type = 1;
   
`include "config.v"

   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   localparam buff_addr_width = clogb(num_buffers-1);

   
   input clk;
   input reset;
   
   input [0:data_width-1] data_in;
   input [0:type_width-1] type_in;
   
   output [0:num_ports-1] vc_req_op;
   output [0:num_vcs-1] vc_req_ovc;
   input vc_gnt;
   input [0:num_vcs-1] vc_gnt_ovc;
   
   output [0:num_ports-1] sw_req_op;
   output [0:num_ports-1] sw_req_nonspec_op;
   output [0:num_vcs-1] sw_req_ovc;
   input sw_gnt;

   output [0:data_width-1] data_out;
   output [0:vc_idx_width-1] vc_out;
   output [0:type_width-1] type_out;
   
   
   wire [0:type_width-1] type_q;
   
   
   // --------------------------------------------------------------------------
   // -- track VC allocation status
   // --------------------------------------------------------------------------
   
   wire 		      vc_alloc_hold_q;
   wire 		      vc_allocated;
   assign vc_allocated = vc_gnt | vc_alloc_hold_q;

   wire 		      vc_alloc_hold_s;
   assign vc_alloc_hold_s = vc_allocated && !((type_q == type_tail) && sw_gnt);
   
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
   
   wire 		      stall;
   assign stall = ((type_q == type_valid) || (type_q == type_tail)) &&
		  !(vc_allocated && sw_gnt);
   
   
   // --------------------------------------------------------------------------
   // -- flit buffer
   // --------------------------------------------------------------------------
   
   wire flit_avail;
   assign flit_avail = (type_in == type_valid) || (type_in == type_tail);
   
   wire empty;
   
   wire push;
   assign push = flit_avail && !(empty && !stall);
	   
   wire pop;
   assign pop = !empty && !stall;
   
   wire [0:buff_addr_width-1] write_addr, read_addr;
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
   
   wire [0:data_width-1]      buff_data;
   wire [0:type_width-1]      buff_type;
   regfile
     #(.width(data_width + type_width),
       .depth(num_buffers-1),
       .internal_bypass(0))
   fbf
     (.clk(clk),
      .write_enable(flit_avail),
      .write_address(write_addr),
      .write_data({data_in, type_in}),
      .read_address(read_addr),
      .read_data({buff_data, buff_type}));


   // --------------------------------------------------------------------------
   // -- flit data flow
   // --------------------------------------------------------------------------
   
   wire [0:data_width-1]      next_data;
   assign next_data = empty ? data_in : buff_data;
   
   wire [0:data_width-1]      data_s, data_q;
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
	   

   wire [0:type_width-1]      next_type;
   assign next_type = empty ? type_in : buff_type;
	   
   wire [0:type_width-1]      type_s;
   assign type_s = stall ? type_q : next_type;
   dff
     #(.width(type_width),
       .reset_type(reset_type))
   typeq
     (.clk(clk),
      .reset(reset),
      .d(type_s),
      .q(type_q));
   
   // Suppress the outgoing flit if we haven't been allocated a VC yet.
   // Note: This assumes "no flit" is encoded as all-zeros!
   assign type_out = {type_width{vc_allocated}} & type_q;
   
   
   // --------------------------------------------------------------------------
   // -- routing logic
   // --------------------------------------------------------------------------
	   
   wire 		      route_req;
   assign route_req = ((type_in == type_valid) || (type_in == type_tail) ||
		       !empty) && !stall;
   
   wire [0:head_data_width-1] header;
   assign header = next_data[0:head_data_width-1];
   
   wire [0:class_idx_width-1] pkt_class;
   wire [0:addr_width-1]      pkt_address;
   header_decoder
   hdrd
     (.header(header),
      .pkt_class(pkt_class),
      .pkt_address(pkt_address));
   
   wire 		      route_gnt;
   wire [0:num_ports-1]       route_port;
   wire [0:num_vcs-1] 	      route_ovc_mask;
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
   
   wire [0:num_ports-1]       port_s, port_q;
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
   
   wire [0:num_ports-1]       nonspec_port_s, nonspec_port_q;
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
   
   wire [0:num_vcs-1] 	      vc_mask_s, vc_mask_q;
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
