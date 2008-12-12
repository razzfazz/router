//`ifndef _CONFIG_V_
//`define _CONFIG_V_

`define USE_FBFLY
//`define USE_MESH

// flit buffers per VC (must be power of two, greater than 1)
parameter num_buffers = 8;
localparam buffer_idx_width = clogb(num_buffers);

// header buffers per VC
parameter num_headers = 4;

// flit width
parameter data_width = 64;

// traffic classes (must be power of two)
parameter num_traffic_classes = 2;

// routing classes (must be power of two)
parameter num_routing_classes = 2;

// total number of classes
localparam num_classes = num_traffic_classes * num_routing_classes;

// number of virtual channels per class (must be power of two)
parameter num_vcs_per_class = 1;

// total number of virtual channels
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

// flattened butterfly:
`ifdef USE_FBFLY

// connectivity in each dimension
localparam num_neighbors = num_routers_per_dim - 1;

// function to determine neighbor to route to
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

`endif

// mesh:
`ifdef USE_MESH

// connectivity in each dimension
localparam num_neighbors = 2;

// function to determine neighbor to route to
function [0:num_neighbors-1] get_neighbor
  (input [0:dim_addr_width-1] src, input [0:dim_addr_width-1] dst);
   begin
      get_neighbor[0] = (dst < src);
      get_neighbor[1] = (dst > src);
   end
endfunction

`endif

// number of ports required on router
localparam num_ports = num_dimensions * num_neighbors + num_nodes_per_router;
localparam port_idx_width = clogb(num_ports);

// prevent packets from exiting through same port they came in on
parameter ignore_same_port = 0;

// only allow legal ivc->ovc requests
parameter restrict_vcs = 0;

//`endif
