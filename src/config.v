//`ifndef _CONFIG_V_
//`define _CONFIG_V_

`include "functions.v"

// buffers per VC
parameter num_buffers = 8;
localparam buff_idx_width = clogb(num_buffers);

// flit types
parameter num_types = 4;
localparam type_width = clogb(num_types);
parameter [0:type_width-1] type_idle = 0;
parameter [0:type_width-1] type_rsvd = 1;
parameter [0:type_width-1] type_valid = 2;
parameter [0:type_width-1] type_tail = 3;

// flit width
parameter data_width = 64;

// packet classes
parameter num_classes = 4;
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
localparam head_data_width = addr_width + class_idx_width;

// connectivity in each dimension
parameter num_neighbors = num_routers_per_dim - 1;

// number of ports required on router
localparam num_ports = num_dimensions * num_neighbors + num_nodes_per_router;
localparam port_idx_width = clogb(num_ports);

//`endif
