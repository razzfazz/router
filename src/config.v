//`ifndef _CONFIG_V_
//`define _CONFIG_V_

// buffers per VC
parameter num_buffers = 10;
localparam buff_idx_width = clogb(num_buffers);

// flit width
parameter data_width = 64;

// traffic classes (2+)
parameter num_traffic_classes = 2;
localparam traffic_class_idx_width = clogb(num_traffic_classes);

// routing classes (1+)
// FIXME: Setting this to 1 is probably not handled correctly right now due to 
// Verilog and/or the tools not liking zero-width vectors.
parameter num_routing_classes = 2;
localparam routing_class_idx_width = clogb(num_routing_classes);

// definitions 
parameter [0:routing_class_idx_width-1] routing_class_minimal = 0;
parameter [0:routing_class_idx_width-1] routing_class_non_minimal = 1;

// total number of classes
localparam num_classes = num_traffic_classes * num_routing_classes;
localparam class_idx_width = clogb(num_classes);

// number of virtual channels
parameter num_vcs_per_class = 1;
localparam num_vcs = num_classes * num_vcs_per_class;
localparam vc_idx_width = clogb(num_vcs);

// function to extract traffic class from VC index
function [0:traffic_class_idx_width-1] get_traffic_class
  (input [0:vc_idx_width-1] vc);
   begin
      get_traffic_class = vc[0:traffic_class_idx_width-1];
   end
endfunction

// function to extract routing class from VC index
function [0:routing_class_idx_width-1] get_routing_class
  (input [0:vc_idx_width-1] vc);
   begin
      get_routing_class = vc[traffic_class_idx_width:
			     traffic_class_idx_width+routing_class_idx_width-1];
   end
endfunction

// function to change the traffic class in a VC index
function [0:vc_idx_width-1] set_traffic_class
  (input [0:vc_idx_width-1] vc,
   input [0:traffic_class_idx_width-1] traffic_class);
   begin
      set_traffic_class = vc;
      set_traffic_class[0:traffic_class_idx_width-1] = traffic_class;
   end
endfunction

// function to change the routing class in a VC index
function [0:vc_idx_width-1] set_routing_class
  (input [0:vc_idx_width-1] vc,
   input [0:routing_class_idx_width-1] routing_class);
   begin
      set_routing_class = vc;
      set_routing_class[traffic_class_idx_width:
			traffic_class_idx_width+routing_class_idx_width-1]
	= routing_class;
   end
endfunction

// function to create a bit-mask of allowable VCs for a given combination of
// traffic class and routing class
function [0:num_vcs-1] create_vc_mask
  (input [0:traffic_class_idx_width-1] traffic_class,
   input [0:routing_class_idx_width-1] routing_class);
   integer vc;
   begin
      for(vc = 0; vc < num_vcs; vc = vc + 1)
	begin
	   create_vc_mask[vc] = (get_traffic_class(vc) == traffic_class) &&
				(get_routing_class(vc) == routing_class);
	end
   end
endfunction

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
// mesh:
//parameter num_neighbors = 2;

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
// mesh:
/*function [0:num_neighbors-1] get_neighbor
  (input [0:dim_addr_width-1] src, input [0:dim_addr_width-1] dst);
   begin
      get_neighbor[0] = (dst < src);
      get_neighbor[1] = (dst > src);
   end
endfunction*/

// function to extract routing info structure from flit
function [0:route_info_width-1] get_route_info
  (input [0:data_width-1] data);
   begin
      get_route_info = data[0:route_info_width-1];
   end
endfunction

// function to set routing info in flit
function [0:data_width-1] set_route_info
  (input [0:data_width-1] data, input [0:route_info_width-1] route_info);
   begin
      set_route_info = data;
      set_route_info[0:route_info_width-1] = route_info;
   end
endfunction

// function to assemble routing info structure from components
function [0:route_info_width-1] create_route_info
  (input [0:addr_width-1] next_address, input [0:addr_width-1] final_address);
   begin
      create_route_info = {next_address, final_address};
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

// prevent packets from exiting through same port they came in on
parameter ignore_same_port = 1;

// only allow legal ivc->ovc requestst
parameter restrict_vcs = 1;

function [0:num_ports*num_ports-1] create_mask_ip_op(input ignore_same_port);
   integer i;
   reg [0:port_idx_width-1] ip, op;
   begin
      for(i = 0; i < num_ports*num_ports; i = i + 1)
	begin
	   ip = i / num_ports;
	   op = i % num_ports;
	   create_mask_ip_op[i] = (ip != op) || !ignore_same_port;
	end
   end
endfunction

function [0:num_ports*num_ports-1] create_mask_op_ip(input ignore_same_port);
   integer i;
   reg [0:port_idx_width-1] op, ip;
   begin
      for(i = 0; i < num_ports*num_ports; i = i + 1)
	begin
	   op = i / num_ports;
	   ip = i % num_ports;
	   create_mask_op_ip[i] = (ip != op) || !ignore_same_port;
	end
   end
endfunction

function [0:num_vcs*num_vcs-1] create_mask_ivc_ovc(input restrict_vcs);
   integer i;
   reg [0:vc_idx_width-1] ivc, ovc;
   reg [0:traffic_class_idx_width-1] ivctc, ovctc;
   begin
      for(i = 0; i < num_vcs*num_vcs; i = i + 1)
	begin
	   ivc = i / num_vcs;
	   ovc = i % num_vcs;
	   ivctc = ivc / (num_routing_classes * num_vcs_per_class);
	   ovctc = ovc / (num_routing_classes * num_vcs_per_class);
	   create_mask_ivc_ovc[i]
	     = (ivctc == ovctc) ||
	     /*= ((get_traffic_class(ivc) == get_traffic_class(ovc)) &&
		((get_routing_class(ivc) != routing_class_minimal) ||
		 (get_routing_class(ovc) == routing_class_minimal))) ||*/
	       !restrict_vcs;
	end
   end
endfunction

function [0:num_vcs*num_vcs-1] create_mask_ovc_ivc(input restrict_vcs);
   integer i;
   reg [0:vc_idx_width-1] ovc, ivc;
   reg [0:traffic_class_idx_width-1] ovctc, ivctc;
   begin
      for(i = 0; i < num_vcs*num_vcs; i = i + 1)
	begin
	   ovc = i % num_vcs;
	   ivc = i / num_vcs;
	   ovctc = ivc / (num_routing_classes * num_vcs_per_class);
	   ivctc = ovc / (num_routing_classes * num_vcs_per_class);
	   create_mask_ovc_ivc[i]
	     = (ivctc == ovctc) ||
	     /*= ((get_traffic_class(ivc) == get_traffic_class(ovc)) &&
		((get_routing_class(ivc) != routing_class_minimal) ||
		 (get_routing_class(ovc) == routing_class_minimal))) ||*/
	       !restrict_vcs;
	end
   end
endfunction

//`endif
