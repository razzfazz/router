module row_bus_driver (/*AUTOARG*/
   // Outputs
   flit_ctrl_in_row_bus, flit_data_in_row_bus, flow_ctrl_out_tile,
   // Inputs
   router_address, clk, reset, flow_ctrl_in_row_bus,
   flit_ctrl_in_tile, flit_data_in_tile
   );

   `include "c_constants.v"
   `include "vcr_constants.v"
   
   // compute ceiling of binary logarithm
   function integer clogb(input integer argument);
      integer 		     i;
      begin
	 clogb 			    = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb 		    = clogb + 1;
      end
   endfunction
   
   // flit buffer entries per VC  input buffer
   parameter num_flit_buffers 	    = 128;
   parameter num_row_buffers 	    = 32;
   parameter num_col_buffers 	    = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers     = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes    = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes    = 1;
   
   // total number of packet classes
   localparam num_classes 	    = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class 	    = 1;
   
   // number of VCs
   localparam num_vcs 		    = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width 	    = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports 		    = 8;
   
   // width required to select an individual port
   localparam port_idx_width 	    = clogb(num_ports);
   
   // number of dimensions in network
   parameter num_dimensions 	    = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim    = 8;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim  = 2;
   
   // select packet format
   parameter packet_format 	    = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length     = 10;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length     = 1;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width 	    = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width     = num_dimensions * dim_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width  = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
				 (1 + vc_idx_width + 1 + 1) : 
				 (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
				 (1 + vc_idx_width + 1) : 
				 -1;
   
   // width of flit payload data
   parameter flit_data_width = 32;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_MESH;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // width required for internal flit control signalling
   localparam int_flit_ctrl_width
     = 1 + vc_idx_width + 1 + 1;
   
   // width required for internal flow control signalling
   localparam int_flow_ctrl_width
     = (credit_handling_type == `CREDIT_HANDLING_TYPE_LEVEL) ?
       2 :
       (credit_handling_type == `CREDIT_HANDLING_TYPE_PUSH) ?
       1 :
       -1;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // number of entries in flit buffer
   localparam fbf_depth = num_vcs*num_flit_buffers;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
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
   
   localparam sw_spec_enable = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type = `RESET_TYPE_ASYNC;

   input [0:router_addr_width-1] router_address;
   input clk;
   input reset;
   
   input [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_in_row_bus;
   output [0:num_vcs*flit_ctrl_width-1] flit_ctrl_in_row_bus;
   output [0:num_vcs*flit_data_width-1] flit_data_in_row_bus;
   
   input [0:flit_ctrl_width-1] flit_ctrl_in_tile;
   input [0:flit_data_width-1] flit_data_in_tile;
   output [0:flow_ctrl_width-1] flow_ctrl_out_tile;




   //------------------------------------
   //input vc split
   //------------------------------------
   wire [0:flit_ctrl_width-1] flit_ctrl_in_vc0;
   wire [0:flit_data_width-1] flit_data_in_vc0;
   wire [0:flit_ctrl_width-1] flit_ctrl_in_vc1;
   wire [0:flit_data_width-1] flit_data_in_vc1;
   
   //valid bits
   assign flit_ctrl_in_vc0[0]  = ~flit_ctrl_in_tile[1:1+vc_idx_width-1] && flit_ctrl_in_tile[0];
   assign flit_ctrl_in_vc1[0]  = flit_ctrl_in_tile[1:1+vc_idx_width-1] && flit_ctrl_in_tile[0];
   //control and data
   assign flit_ctrl_in_vc0[1:flit_ctrl_width-1] = ~flit_ctrl_in_tile[1:1+vc_idx_width-1]  && flit_ctrl_in_tile[0]? flit_ctrl_in_tile[1:flit_ctrl_width-1]:flit_ctrl_in_vc0[1:flit_ctrl_width-1];
   assign flit_ctrl_in_vc1[1:flit_ctrl_width-1] = flit_ctrl_in_tile[1:1+vc_idx_width-1]  && flit_ctrl_in_tile[0]? flit_ctrl_in_tile[1:flit_ctrl_width-1]:flit_ctrl_in_vc1[1:flit_ctrl_width-1];
   assign flit_data_in_vc0[0:flit_data_width-1] = ~flit_ctrl_in_tile[1:1+vc_idx_width-1]  && flit_ctrl_in_tile[0]? flit_data_in_tile[0:flit_data_width-1]:flit_data_in_vc0[0:flit_data_width-1];
   assign flit_data_in_vc1[0:flit_data_width-1] = flit_ctrl_in_tile[1:1+vc_idx_width-1]  && flit_ctrl_in_tile[0]? flit_data_in_tile[0:flit_data_width-1]:flit_data_in_vc1[0:flit_data_width-1];









   //-------------------------------------------------------------------
   // input controller VC 0
   //-------------------------------------------------------------------

   wire [0:2*8*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
//   wire [0:num_vcs*port_idx_width-1] route_port_ivc;
  	   wire [0:num_vcs*num_ports-1] route_ivc_op;
   wire [0:num_vcs-1] 		     inc_rc_ivc;
   wire [0:num_vcs-1] 		     vc_req_ivc;
   wire [0:num_vcs-1] 		     sw_req_nonspec_ivc;
   wire [0:num_vcs-1] 		     sw_req_spec_ivc;
   wire [0:int_flit_ctrl_width-1]    int_flit_ctrl_out;
   wire [0:flit_data_width-1] 	     flit_data_out;
   wire [0:flow_ctrl_width-1] 	     flow_ctrl_out;
   wire [0:fbf_addr_width-1] 	     fbf_write_addr;
   wire 			     fbf_write_enable;
   wire [0:flit_data_width-1] 	     fbf_write_data;
   wire [0:fbf_addr_width-1] 	     fbf_read_addr;
   wire 			     fbf_read_enable;
   wire [0:flit_data_width-1] 	     fbf_read_data;
   wire 			     ipc_error;
   vcr_ip_ctrl_mac_yarc
     #(.num_flit_buffers(num_flit_buffers),
       .num_header_buffers(num_header_buffers),
       .num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .packet_format(packet_format),
       .max_payload_length(max_payload_length),
       .min_payload_length(min_payload_length),
       .flit_data_width(flit_data_width),
       .track_vcs_at_output(track_vcs_at_output),
       .restrict_turns(0),
       .routing_function_type(routing_function_type),
       .dimension_order(dimension_order),
       .credit_handling_type(credit_handling_type),
       .header_fifo_type(header_fifo_type),
       .fbf_regfile_type(fbf_regfile_type),
       .sw_spec_enable(sw_spec_enable),
       .perf_ctr_enable(perf_ctr_enable),
       .perf_ctr_width(perf_ctr_width),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .port_id(0),
       .reset_type(reset_type))
   ipc
     (
      .clk(clk),
      .reset(reset),
      .router_address(router_address),
      .flit_ctrl_in(flit_ctrl_in_vc0),
      .flit_data_in(flit_data_in_vc0),
      .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
      .route_ivc_op(route_ivc_op),
      .inc_rc_ivc(inc_rc_ivc),
      .vc_req_ivc(vc_req_ivc),
      .vc_gnt_ivc(2'b11),
      .vc_gnt_ivc_ovc(4'b1111),
      .sw_req_nonspec_ivc(sw_req_nonspec_ivc),
      .sw_req_spec_ivc(sw_req_spec_ivc),
      .sw_gnt_nonspec_ivc(sw_gnt_nonspec_ivc),
      .sw_gnt_spec_ivc(2'b00),
      .int_flit_ctrl_out(int_flit_ctrl_out),
      .flit_data_out(flit_data_out),
      .flow_ctrl_out(flow_ctrl_out),
      .error(ipc_error));
   
   c_regfile_mac
     #(.width(flit_data_width),
       .depth(fbf_depth),
       .regfile_type(fbf_regfile_type))
   fbf
     (.clk(clk),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(fbf_write_data),
      .read_enable(fbf_read_enable),
      .read_address(fbf_read_addr),
      .read_data(fbf_read_data));

  
endmodule
