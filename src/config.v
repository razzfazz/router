//`ifndef _CONFIG_V_
//`define _CONFIG_V_

`include "functions.v"

// buffers per VC
parameter num_buffers = 8;
localparam buff_idx_width = clogb(num_buffers);

// flit types
parameter num_flit_types = 4;
localparam flit_type_width = clogb(num_flit_types);
parameter [0:flit_type_width-1] flit_type_body = 0;
parameter [0:flit_type_width-1] flit_type_tail = 1;
parameter [0:flit_type_width-1] flit_type_head = 2;
parameter [0:flit_type_width-1] flit_type_single = 3;

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
localparam route_info_width = addr_width + class_idx_width + addr_width;

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
   reg [0:num_routers_per_dim-1] temp = {num_routers_per_dim{1'b0}};
   reg [0:num_neighbors-1] result = {num_neighbors{1'b0}};
   integer 		   i;
   integer 		   j = 0;
   temp[dst] = 1'b1;
   for(i = src + 1; i < num_neighbors; i = i + 1, j = j + 1)
     begin
	result[j] = temp[i];
     end
   for(i = 0; i < src; i = i + 1, j = j + 1)
     begin
	result[j] = temp[i];
     end
   choose_neighbor = result;
endfunction
/* mesh:
function [0:num_neighbors-1] get_neighbor
  (input [0:dim_addr_width-1] src, input [0:dim_addr_width-1] dst);
   get_neighbor[0] = (dst < src);
   get_neighbor[1] = (dst > src);
endfunction
*/

// number of ports required on router
localparam num_ports = num_dimensions * num_neighbors + num_nodes_per_router;
localparam port_idx_width = clogb(num_ports);

//`endif
