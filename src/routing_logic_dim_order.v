module routing_logic_dim_order
  (clk, reset, req, pkt_class, pkt_address, gnt, op, ovc_mask);
   
`include "config.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};

   input clk;
   input reset;
   input req;
   input [0:class_width-1] pkt_class;
   input [0:addr_width-1] pkt_address;
   output gnt;
   output [0:num_ports-1] op;
   output [0:num_vcs-1] ovc_mask;
   
   assign gnt = req;
   
   mux_nto1
     #(.width(num_vcs),
       .num_ports(num_classes))
   vc_mask_sel
     (.select(pkt_class),
      .data_in(vc_masks),
      .data_out(ovc_mask));
   
   wire [0:num_dimensions-1] dim_addr_match;
   
   generate
      
      genvar 		     dim;
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   localparam [0:dim_addr_width-1] my_dim_addr
	     = address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   wire [0:dim_addr_width-1] pkt_dim_addr;
	   assign pkt_dim_addr
	     = pkt_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   assign dim_addr_match[dim] = (my_dim_addr == pkt_dim_addr);

	   wire 		     route_here;
	   if(dim == 0)
	     assign route_here = ~dim_addr_match[dim];
	   else
	     assign route_here = dim_addr_match[0:dim-1] & ~dim_addr_match[dim];

	   wire [0:num_neighbors-1] port_dec;
	   decoder
	     #(.num_ports(num_neighbors))
	   dim_addr_dec
	     (.data_in(pkt_dim_addr),
	      .data_out(port_dec));

	   wire [0:(2*num_neighbors-1)-1] port_rep;
	   assign port_rep = {port_dec, port_dec[0:num_neighbors-2]};

	   assign op[dim*(num_neighbors-1):(dim+1)*(num_neighbors-1)-1]
	     = port_rep[(my_dim_addr+1):(my_dim_addr+num_neighbors)-1] &
	       {(num_neighbors-1){route_here}};

	end
      
   endgenerate

   wire [0:node_addr_width-1] 		  node_addr;
   assign node_addr = pkt_address[num_dimensions*dim_addr_width:addr_width-1];
   
   wire [0:num_nodes-1] 		  node_dec;
   decoder
     #(.num_ports(num_nodes))
   port_addr_dec
     (.data_in(node_addr),
      .data_out(node_dec));
   
   assign op[num_dimensions*(num_neighbors-1):num_ports-1]
	    = node_dec & {num_nodes{&dim_addr_match}};
   
endmodule
