module router_wrapper
  (clk, reset, flit_valid_in_ip, flit_vc_in_ip, flit_head_in_ip,
   flit_tail_in_ip, flit_data_in_ip, cred_valid_out_ip, cred_vc_out_ip,
   flit_valid_out_op, flit_vc_out_op, flit_head_out_op, flit_tail_out_op,
   flit_data_out_op, cred_valid_in_op, cred_vc_in_op, error);
   
`include "constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // select network topology
   parameter network_topology = `NETWORK_TOPOLOGY_MESH;
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // current router's address
   parameter [0:router_addr_width-1] router_address = {router_addr_width{1'b0}};
   
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       2 :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       (num_routers_per_dim - 1) :
       -1;
   
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router = 1;
   
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;

   // flit width
   parameter data_width = 64;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // try to recover from errors
   parameter error_recovery = 0;
   
   // select routing function type
   localparam routing_function_type
     = (network_topology == `NETWORK_TOPOLOGY_MESH) ?
       `ROUTING_FUNCTION_TYPE_BY_RELATION :
       (network_topology == `NETWORK_TOPOLOGY_FBFLY) ?
       `ROUTING_FUNCTION_TYPE_BY_DIFFERENCE :
       -1;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // select method for credit checking
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_LEVEL)
   parameter sw_spec_cred_check = `SW_SPEC_CRED_CHECK_SEL_POST;
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   // enable speculative switch allocation
   localparam sw_spec_enable = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select crossbar implementation variant
   parameter crossbar_type = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // valid flit data available at input port(s)
   input [0:num_ports-1] flit_valid_in_ip;
   
   // which VC(s) is/are incoming flit(s) travelling on
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports*vc_idx_width-1] flit_vc_in_ip;
   
   // incoming flit(s) is/are head(s)
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports-1] flit_head_in_ip;
   
   // incoming flit(s) is/are tail(s)
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports-1] flit_tail_in_ip;
   
   // flit data for each incoming flit
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports*data_width-1] flit_data_in_ip;
   
   // outgoing credit(s) valid
   output [0:num_ports-1] cred_valid_out_ip;
   wire [0:num_ports-1] cred_valid_out_ip;
   
   // VC indicators for outgoing credit(s)
   // (note: only valid when corresponding bit in cred_valid_out_ip is high)
   output [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   wire [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   // valid flit data available at output port(s)
   output [0:num_ports-1] flit_valid_out_op;
   wire [0:num_ports-1] 	     flit_valid_out_op;
   
   // which VC(s) is/are outgoing flit(s) travelling on
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   wire [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   
   // outgoing flit(s) is/are head(s)
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports-1] flit_head_out_op;
   wire [0:num_ports-1] 	     flit_head_out_op;
   
   // outgoing flit(s) is/are tail(s)
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports-1] flit_tail_out_op;
   wire [0:num_ports-1] 	     flit_tail_out_op;
   
   // flit data for each outgoing flit
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports*data_width-1] flit_data_out_op;
   wire [0:num_ports*data_width-1]   flit_data_out_op;
   
   // incoming credit(s) available
   input [0:num_ports-1] cred_valid_in_op;
   
   // VC indicators for incoming flit(s)
   // (note: only valid when corresponding bit in cred_valid_in_op is high)
   input [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   // internal error condition detected
   output error;
   wire 			     error;
   
   router
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_vcs(num_vcs),
       .num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .router_address(router_address),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .data_width(data_width),
       .perf_ctr_enable(perf_ctr_enable),
       .perf_ctr_width(perf_ctr_width),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .error_recovery(error_recovery),
       .routing_function_type(routing_function_type),
       .credit_handling_type(credit_handling_type),
       .sw_spec_cred_check(sw_spec_cred_check),
       .vc_allocator_type(vc_allocator_type),
       .vc_arbiter_type(vc_arbiter_type),
       .sw_allocator_type(sw_allocator_type),
       .sw_arbiter_type(sw_arbiter_type),
       .sw_spec_level(sw_spec_level),
       .crossbar_type(crossbar_type),
       .reset_type(reset_type))
   rtr
     (.clk(clk),
      .reset(reset),
      .flit_valid_in_ip(flit_valid_in_ip),
      .flit_vc_in_ip(flit_vc_in_ip),
      .flit_head_in_ip(flit_head_in_ip),
      .flit_tail_in_ip(flit_tail_in_ip),
      .flit_data_in_ip(flit_data_in_ip),
      .cred_valid_out_ip(cred_valid_out_ip),
      .cred_vc_out_ip(cred_vc_out_ip),
      .flit_valid_out_op(flit_valid_out_op),
      .flit_vc_out_op(flit_vc_out_op),
      .flit_head_out_op(flit_head_out_op),
      .flit_tail_out_op(flit_tail_out_op),
      .flit_data_out_op(flit_data_out_op),
      .cred_valid_in_op(cred_valid_in_op),
      .cred_vc_in_op(cred_vc_in_op),
      .error(error));
   
endmodule