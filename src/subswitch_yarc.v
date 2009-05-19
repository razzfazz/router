module subswitch_yarc(/*autoarg*/
   // Outputs
   flow_ctrl_row_bus, flit_data_col_bus, flit_ctrl_col_bus,
   // Inputs
   flit_ctrl_row_bus, flit_data_row_bus, flow_ctrl_col_bus, clk,
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
   
   // flit buffer entries per VC  input buffer
   parameter num_flit_buffers 	    = 128;
   parameter num_row_buffers 	    = 32;
   parameter num_col_buffers 	    = 8;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers     = 8;
   
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
   
   // width of flow control signals hack hack hack
   localparam flow_ctrl_width = 1 + vc_idx_width+1;
   
   // enable performance counter
   parameter perf_ctr_enable = 0;
   
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

   //=================
   //End of param
   //=================


   input [0:num_vcs*num_ports*flit_ctrl_width-1]  flit_ctrl_row_bus;
   input [0:num_vcs*num_ports*flit_data_width-1]  flit_data_row_bus;
   output [0:num_ports*(flow_ctrl_width)-1] flow_ctrl_row_bus;
   
   output [0:num_ports*flit_data_width-1] flit_data_col_bus;
   output [0:num_ports*flit_ctrl_width-1] flit_ctrl_col_bus;
   input [0:num_ports*(flow_ctrl_width-1)-1] flow_ctrl_col_bus;

   input clk;
   input reset;
   
   input [0:router_addr_width-1] router_address;

   
   wire [0:num_vcs*num_ports*int_flit_ctrl_width-1]  int_flit_ctrl_sub;
   wire [0:num_vcs*num_ports*flit_data_width-1]  flit_data_sub;
   wire [0:num_vcs*num_ports*(flow_ctrl_width-1)-1] flow_ctrl_sub;

   
   wire [0:2*8*int_flow_ctrl_width-1] int_flow_ctrl_op_ovc;
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] 	    vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_nonspec_ip_ivc;

   wire [0:num_ports*num_vcs*num_ports-1] 	    route_ip_ivc_op;   
   wire [0:num_ports*num_vcs-1] 		    sw_req_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    vc_req_ip_ivc;
   wire [0:num_ports*int_flit_ctrl_width-1] 	    xbc_data_in_ip;   
   wire [0:num_ports*flit_data_width-1] 	    xbd_data_in_ip;

   wire [0:num_ports*num_vcs-1] 		    inc_rc_ip_ivc;


   //combine the two input vcs into a single input ot the xbr according to the sw gnts
   wire [0:num_ports*num_vcs-1] xbr_input_mux_signal;
     c_dff
     #(.width(num_ports*num_vcs),
       .reset_type(reset_type))
   xbr_input_mux
     (.clk(clk),
      .reset(reset),
      .d(sw_gnt_nonspec_ip_ivc),
      .q(xbr_input_mux_signal));
   
   generate
      genvar column,vcs;
      for(column = 0; column<num_ports; column = column +1)
	begin:columns
	   for(vcs = 0; vcs<2; vcs = vcs+1)
	     begin: vcss
		wire [0:num_vcs*num_ports-1] route_ivc_op;
		wire [0:num_vcs-1] 		     inc_rc_ivc;
		wire [0:num_vcs-1] 		     vc_req_ivc;
		wire [0:num_vcs-1] 		     sw_req_nonspec_ivc;
		wire [0:num_vcs-1] 		     sw_req_spec_ivc;
		wire [0:num_vcs-1] 	      vc_gnt_ivc;
		wire [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
		wire [0:num_vcs-1] 	      sw_gnt_nonspec_ivc;
		wire 			     ipc_error;
		wire head    = flit_ctrl_row_bus[(column*2+vcs)*flit_ctrl_width] & flit_ctrl_row_bus[(column*2+vcs)*flit_ctrl_width+2];
		wire last_access;
		wire access  = head?flit_data_row_bus[(column*2+vcs)*flit_data_width+column]:last_access;
	
		
		c_dff
		  #(.width(1),
		    .reset_type(reset_type))
		xbr_input_mux
		  (.clk(clk),
		   .reset(reset),
		   .d(access),
		   .q(last_access));
		wire real_valid  = flit_ctrl_row_bus[(column*2+vcs)*flit_ctrl_width]  &access;
		

		
		assign vc_gnt_ivc[1-vcs] 		  =1'b0;
		assign vc_gnt_ivc[vcs] 			  = vc_gnt_ip_ivc[(column*num_vcs+vcs)];
		assign vc_gnt_ivc_ovc[(1-vcs)*num_vcs:(1-vcs+1)*num_vcs-1] = 2'b00;
		assign vc_gnt_ivc_ovc[(vcs)*num_vcs:(vcs+1)*num_vcs-1] 
 		  =  vc_gnt_ip_ivc_ovc[(column*num_vcs+vcs)*num_vcs:(column*num_vcs+vcs+1)*num_vcs-1];
		assign sw_gnt_nonspec_ivc[1-vcs] 	  = 1'b0;
		assign sw_gnt_nonspec_ivc[vcs] 	  
 		  = sw_gnt_nonspec_ip_ivc[(column*num_vcs+vcs)];
		
		vcr_ip_ctrl_mac_yarc
		  #(.num_flit_buffers(num_row_buffers),
		    .num_header_buffers(num_row_buffers),
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
		    .port_id(column),
		    .vc_id(vcs),
		    .reset_type(reset_type),
		    .routing_dimension(1))
		ipc
		  (
		   // Outputs
		   .route_ivc_op(route_ivc_op), //wtf??
		   .inc_rc_ivc(inc_rc_ivc), //wtf??
		   .vc_req_ivc(vc_req_ivc), //feed it right back
		   .sw_req_nonspec_ivc(sw_req_nonspec_ivc), //feed it right back
		   .sw_req_spec_ivc(sw_req_spec_ivc), //no speculation
		   .int_flit_ctrl_out(int_flit_ctrl_sub[(column*2+vcs)*int_flit_ctrl_width:(column*2+vcs+1)*int_flit_ctrl_width-1]),
		   .flit_data_out(flit_data_sub[(column*2+vcs)*flit_data_width:(column*2+vcs+1)*flit_data_width-1]),
		   .flow_ctrl_out(flow_ctrl_sub[(column*2+vcs)*(flow_ctrl_width-1):(column*2+vcs+1)*(flow_ctrl_width-1)-1]),
		   .error(ipc_error),
		   
		   // Inputs
		   .clk(clk),
		   .reset(reset),    
		   .router_address(router_address),
		   .flit_ctrl_in({real_valid,flit_ctrl_row_bus[(column*2+vcs)*flit_ctrl_width+1:(column*2+vcs+1)*flit_ctrl_width-1]}),
		   .flit_data_in(flit_data_row_bus[(column*2+vcs)*flit_data_width:(column*2+vcs+1)*flit_data_width-1]),
		   .int_flow_ctrl_op_ovc(int_flow_ctrl_op_ovc),
		   .vc_gnt_ivc(vc_gnt_ivc),//feed it right back
		   .vc_gnt_ivc_ovc(vc_gnt_ivc_ovc), ///wtf?
		   .sw_gnt_nonspec_ivc(sw_gnt_nonspec_ivc), //feed it right back
		   .sw_gnt_spec_ivc(2'b00) //no speculation
		   );


	
		assign vc_req_ip_ivc[(column*num_vcs+vcs)] = vc_req_ivc[vcs];
		assign sw_req_nonspec_ip_ivc[(column*num_vcs+vcs):(column*num_vcs+vcs+1)-1]= sw_req_nonspec_ivc[vcs];
		assign route_ip_ivc_op[(column*num_vcs+vcs)*num_ports:(column*num_vcs+vcs+1)*num_ports-1]
 		  = route_ivc_op[vcs*num_ports:(vcs+1)*num_ports-1];
		
		assign inc_rc_ip_ivc[(column*num_vcs+vcs):(column*num_vcs+vcs+1)-1] = inc_rc_ivc[vcs];
	     end // block: vcss
	   assign xbc_data_in_ip[(column)*int_flit_ctrl_width:
				 (column+1)*int_flit_ctrl_width-1]
 	       = xbr_input_mux_signal[(column*num_vcs+0)]?int_flit_ctrl_sub[(column*2+0)*int_flit_ctrl_width:
						 (column*2+0+1)*int_flit_ctrl_width-1]:
		 int_flit_ctrl_sub[(column*2+1)*int_flit_ctrl_width
				   :(column*2+1+1)*int_flit_ctrl_width-1];
	   
	   assign xbd_data_in_ip[(column)*flit_data_width:
				 (column+1)*flit_data_width-1]
 	     = xbr_input_mux_signal[(column*num_vcs+0)]?flit_data_sub[(column*2+0)*flit_data_width:
					   (column*2+0+1)*flit_data_width-1]:
	       flit_data_sub[(column*2+1)*flit_data_width:
			     (column*2+1+1)*flit_data_width-1];
	   
	   assign flow_ctrl_row_bus[column*flow_ctrl_width+0] 		
 	     = flow_ctrl_sub[(column*2+0)*(flow_ctrl_width-1)] | flow_ctrl_sub[(column*2+1)*(flow_ctrl_width-1)];
	   assign flow_ctrl_row_bus[column*flow_ctrl_width+1]
 	     = flow_ctrl_sub[(column*2+0)*(flow_ctrl_width-1)];
	   assign flow_ctrl_row_bus[column*flow_ctrl_width+2]
 	     =flow_ctrl_sub[(column*2+1)*(flow_ctrl_width-1)];

	end
   endgenerate

   ///////////////////////////////////////////////////////////////
   //vc allocator hack hack hack
   //there shouldn't be a vc allocator
   //////////////////////////////////////////////////////////////
   
   wire [0:num_ports*num_vcs-1] 		    vc_gnt_op_ovc;
   wire [0:num_ports*num_vcs*num_ports-1] vc_gnt_op_ovc_ip;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_gnt_op_ovc_ivc;
   wire [0:num_ports*num_vcs-1] 	elig_op_ovc;
   

   vcr_vc_alloc_mac
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .arbiter_type(vc_arbiter_type),
       .allocator_type(vc_allocator_type),
       .reset_type(reset_type))
   vca
     (.clk(clk),
      .reset(reset),
      .route_ip_ivc_op(route_ip_ivc_op),
      .inc_rc_ip_ivc(inc_rc_ip_ivc),
      .elig_op_ovc(elig_op_ovc),
      .req_ip_ivc(vc_req_ip_ivc),
      .gnt_ip_ivc(vc_gnt_ip_ivc),
      .gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
      .gnt_op_ovc(vc_gnt_op_ovc),
      .gnt_op_ovc_ip(vc_gnt_op_ovc_ip),
      .gnt_op_ovc_ivc(vc_gnt_op_ovc_ivc));




   
   //---------------------------------------------------------------------------
   // switch allocator
   //---------------------------------------------------------------------------

   wire [0:num_ports*num_ports-1] 		    sw_gnt_ip_op;   
   wire [0:num_ports*num_vcs-1] 		    sw_req_spec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 		    sw_gnt_spec_ip_ivc;//ignored no spec
   vcr_sw_alloc_mac
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .allocator_type(sw_allocator_type),
       .arbiter_type(sw_arbiter_type),
       .spec_level(sw_spec_level),
       .reset_type(reset_type))
   swa
     (.clk(clk),
      .reset(reset),
      .route_ip_ivc_op(route_ip_ivc_op),
      .req_nonspec_ip_ivc(sw_req_nonspec_ip_ivc),
      .req_spec_ip_ivc(sw_req_spec_ip_ivc), //ignored no spec
      .gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
      .gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc), //ignored no spec
      .gnt_ip_op(sw_gnt_ip_op));
   
   //---------------------------------------------------------------------------
   // crossbar
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	  xbr_ctrl_ip_op_s, xbr_ctrl_ip_op_q;
   assign xbr_ctrl_ip_op_s = sw_gnt_ip_op;
   c_dff
     #(.width(num_ports*num_ports),
       .reset_type(reset_type))
   xbr_ctrl_ip_opq
     (.clk(clk),
      .reset(reset),
      .d(xbr_ctrl_ip_op_s),
      .q(xbr_ctrl_ip_op_q));
   
   wire [0:num_ports*int_flit_ctrl_width-1] xbc_data_out_op;
   c_crossbar
     #(.num_in_ports(num_ports),
       .num_out_ports(num_ports),
       .width(int_flit_ctrl_width),
       .crossbar_type(xbc_crossbar_type))
   xbc
     (.ctrl_ip_op(xbr_ctrl_ip_op_q),
      .data_in_ip(xbc_data_in_ip),
      .data_out_op(xbc_data_out_op));
   
   wire [0:num_ports*flit_data_width-1]     xbd_data_out_op;
   c_crossbar
     #(.num_in_ports(num_ports),
       .num_out_ports(num_ports),
       .width(flit_data_width),
       .crossbar_type(xbd_crossbar_type))
   xbd
     (.ctrl_ip_op(xbr_ctrl_ip_op_q),
      .data_in_ip(xbd_data_in_ip),
      .data_out_op(xbd_data_out_op));



   //-------------------------------------------------------------------------
   // output
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] xbr_ctrl_op_ip;
   c_interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   xbr_ctrl_op_ip_intl
     (.data_in(xbr_ctrl_ip_op_q),
      .data_out(xbr_ctrl_op_ip));
   
   wire [0:num_ports-1] 	  opc_error_op;
   
   generate
      
      genvar 			  op;
      
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:int_flit_ctrl_width-1] int_flit_ctrl_in;
	   assign int_flit_ctrl_in
	     = xbc_data_out_op[op*int_flit_ctrl_width:
			       (op+1)*int_flit_ctrl_width-1];
	   
	   wire [0:flit_data_width-1] flit_data_in;
	   assign flit_data_in
	     = xbd_data_out_op[op*flit_data_width:(op+1)*flit_data_width-1];
	   
	   wire [0:flow_ctrl_width-1-1] flow_ctrl_in;
	   assign flow_ctrl_in
	     = flow_ctrl_col_bus[op*(flow_ctrl_width-1):(op+1)*(flow_ctrl_width-1)-1];
	   
	   wire [0:num_vcs-1] 	      vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
	   
	   wire [0:num_vcs*num_ports-1] vc_gnt_ovc_ip;
	   assign vc_gnt_ovc_ip = vc_gnt_op_ovc_ip[op*num_vcs*num_ports:
						   (op+1)*num_vcs*num_ports-1];
	   
	   wire [0:num_vcs*num_vcs-1] 	vc_gnt_ovc_ivc;
	   assign vc_gnt_ovc_ivc = vc_gnt_op_ovc_ivc[op*num_vcs*num_vcs:
						     (op+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_ports-1] 	xbr_ctrl_ip;
	   assign xbr_ctrl_ip = xbr_ctrl_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire [0:flit_ctrl_width-1] 	flit_ctrl_out;
	   wire [0:flit_data_width-1] 	flit_data_out;
	   wire [0:num_vcs-1] 		elig_ovc;
	   wire [0:num_vcs*int_flow_ctrl_width-1] int_flow_ctrl_ovc;
	   wire 				  opc_error;
	   vcr_op_ctrl_mac
	     #(.num_flit_buffers(num_col_buffers),
	       .num_header_buffers(num_col_buffers),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_vcs_per_class(num_vcs_per_class),
	       .num_ports(num_ports),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .num_dimensions(num_dimensions),
	       .packet_format(packet_format),
	       .max_payload_length(max_payload_length),
	       .min_payload_length(min_payload_length),
	       .flit_data_width(flit_data_width),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .track_vcs_at_output(track_vcs_at_output),
	       .credit_handling_type(credit_handling_type),
	       .cred_level_width(2),
	       .reset_type(reset_type))
	   opc
	     (.clk(clk),
	      .reset(reset),
	      .flow_ctrl_in(flow_ctrl_in),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .vc_gnt_ovc_ip(vc_gnt_ovc_ip),
	      .vc_gnt_ovc_ivc(vc_gnt_ovc_ivc),
	      .xbr_ctrl_ip(xbr_ctrl_ip),
	      .int_flit_ctrl_in(int_flit_ctrl_in),
	      .flit_data_in(flit_data_in),
	      .flit_ctrl_out(flit_ctrl_out),
	      .flit_data_out(flit_data_out),
	      .elig_ovc(elig_ovc),
	      .int_flow_ctrl_ovc(int_flow_ctrl_ovc),
	      .error(opc_error));
	   
	   assign flit_ctrl_col_bus[op*flit_ctrl_width:(op+1)*flit_ctrl_width-1]
		    = flit_ctrl_out;
	   assign flit_data_col_bus[op*flit_data_width:(op+1)*flit_data_width-1]
		    = flit_data_out;
	   
	   assign elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = elig_ovc;
	   assign int_flow_ctrl_op_ovc[op*num_vcs*int_flow_ctrl_width:
				       (op+1)*num_vcs*int_flow_ctrl_width-1]
		    = int_flow_ctrl_ovc;
	   
	   assign opc_error_op[op] = opc_error;
	   
	end
      
   endgenerate

   
   
endmodule
   
