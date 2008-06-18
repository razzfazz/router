module port_decoder_dim_order
  (next_address, next_port);
   
`include "config.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   input [0:addr_width-1] next_address;
   output [0:num_ports-1] next_port;
   
   wire [0:num_dimensions-1] dim_addr_match;
   
   generate
      
      genvar 		     dim;
      for(dim = 0; dim < num_dimensions; dim = dim + 1)
	begin:dims
	   
	   wire [0:dim_addr_width-1] dim_addr;
	   assign dim_addr
	     = next_address[dim*dim_addr_width:(dim+1)*dim_addr_width-1];
	   
	   assign dim_addr_match[dim]
		    = (dim_addr == address[dim*dim_addr_width:
					   (dim+1)*dim_addr_width-1]);
	   
	   wire 		     route_here;
	   if(dim == 0)
	     assign route_here
	       = ~dim_addr_match[dim];
	   else
	     assign route_here
	       = &dim_addr_match[0:dim-1] & ~dim_addr_match[dim];
	   
	   wire [0:num_neighbors-1]  port_dec;
	   assign port_dec = get_neighbor(address[dim*dim_addr_width:
						  (dim+1)*dim_addr_width-1],
					  dim_addr);
	   
	   assign next_port[dim*num_neighbors:(dim+1)*num_neighbors-1]
		    = port_dec & {num_neighbors{route_here}};
	   
	end
      
   endgenerate
   
   wire [0:node_addr_width-1] 	     node_addr;
   assign node_addr = next_address[num_dimensions*dim_addr_width:addr_width-1];
   
   wire [0:num_nodes_per_router-1]   node_dec;
   decoder
     #(.num_ports(num_nodes_per_router))
   port_addr_dec
     (.data_in(node_addr),
      .data_out(node_dec));
   
   assign next_port[num_dimensions*num_neighbors:num_ports-1]
	    = node_dec & {num_nodes_per_router{&dim_addr_match}};
   
endmodule
