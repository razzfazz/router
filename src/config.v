//`ifndef _CONFIG_V_
//`define _CONFIG_V_

`include "functions.v"

// buffers per VC
parameter num_buffers = 8;
localparam buff_idx_width = clogb(num_buffers);

// flit width
parameter data_width = 64;

// traffic classes
parameter num_traffic_classes = 2;
localparam traffic_class_idx_width = clogb(num_traffic_classes);

// routing classes
parameter num_routing_classes = 2;
localparam routing_class_idx_width = clogb(num_routing_classes);

// total number of classes
localparam num_classes = num_traffic_classes * num_routing_classes;
localparam class_idx_width = clogb(num_classes);

// number of virtual channels
parameter num_vcs_per_class = 1;
localparam num_vcs = num_classes * num_vcs_per_class;
localparam vc_idx_width = clogb(num_vcs);

// network dimensions
parameter num_dimensions = 2;

// number of nodes per router (a.k.a. concentration factor)
parameter num_nodes_per_router = 4;
localparam node_addr_width = clogb(num_nodes_per_router);

// total number of nodes in each dimension
parameter num_routers_per_dim = 4;
localparam dim_addr_width = clogb(num_routers_per_dim);
localparam router_addr_width = num_dimensions * dim_addr_width;

// total address width
localparam addr_width = router_addr_width + node_addr_width;

// length of header data required for routing
localparam route_info_width = 2 * addr_width;

// connectivity in each dimension
// flattened butterfly:
parameter num_neighbors = num_routers_per_dim - 1;
/* mesh:
parameter num_neighbors = 2;
*/

// function to determine neighbor to route to (
// flattened butterfly:
function [0:num_neighbors-1] get_neighbor
  (input [0:dim_addr_width-1] src, input [0:dim_addr_width-1] dst);
   reg [0:num_routers_per_dim-1] temp;
   reg [0:num_neighbors-1] 	 result;
   integer 			 i;
   begin
      temp = {num_routers_per_dim{1'b0}};
      temp[dst] = 1'b1;
      for(i = src + 1; i < num_routers_per_dim; i = i + 1)
	begin
	   result[i - src - 1] = temp[i];
	end
      for(i = 0; i < src; i = i + 1)
	begin
	   result[num_routers_per_dim + i - src - 1] = temp[i];
	end
      get_neighbor = result;
   end
endfunction
/* mesh:
function [0:num_neighbors-1] get_neighbor
  (input [0:dim_addr_width-1] src, input [0:dim_addr_width-1] dst);
   begin
      get_neighbor[0] = (dst < src);
      get_neighbor[1] = (dst > src);
   end
endfunction
*/

// function to extract routing info structure from flit
function [0:route_info_width-1] get_route_info
  (input [0:data_width-1] data);
   begin
      get_route_info = data[0:route_info_width-1];
   end
endfunction

// function to extract next hop address field from routing info structure
function [0:addr_width-1] get_next_address
  (input [0:route_info_width-1] data);
   begin
      get_next_address = data[0:addr_width-1];
   end
endfunction

// function to extract final destination field from routing info structure
function [0:addr_width-1] get_final_address
  (input [0:route_info_width-1] data);
   begin
      get_final_address = data[addr_width:(2*addr_width)-1];
   end
endfunction

// number of ports required on router
localparam num_ports = num_dimensions * num_neighbors + num_nodes_per_router;
localparam port_idx_width = clogb(num_ports);

//`endif
