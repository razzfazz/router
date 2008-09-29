//`ifndef _CONFIG_UTILS_V_
//`define _CONFIG_UTILS_V_

// function to extract traffic class from VC index
function integer get_traffic_class(input [0:vc_idx_width-1] vc);
   begin
      get_traffic_class
	= (vc >> clogb(num_routing_classes*num_vcs_per_class)) %
	  num_traffic_classes;
   end
endfunction

// change traffic class in VC identifier
function [0:vc_idx_width-1] set_traffic_class(input [0:vc_idx_width-1] vc,
    input integer traffic_class);
   begin
      set_traffic_class
	= (traffic_class << (num_routing_classes*num_vcs_per_class)) |
	  (get_routing_class(vc) << num_vcs_per_class) |
	  (vc % num_vcs_per_class);
   end
endfunction

// function to extract routing class from VC index
function integer get_routing_class(input [0:vc_idx_width-1] vc);
   begin
      get_routing_class
	= (vc >> clogb(num_vcs_per_class)) % num_routing_classes;
   end
endfunction

// change routing class in VC identifier
function [0:vc_idx_width-1] set_routing_class(input [0:vc_idx_width-1] vc,
    input integer routing_class);
   begin
      set_routing_class
	= (get_traffic_class(vc) << (num_routing_classes*num_vcs_per_class)) |
	  (routing_class << num_vcs_per_class) |
	  (vc % num_vcs_per_class);
   end
endfunction

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
   integer/*reg [0:vc_idx_width-1]*/ ivc, ovc;
   integer 		  ivctc, ovctc;
//   integer 		  ivcrc, ovcrc;
   begin
      for(i = 0; i < num_vcs*num_vcs; i = i + 1)
	begin
	   ivc = i / num_vcs;
	   ovc = i % num_vcs;
	   ivctc = (ivc / (num_routing_classes * num_vcs_per_class)) /*%
		   num_traffic_classes*/;
	   ovctc = (ovc / (num_routing_classes * num_vcs_per_class)) /*%
		   num_traffic_classes*/;
//	   ivcrc = (ivc / num_vcs_per_class) % num_routing_classes;
//	   ovcrc = (ovc / num_vcs_per_class) % num_routing_classes;
	   create_mask_ivc_ovc[i]
	     = ((ivctc == ovctc) /*&&
		((ivcrc != 0) ||
		 (ovcrc == 0))*/) ||
	       !restrict_vcs;
	end
   end
endfunction

function [0:num_vcs*num_vcs-1] create_mask_ovc_ivc(input restrict_vcs);
   integer i;
   integer/*reg [0:vc_idx_width-1]*/ ovc, ivc;
   integer 		  ovctc, ivctc;
//   integer 		  ovcrc, ivcrc;
   begin
      for(i = 0; i < num_vcs*num_vcs; i = i + 1)
	begin
	   ovc = i % num_vcs;
	   ivc = i / num_vcs;
	   ovctc = (ovc / (num_routing_classes * num_vcs_per_class)) /*%
		   num_traffic_classes*/;
	   ivctc = (ivc / (num_routing_classes * num_vcs_per_class)) /*%
		   num_traffic_classes*/;
//	   ovcrc = (ovc / num_vcs_per_class) % num_routing_classes;
//	   ivcrc = (ivc / num_vcs_per_class) % num_routing_classes;
	   create_mask_ovc_ivc[i]
	     = ((ovctc == ivctc) /*&&
		((ovcrc == 0) ||
		 (ivcrc != 0))*/) ||
	       !restrict_vcs;
	end
   end
endfunction

//`endif
