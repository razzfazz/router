//`ifndef _CONFIG_V_
//`define _CONFIG_V_

// number of virtual channels
parameter num_vcs = 4;

// buffers per VC
parameter num_buffers = 8;

// flit types
// (idle, reserved, valid, tail)
parameter num_types = 4;

// flit width
parameter data_width = 64;

// packet classes
// (read request, read reply, write request, write reply)
parameter num_classes = 4;

// network dimensions
parameter num_dimensions = 2;

// number of nodes per router (a.k.a. concentration factor)
parameter num_nodes = 4;

// number of routers in each dimension
parameter num_neighbors = 4;

// which packet classes can go on which VC?
parameter [0:num_classes*num_vcs-1] vc_masks
  = {4'b1000, 4'b0100, 4'b0010, 4'b0001};

`include "functions.v"

localparam num_ports = num_dimensions * (num_neighbors-1) + num_nodes;
localparam type_width = clogb(num_types);
localparam dim_addr_width = clogb(num_neighbors);
localparam node_addr_width = clogb(num_nodes);
localparam addr_width = num_dimensions * dim_addr_width + node_addr_width;
localparam port_idx_width = clogb(num_ports);
localparam vc_idx_width = clogb(num_vcs);
localparam buff_idx_width = clogb(num_buffers);
localparam class_idx_width = clogb(num_classes);
localparam head_data_width = addr_width + class_idx_width;

localparam [0:type_width-1] type_idle = 0;
localparam [0:type_width-1] type_rsvd = 1;
localparam [0:type_width-1] type_valid = 2;
localparam [0:type_width-1] type_tail = 3;

//`endif
