// top-level module for router
module fbr2x
     (clk, reset, router_address, flit_ctrl_in_ip, flit_data_in_ip, 
   flow_ctrl_out_ip, flit_ctrl_out_op, flit_data_out_op, flow_ctrl_in_op, 
   error);
   
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
   
   // flit buffer entries per VC
   parameter num_flit_buffers 	    = 32;
   parameter num_intm_buffers 	    = 8;
   parameter num_mini_buffers 	    = 4;
   
       
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers     = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes    = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes    = 2;
   
   // total number of packet classes
   localparam num_classes 	    = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class 	    = 1;
   
   // number of VCs
   localparam num_vcs 		    = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width 	    = clogb(num_vcs);
   
   // number of input and output ports on router
   parameter num_ports 		    = 10;
   
   // number of dimensions in network
   parameter num_dimensions 	    = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim    = 4;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim  = 3;
   
   // select packet format
   parameter packet_format 	    = `PACKET_FORMAT_EXPLICIT_LENGTH;
   
   // maximum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter max_payload_length     = 0;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length     = 0;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width 	    = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width     = num_dimensions * dim_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width
 				    = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // width of flit payload data
   parameter flit_data_width = 32;
   
   // width of flow control signals
   localparam flow_ctrl_width = 1 + vc_idx_width;
   
   // enable performance counter
   parameter perf_ctr_enable = 0;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 0;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select whether to set a packet's outgoing VC ID at the input or output 
   // controller
   parameter track_vcs_at_output = 0;
   
   // filter out illegal destination ports
   // (the intent is to allow synthesis to optimize away the logic associated 
   // with such turns)
   parameter restrict_turns = 0;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_FBFLY;
   
   // select order of dimension traversal
   parameter dimension_order = `DIMENSION_ORDER_ASCENDING;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_LEVEL;
   
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
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_NONE;
   
   localparam sw_spec_enable = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type = `RESET_TYPE_ASYNC;

   parameter num_nodes_per_router  = 4;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // control signals for each incoming flit
   input [0:(num_ports+num_ports-num_nodes_per_router)*flit_ctrl_width-1] flit_ctrl_in_ip;
   
   // flit data for each incoming flit
   input [0:(num_ports+num_ports-num_nodes_per_router)*flit_data_width-1] flit_data_in_ip;
   
   // outgoing flow control signals
   output [0:(num_ports+num_ports-num_nodes_per_router)*flow_ctrl_width-1] flow_ctrl_out_ip;
   wire [0:(num_ports+num_ports-num_nodes_per_router)*flow_ctrl_width-1] flow_ctrl_out_ip;
   
   // control signals for each outgoing flit
   output [0:(num_ports+num_ports-num_nodes_per_router)*flit_ctrl_width-1] flit_ctrl_out_op;
   wire [0:(num_ports+num_ports-num_nodes_per_router)*flit_ctrl_width-1] flit_ctrl_out_op;
   
   // flit data for each outgoing flit
   output [0:(num_ports+num_ports-num_nodes_per_router)*flit_data_width-1] flit_data_out_op;
   wire [0:(num_ports+num_ports-num_nodes_per_router)*flit_data_width-1] flit_data_out_op;
   
   // incoming flow control signals
   input [0:(num_ports+num_ports-num_nodes_per_router)*flow_ctrl_width-1] flow_ctrl_in_op;
   
   // internal error condition detected
   output error;
   wire 				error;



   assign flow_ctrl_out_ip  =   {((num_ports+num_ports-num_nodes_per_router)*flow_ctrl_width){1'b0}};
   

   
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip0;
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op0;
   wire [0:num_ports*flit_data_width-1] flit_data_out_op0;
   wire error0;
   
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_in_ip0;
   wire [0:num_ports*flit_data_width-1] flit_data_in_ip0;   
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_in_op0;
   

   
   fbr_tile
     #(
       // Parameters
       .num_flit_buffers		(num_flit_buffers),
       .num_intm_buffers		(num_intm_buffers),
       .num_mini_buffers		(num_mini_buffers),
       .num_header_buffers		(num_header_buffers),
       .num_traffic_classes		(num_traffic_classes),
       .num_routing_classes		(num_routing_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_ports			(num_ports),
       .num_dimensions			(num_dimensions),
       .num_routers_per_dim		(num_routers_per_dim),
       .num_neighbors_per_dim		(num_neighbors_per_dim),
       .packet_format			(packet_format),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .perf_ctr_enable			(perf_ctr_enable),
       .perf_ctr_width			(perf_ctr_width),
       .checker_enable			(checker_enable),
       .checker_capture_mode		(checker_capture_mode),
       .track_vcs_at_output		(track_vcs_at_output),
       .restrict_turns			(restrict_turns),
       .routing_function_type		(routing_function_type),
       .dimension_order			(dimension_order),
       .credit_handling_type		(credit_handling_type),
       .header_fifo_type		(header_fifo_type),
       .fbf_regfile_type		(fbf_regfile_type),
       .vc_allocator_type		(vc_allocator_type),
       .vc_arbiter_type			(vc_arbiter_type),
       .sw_allocator_type		(sw_allocator_type),
       .sw_arbiter_type			(sw_arbiter_type),
       .sw_spec_level			(sw_spec_level),
       .xbc_crossbar_type		(xbc_crossbar_type),
       .xbd_crossbar_type		(xbd_crossbar_type),
       .reset_type			(reset_type))
   fbr0
     (
      // Outputs
      .flow_ctrl_out_ip			(flow_ctrl_out_ip0[0:num_ports*flow_ctrl_width-1]),
      .flit_ctrl_out_op			(flit_ctrl_out_op0[0:num_ports*flit_ctrl_width-1]),
      .flit_data_out_op			(flit_data_out_op0[0:num_ports*flit_data_width-1]),
      .error				(error0),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .router_address			(router_address[0:router_addr_width-1]),
      .flit_ctrl_in_ip			(flit_ctrl_in_ip0[0:num_ports*flit_ctrl_width-1]),
      .flit_data_in_ip			(flit_data_in_ip0[0:num_ports*flit_data_width-1]),
      .flow_ctrl_in_op			(flow_ctrl_in_op0[0:num_ports*flow_ctrl_width-1]));
   



   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_out_ip1;
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_out_op1;
   wire [0:num_ports*flit_data_width-1] flit_data_out_op1;
   wire error1;
   
   wire [0:num_ports*flit_ctrl_width-1] flit_ctrl_in_ip1;
   wire [0:num_ports*flit_data_width-1] flit_data_in_ip1;   
   wire [0:num_ports*flow_ctrl_width-1] flow_ctrl_in_op1;
   

   
   fbr_tile
     #(
       // Parameters
       .num_flit_buffers		(num_flit_buffers),
       .num_intm_buffers		(num_intm_buffers),
       .num_mini_buffers		(num_mini_buffers),
       .num_header_buffers		(num_header_buffers),
       .num_traffic_classes		(num_traffic_classes),
       .num_routing_classes		(num_routing_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_ports			(num_ports),
       .num_dimensions			(num_dimensions),
       .num_routers_per_dim		(num_routers_per_dim),
       .num_neighbors_per_dim		(num_neighbors_per_dim),
       .packet_format			(packet_format),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .perf_ctr_enable			(perf_ctr_enable),
       .perf_ctr_width			(perf_ctr_width),
       .checker_enable			(checker_enable),
       .checker_capture_mode		(checker_capture_mode),
       .track_vcs_at_output		(track_vcs_at_output),
       .restrict_turns			(restrict_turns),
       .routing_function_type		(routing_function_type),
       .dimension_order			(dimension_order),
       .credit_handling_type		(credit_handling_type),
       .header_fifo_type		(header_fifo_type),
       .fbf_regfile_type		(fbf_regfile_type),
       .vc_allocator_type		(vc_allocator_type),
       .vc_arbiter_type			(vc_arbiter_type),
       .sw_allocator_type		(sw_allocator_type),
       .sw_arbiter_type			(sw_arbiter_type),
       .sw_spec_level			(sw_spec_level),
       .xbc_crossbar_type		(xbc_crossbar_type),
       .xbd_crossbar_type		(xbd_crossbar_type),
       .reset_type			(reset_type))
   fbr1
     (
      // Outputs
      .flow_ctrl_out_ip			(flow_ctrl_out_ip1[0:num_ports*flow_ctrl_width-1]),
      .flit_ctrl_out_op			(flit_ctrl_out_op1[0:num_ports*flit_ctrl_width-1]),
      .flit_data_out_op			(flit_data_out_op1[0:num_ports*flit_data_width-1]),
      .error				(error1),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .router_address			(router_address[0:router_addr_width-1]),
      .flit_ctrl_in_ip			(flit_ctrl_in_ip1[0:num_ports*flit_ctrl_width-1]),
      .flit_data_in_ip			(flit_data_in_ip1[0:num_ports*flit_data_width-1]),
      .flow_ctrl_in_op			(flow_ctrl_in_op1[0:num_ports*flow_ctrl_width-1]));

   /*  splitter     */
   assign flit_ctrl_in_ip0[0:(num_ports-num_nodes_per_router)*flit_ctrl_width-1] = flit_ctrl_in_ip[0:(num_ports-num_nodes_per_router)*flit_ctrl_width-1];
   assign flit_data_in_ip0[0:(num_ports-num_nodes_per_router)*flit_data_width-1] = flit_data_in_ip[0:(num_ports-num_nodes_per_router)*flit_data_width-1];
   assign flit_data_in_ip0[(num_ports-num_nodes_per_router)*flit_data_width:num_ports*flit_data_width-1] = flit_data_in_ip[(num_ports-num_nodes_per_router)*flit_data_width*2:(num_ports+num_ports-num_nodes_per_router)*flit_data_width-1];
   assign flow_ctrl_in_op0[0:(num_ports-num_nodes_per_router)*flow_ctrl_width-1] = flow_ctrl_in_op[0:(num_ports-num_nodes_per_router)*flow_ctrl_width-1];
   
   assign flit_ctrl_in_ip1[0:(num_ports-num_nodes_per_router)*flit_ctrl_width-1] = flit_ctrl_in_ip[(num_ports-num_nodes_per_router)*flit_ctrl_width:(num_ports-num_nodes_per_router)*flow_ctrl_width*2-1];
   assign flit_data_in_ip1[0:(num_ports-num_nodes_per_router)*flit_ctrl_width] = flit_data_in_ip[(num_ports-num_nodes_per_router)*flit_ctrl_width:(num_ports-num_nodes_per_router)*flow_ctrl_width*2-1];
   assign flit_data_in_ip1[(num_ports-num_nodes_per_router)*flit_data_width:num_ports*flit_data_width-1] = flit_data_in_ip[(num_ports-num_nodes_per_router)*flit_data_width*2:(num_ports+num_ports-num_nodes_per_router)*flit_data_width-1];
   assign flow_ctrl_in_op1[0:(num_ports-num_nodes_per_router)*flit_ctrl_width] = flow_ctrl_in_op[(num_ports-num_nodes_per_router)*flit_ctrl_width:(num_ports-num_nodes_per_router)*flow_ctrl_width*2-1];
   
   
										   
   generate
      genvar splittervar;
      for(splittervar = 0; splittervar<num_nodes_per_router; splittervar=splittervar+1)
	begin:splittergen
	   
	   wire splitter_s, splitter_q;
	   
	   assign splitter_s  = flit_ctrl_in_ip[(2*(num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width]?~splitter_q:splitter_q;
	   
	   c_dff
	     #(.width(1),
	       .reset_type(reset_type))
	   splitter_rr
	     (.clk(clk),
	      .reset(reset),
	      .d(splitter_s),
	      .q(splitter_q));
	   assign flit_ctrl_in_ip0[((num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width]  =(~splitter_s)&flit_ctrl_in_ip[(2*(num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width];
	   assign flit_ctrl_in_ip0[((num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width+1:((num_ports-num_nodes_per_router)+splittervar+1)*flit_ctrl_width-1] = flit_ctrl_in_ip[(2*(num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width];
	   
	   assign flit_ctrl_in_ip1[((num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width]  =(splitter_s)&flit_ctrl_in_ip[(2*(num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width];
	   assign flit_ctrl_in_ip1[((num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width+1:((num_ports-num_nodes_per_router)+splittervar+1)*flit_ctrl_width-1] = flit_ctrl_in_ip[(2*(num_ports-num_nodes_per_router)+splittervar)*flit_ctrl_width];
	   
	end // block: splittergen
   endgenerate
   
   
   assign error  = error0|error1;
   
endmodule
