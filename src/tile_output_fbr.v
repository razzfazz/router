module tile_output_fbr (/*autoarg*/
   // Outputs
   flow_ctrl_col_bus, flit_ctrl_out_tile, flit_data_out_tile,
   // Inputs
   flit_ctrl_col_bus, flit_data_col_bus, flow_ctrl_in_tile, clk,
   reset, router_address
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
      // flit buffer entries per VC
   parameter num_flit_buffers 	    = 64;
   parameter num_intm_buffers 	    = 8;
   parameter num_mini_buffers 	    = 4;
   
       
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers     = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes    = 1;
   
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

   //=================
   //End of param
   //=================

   //within the tiles
   input [0:num_ports*flit_ctrl_width-1] flit_ctrl_col_bus;
   input [0:num_ports*flit_data_width-1] flit_data_col_bus;
   output [0:num_ports*(flow_ctrl_width)-1] flow_ctrl_col_bus;

   //to the outside world
   input  [0:flow_ctrl_width-1] flow_ctrl_in_tile;
   output [0:flit_ctrl_width-1] flit_ctrl_out_tile;
   output [0:flit_data_width-1] flit_data_out_tile;

   input clk;
   input reset;
   
   input [0:router_addr_width-1] router_address;


   //2:1 rr for vc, then 8:1 rr for row input


   
   //--------------------------------------------------------------------
   // input ports
   //--------------------------------------------------------------------
   
   wire [0:num_vcs-1] elig_ovc;
   wire [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   
   wire [0:num_ports*num_vcs*num_ports-1] 	    route_ip_ivc_op;
   wire [0:num_ports*num_vcs-1] 		    inc_rc_ip_ivc;
   
   wire [0:num_ports*num_vcs-1] 		    vc_req_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	    vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs-1] 		    sw_req_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_req_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_spec_ip_ivc;
   wire [0:num_ports*num_ports-1] 		    sw_gnt_ip_op;
   
   wire [0:num_ports*int_flit_ctrl_width-1] 	    xbc_data_in_ip;
   wire [0:num_ports*flit_data_width-1] 	    xbd_data_in_ip;
   wire [0:int_flit_ctrl_width-1] 	   flit_ctrl_output;
   wire [0:flit_data_width-1] 	    flit_data_output;
   
   wire [0:num_ports-1] 			    ipc_error_ip;



   wire [0:1] vc_final_gnt;
   wire [0:1] vc_final_req;
   wire [0:1] vc_arb_v1_gnt;
   wire [0:1] vc_arb_v2_gnt;
   wire [0:1] vc_arb_v1_req;
   wire [0:1] vc_arb_v2_req;

   wire [0:1] sw_final_gnt;
   wire [0:1] sw_final_req;
   wire [0:1] sw_arb_v1_gnt;
   wire [0:1] sw_arb_v2_gnt;
   wire [0:1] sw_arb_v1_req;
   wire [0:1] sw_arb_v2_req;

   
   wire [0:3] vc_gnt_s = (|vc_final_gnt)?(vc_final_gnt[0]?{vc_arb_v1_gnt,2'b0}:{2'b0,vc_arb_v2_gnt}):4'b0;
   wire [0:3] sw_gnt_s = (|sw_final_gnt)?(sw_final_gnt[0]?{sw_arb_v1_gnt,2'b0}:{2'b0,sw_arb_v2_gnt}):4'b0;
   wire [0:1] output_select_q;

  

      c_dff#(
	  // Parameters
	  .width			(2),
	  .reset_type			(reset_type))
   output_select_dff
     (
      // Outputs
      .q				(output_select_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .d				(sw_gnt_s[0:1] |sw_gnt_s[2:3] ));
   c_select_1ofn
     #(
       // Parameters
       .num_ports			(2),
       .width				(int_flit_ctrl_width))
   mux_ctrl
     (
      // Outputs
      .data_out				(flit_ctrl_output),
      // Inputs
      .select				(output_select_q),
      .data_in				(xbc_data_in_ip));
   c_select_1ofn
     #(
       // Parameters
       .num_ports			(2),
       .width				(flit_data_width))
   mux_data
     (
      // Outputs
      .data_out				(flit_data_output),
      // Inputs
      .select				(output_select_q),
      .data_in				(xbd_data_in_ip));
   
   
   generate
      
      genvar 					    ip;
      
      for (ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   
	   //-------------------------------------------------------------------
	   // input controller
	   //-------------------------------------------------------------------
	   
	   wire [0:flit_ctrl_width-1] flit_ctrl_in;
	   assign flit_ctrl_in
	     = flit_ctrl_col_bus[ip*flit_ctrl_width:(ip+1)*flit_ctrl_width-1];
	   
	   wire [0:flit_data_width-1] flit_data_in;
	   assign flit_data_in
	     = flit_data_col_bus[ip*flit_data_width:(ip+1)*flit_data_width-1];
	   

	   
	   wire [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
	   assign vc_gnt_ivc_ovc
	     = vc_gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:(ip+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_nonspec_ivc;
	   assign sw_gnt_nonspec_ivc[0]
 	     = sw_gnt_s[ip] ;
	   assign sw_gnt_nonspec_ivc[1]
 	     = sw_gnt_s[2+ip] ;
	   
	   wire [0:num_vcs-1] 	      sw_gnt_spec_ivc;
	   
	   wire [0:num_vcs*num_ports-1] route_ivc_op;
	   wire [0:num_vcs-1] 		inc_rc_ivc;
	   wire [0:num_vcs-1] 		vc_req_ivc;
	   wire [0:num_vcs-1] 		sw_req_nonspec_ivc;
	   wire [0:num_vcs-1] 		sw_req_spec_ivc;
	   wire [0:int_flit_ctrl_width-1] int_flit_ctrl_out;
	   wire [0:flit_data_width-1] 	  flit_data_out;
	   wire [0:(flow_ctrl_width-1)] 	  flow_ctrl_out;
	   wire 			  ipc_error;
	   vcr_ip_ctrl_mac_yarc_output
	     #(.num_flit_buffers(num_mini_buffers),
	       .num_header_buffers(num_mini_buffers),
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
	       .port_id(ip),
	       .reset_type(reset_type))
	   ipc
	     (.clk(clk),
	      .reset(reset),
	      .router_address(router_address),
	      .flit_ctrl_in(flit_ctrl_in),
	      .flit_data_in(flit_data_in),
	      .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
	      .route_ivc_op(route_ivc_op),
	      .inc_rc_ivc(inc_rc_ivc),
	      .vc_req_ivc(vc_req_ivc),
	      .vc_gnt_ivc({vc_arb_v1_gnt[ip],vc_arb_v2_gnt[ip]}),
	      .vc_gnt_ivc_ovc(4'b1001),
	      .sw_req_nonspec_ivc(sw_req_nonspec_ivc),
	      .sw_req_spec_ivc(sw_req_spec_ivc),
	      .sw_gnt_nonspec_ivc(sw_gnt_nonspec_ivc),
	      .sw_gnt_spec_ivc(sw_gnt_spec_ivc),
	      .int_flit_ctrl_out(int_flit_ctrl_out),
	      .flit_data_out(flit_data_out),
	      .flow_ctrl_out(flow_ctrl_out),
	      .error(ipc_error));

	   assign inc_rc_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = inc_rc_ivc;


	   assign vc_arb_v1_req[ip]  = vc_req_ivc[0] & elig_ovc[0];
	   assign vc_arb_v2_req[ip]  = vc_req_ivc[1] & elig_ovc[1];

	   assign sw_arb_v1_req[ip]  = sw_req_nonspec_ivc[0];
	   assign sw_arb_v2_req[ip]  = sw_req_nonspec_ivc[1];
	   
	   assign xbc_data_in_ip[ip*int_flit_ctrl_width:
				 (ip+1)*int_flit_ctrl_width-1]
		    = int_flit_ctrl_out;
	   assign xbd_data_in_ip[ip*flit_data_width:(ip+1)*flit_data_width-1]
		    = flit_data_out;
	   assign flow_ctrl_col_bus[ip*(flow_ctrl_width):
				    (ip+1)*(flow_ctrl_width)-1]
 								   = flow_ctrl_out;
	   assign ipc_error_ip[ip] 				   = ipc_error;
	   
	end
      
   endgenerate




   /////////////////////////////////
   //vc alloc??
   ////////////////////////////////

   
   
   assign vc_final_req[0] 						   = (|vc_arb_v1_req);
   assign vc_final_req[1] 						   = (|vc_arb_v2_req);
   
   
   c_rr_arbiter
     #(
       // Parameters
       .num_ports			(2),
       .reset_type			(reset_type))
   arb_vall
     (
      // Outputs
      .gnt				(vc_final_gnt[0:1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .update				(1'b1),
      .req				(vc_final_req[0:1]));
   



   c_rr_arbiter
     #(
       // Parameters
       .num_ports			(2),
       .reset_type			(reset_type))
   arb_v1
     (
      // Outputs
      .gnt				(vc_arb_v1_gnt[0:1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .update				(vc_final_gnt[0]),
      .req				(vc_arb_v1_req[0:1]));

   c_rr_arbiter
     #(
       // Parameters
       .num_ports			(2),
       .reset_type			(reset_type))
   arb_v2
     (
      // Outputs
      .gnt				(vc_arb_v2_gnt[0:1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .update				(vc_final_gnt[1]),
      .req				(vc_arb_v2_req[0:1]));



   ////////////////////////////////
       //sw arbiter
   ///////////////////////////////
   assign sw_final_req[0] 						   = (|sw_arb_v1_req);
   assign sw_final_req[1] 						   = (|sw_arb_v2_req);
   
   
   c_rr_arbiter
     #(
       // Parameters
       .num_ports			(2),
       .reset_type			(reset_type))
   sw_arb_vall
     (
      // Outputs
      .gnt				(sw_final_gnt[0:1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .update				(1'b1),
      .req				(sw_final_req[0:1]));
   



   c_rr_arbiter
     #(
       // Parameters
       .num_ports			(2),
       .reset_type			(reset_type))
   sw_arb_v1
     (
      // Outputs
      .gnt				(sw_arb_v1_gnt[0:1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .update				(sw_final_gnt[0]),
      .req				(sw_arb_v1_req[0:1]));

   c_rr_arbiter
     #(
       // Parameters
       .num_ports			(2),
       .reset_type			(reset_type))
   sw_arb_v2
     (
      // Outputs
      .gnt				(sw_arb_v2_gnt[0:1]),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .update				(sw_final_gnt[1]),
      .req				(sw_arb_v2_req[0:1]));
   ////////////////////////////////
   //output module
   ////////////////////////////////
   
   vcr_op_ctrl_mac_yarc_output
     #(/*autoinstparam*/
       // Parameters
       .num_flit_buffers		(num_flit_buffers),
       .num_header_buffers		(num_flit_buffers),
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
       .checker_enable			(checker_enable),
       .checker_capture_mode		(checker_capture_mode),
       .track_vcs_at_output		(track_vcs_at_output),
       .credit_handling_type		(credit_handling_type),
       .cred_level_width		(2),
       .reset_type			(reset_type))
   final_output
     (/*autoinst*/
      // Outputs
      .flit_ctrl_out			(flit_ctrl_out_tile[0:flit_ctrl_width-1]),
      .flit_data_out			(flit_data_out_tile[0:flit_data_width-1]),
      .elig_ovc				(elig_ovc[0:num_vcs-1]),
      .int_flow_ctrl_ovc		(int_flow_ctrl_op_ovc[0:num_vcs*int_flow_ctrl_width-1]),
      .error				(error),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .flow_ctrl_in			({flow_ctrl_in_tile[0],~flow_ctrl_in_tile[1],flow_ctrl_in_tile[1]}),
      .vc_gnt_ovc			(vc_final_gnt),
      .vc_gnt_ovc_ip			(vc_gnt_s),
      .vc_gnt_ovc_ivc			({vc_final_gnt,vc_final_gnt}),
      .xbr_ctrl_ip			(output_select_q[0:num_ports-1]),
      .int_flit_ctrl_in			(flit_ctrl_output[0:int_flit_ctrl_width-1]),
      .flit_data_in			(flit_data_output[0:flit_data_width-1]));
   

   
endmodule
