module testbench
  ();
   
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

      function integer pop_count(input integer argument);
      integer i;
      begin
	 pop_count 		   = 0;
	 for(i = argument; i > 0; i = i >> 1)
	   pop_count 		   = pop_count + (i & 1);
      end
   endfunction
   // flit buffer entries per VC  input buffer
   parameter num_flit_buffers 	    = 128;
   parameter num_row_buffers 	    = 8;
   parameter num_col_buffers 	    = 4;
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers     = num_flit_buffers;
   
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
   parameter max_payload_length     = 0;
   
   // minimum payload length (in flits)
   // (note: only used if packet_format==`PACKET_FORMAT_EXPLICIT_LENGTH)
   parameter min_payload_length     = 0;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width 	    = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width     = num_dimensions * dim_addr_width;
   
   // width of flit control signals
   localparam flit_ctrl_width 	    = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
				 (1 + vc_idx_width + 1 + 1) : 
				 (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
				 (1 + vc_idx_width + 1) : 
				 -1;
   
   // width of flit payload data
   parameter flit_data_width = 32;
   
   // width of flow control signals HACK HACK HACK
   localparam flow_ctrl_width = 1 + vc_idx_width+1;
   
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
   parameter header_fifo_type 	 = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type 	 = `REGFILE_TYPE_FF_2D;
   
   // number of entries in flit buffer
   localparam fbf_depth 	 = num_vcs*num_flit_buffers;
   
   // required address size for flit buffer
   localparam fbf_addr_width 	 = clogb(fbf_depth);
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type 	 = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type 	 = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type 	 = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type 	 = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level 	 = `SW_SPEC_LEVEL_NONE;
   
   localparam sw_spec_enable 	 = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select implementation variant for control crossbar
   parameter xbc_crossbar_type 	 = `CROSSBAR_TYPE_MUX;
   
   // select implementation variant for data crossbar
   parameter xbd_crossbar_type 	 = `CROSSBAR_TYPE_MUX;
   
   parameter reset_type 	 = `RESET_TYPE_ASYNC;


   //				   =================
   //End of yarc param
   //				   =================


   //packet source params
   parameter max_packet_count 	 = -1;
   parameter packet_rate 	 = 24;
   parameter side_packet_rate 	 = 3;
   
   parameter initial_seed 	 = 0;
   parameter packet_count_width  = 32;
   parameter restrict_turns 	 = 0;
   parameter port_id 		 = 0;
   parameter packet_length_mode  = 0;
   //end packet source params
   
   parameter end_time 		 = 10000;
   parameter Tclk 		 = 5;
   



   wire [0:flit_ctrl_width-1] flit_ctrl;
   wire [0:flit_data_width-1] flit_data;
   wire [0:flow_ctrl_width-1] flow_ctrl;
  
   wire error;
   wire [0:packet_count_width-1] out_flits;
   reg reset, clk_en,run,clk;


   wire [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_out_row_bus; 
   wire [0:num_vcs*flit_data_width-1] flit_data_out_row_bus;
   wire [0:num_vcs*flit_ctrl_width-1] flit_ctrl_out_row_bus;
   wire [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_out_col_bus;
   wire [0:(num_ports-1)*flit_data_width-1] flit_data_out_col_bus;
   wire [0:(num_ports-1)*(flow_ctrl_width-1)-1] flow_ctrl_out_col_bus;
   wire [0:flow_ctrl_width-1] flow_ctrl_out_tile;
   wire [0:flit_ctrl_width-1] flit_ctrl_out_tile;
   wire [0:flit_data_width-1] flit_data_out_tile;   
   wire [0:router_addr_width-1] router_address;
   assign router_address  = 6'b000000;
   
   wire [0:num_vcs*(num_ports-1)*flit_ctrl_width-1] flit_ctrl_in_row_bus;
   wire [0:num_vcs*(num_ports-1)*flit_data_width-1] flit_data_in_row_bus;
   wire [0:(num_ports-1)*flow_ctrl_width-1] flow_ctrl_in_row_bus;
   wire [0:(num_ports-1)*(flow_ctrl_width-1)-1] flow_ctrl_in_col_bus;
   wire [0:(num_ports-1)*flit_ctrl_width-1] flit_ctrl_in_col_bus;
   wire [0:(num_ports-1)*flit_data_width-1] flit_data_in_col_bus;
   wire [0:flit_ctrl_width-1] flit_ctrl_in_tile;
   wire [0:flit_data_width-1] flit_data_in_tile;
   wire [0:flow_ctrl_width-1] flow_ctrl_in_tile;



   
   
   
   packet_source_yarc #(
		   // Parameters
		   .max_packet_count	(max_packet_count),
		   .packet_rate		(packet_rate),
		   .initial_seed	(initial_seed),
		   .packet_count_width	(packet_count_width),
		   .num_flit_buffers	(num_flit_buffers),
		   .num_header_buffers	(num_flit_buffers),
		   .num_traffic_classes	(num_traffic_classes),
		   .num_routing_classes	(num_routing_classes),
		   .num_vcs_per_class	(num_vcs_per_class),
		   .num_ports		(num_ports),
		   .num_dimensions	(num_dimensions),
		   .num_routers_per_dim	(num_routers_per_dim),
		   .router_address	(0),
		   .num_neighbors_per_dim(num_neighbors_per_dim),
		   .packet_format	(packet_format),
		   .max_payload_length	(max_payload_length),
		   .min_payload_length	(min_payload_length),
		   .flit_data_width	(flit_data_width),
		   .restrict_turns	(restrict_turns),
		   .routing_function_type(routing_function_type),
		   .dimension_order	(dimension_order),
		   .port_id		(port_id),
		   .packet_length_mode	(packet_length_mode))
   ps (
	// Outputs
	.flit_ctrl			(flit_ctrl[0:flit_ctrl_width-1]),
	.flit_data			(flit_data[0:flit_data_width-1]),
	.out_flits			(out_flits[0:packet_count_width-1]),
	.error				(error),
	// Inputs
	.clk				(clk),
	.reset				(reset),
	.flow_ctrl			(flow_ctrl[0:flow_ctrl_width-1]),
	.run				(run));

   wire packets_in;
   wire self_out;
   wire [0:num_ports-1-1] col_out;
   wire [0:1] row_out;
   
   assign packets_in  =flit_ctrl[0];
   assign self_out    = flit_ctrl_out_tile[0];
   assign col_out[0:num_ports-1-1] = {flit_ctrl_out_col_bus[0*flit_ctrl_width],
				      flit_ctrl_out_col_bus[1*flit_ctrl_width],
				      flit_ctrl_out_col_bus[2*flit_ctrl_width],
				      flit_ctrl_out_col_bus[3*flit_ctrl_width],
				      flit_ctrl_out_col_bus[4*flit_ctrl_width],
				      flit_ctrl_out_col_bus[5*flit_ctrl_width],
				      flit_ctrl_out_col_bus[6*flit_ctrl_width]
				      };
   assign row_out[0:1] = {flit_ctrl_out_row_bus[0],
			  flit_ctrl_out_row_bus[flit_ctrl_width]};
   
   
   
/*

   yarc_tile  #(
		// Parameters
		.num_flit_buffers		(num_flit_buffers),
		.num_row_buffers		(num_row_buffers),
		.num_col_buffers		(num_col_buffers),
		.num_header_buffers	(num_header_buffers),
		.num_traffic_classes	(num_traffic_classes),
		.num_routing_classes	(num_routing_classes),
		.num_vcs_per_class		(num_vcs_per_class),
		.num_ports			(num_ports),
		.num_dimensions		(num_dimensions),
		.num_routers_per_dim	(num_routers_per_dim),
		.num_neighbors_per_dim	(num_neighbors_per_dim),
		.packet_format		(packet_format),
		.max_payload_length	(max_payload_length),
		.min_payload_length	(min_payload_length),
		.flit_data_width		(flit_data_width),
		.perf_ctr_enable		(perf_ctr_enable),
		.perf_ctr_width		(perf_ctr_width),
		.checker_enable		(checker_enable),
		.checker_capture_mode	(checker_capture_mode),
		.track_vcs_at_output	(track_vcs_at_output),
		.routing_function_type	(routing_function_type),
		.dimension_order		(dimension_order),
		.credit_handling_type	(credit_handling_type),
		.header_fifo_type		(header_fifo_type),
		.fbf_regfile_type		(fbf_regfile_type),
		.vc_allocator_type		(vc_allocator_type),
		.vc_arbiter_type		(vc_arbiter_type),
		.sw_allocator_type		(sw_allocator_type),
		.sw_arbiter_type		(sw_arbiter_type),
		.sw_spec_level		(sw_spec_level),
		.xbc_crossbar_type		(xbc_crossbar_type),
		.xbd_crossbar_type		(xbd_crossbar_type),
		.reset_type		(reset_type))
   dut (
	// Outputs
	.flow_ctrl_out_row_bus		(flow_ctrl_out_row_bus[0:(num_ports-1)*flow_ctrl_width-1]),
	.flit_data_out_row_bus		(flit_data_out_row_bus[0:num_vcs*flit_data_width-1]),
	.flit_ctrl_out_row_bus		(flit_ctrl_out_row_bus[0:num_vcs*flit_ctrl_width-1]),
	.flit_ctrl_out_col_bus		(flit_ctrl_out_col_bus[0:(num_ports-1)*flit_ctrl_width-1]),
	.flit_data_out_col_bus		(flit_data_out_col_bus[0:(num_ports-1)*flit_data_width-1]),
	.flow_ctrl_out_col_bus		(flow_ctrl_out_col_bus[0:(num_ports-1)*(flow_ctrl_width-1)-1]),
	.flow_ctrl_out_tile		(flow_ctrl_out_tile[0:flow_ctrl_width-1]),
	.flit_ctrl_out_tile		(flit_ctrl_out_tile[0:flit_ctrl_width-1]),
	.flit_data_out_tile		(flit_data_out_tile[0:flit_data_width-1]),
	.error				(error),
	// Inputs
	.clk				(clk),
	.reset				(reset),
	.router_address			(router_address[0:router_addr_width-1]),
	.flit_ctrl_in_row_bus		(flit_ctrl_in_row_bus[0:num_vcs*(num_ports-1)*flit_ctrl_width-1]),
	.flit_data_in_row_bus		(flit_data_in_row_bus[0:num_vcs*(num_ports-1)*flit_data_width-1]),
	.flow_ctrl_in_row_bus		(flow_ctrl_in_row_bus[0:(num_ports-1)*flow_ctrl_width-1]),
	.flow_ctrl_in_col_bus		(flow_ctrl_in_col_bus[0:(num_ports-1)*(flow_ctrl_width-1)-1]),
	.flit_ctrl_in_col_bus		(flit_ctrl_in_col_bus[0:(num_ports-1)*flit_ctrl_width-1]),
	.flit_data_in_col_bus		(flit_data_in_col_bus[0:(num_ports-1)*flit_data_width-1]),
	.flit_ctrl_in_tile			(flit_ctrl_in_tile[0:flit_ctrl_width-1]),
	.flit_data_in_tile			(flit_data_in_tile[0:flit_data_width-1]),
	.flow_ctrl_in_tile			(flow_ctrl_in_tile[0:flow_ctrl_width-1]));

   */
   yarc_tile
dut (
	// Outputs
	.flow_ctrl_out_row_bus		(flow_ctrl_out_row_bus[0:(num_ports-1)*flow_ctrl_width-1]),
	.flit_data_out_row_bus		(flit_data_out_row_bus[0:num_vcs*flit_data_width-1]),
	.flit_ctrl_out_row_bus		(flit_ctrl_out_row_bus[0:num_vcs*flit_ctrl_width-1]),
	.flit_ctrl_out_col_bus		(flit_ctrl_out_col_bus[0:(num_ports-1)*flit_ctrl_width-1]),
	.flit_data_out_col_bus		(flit_data_out_col_bus[0:(num_ports-1)*flit_data_width-1]),
	.flow_ctrl_out_col_bus		(flow_ctrl_out_col_bus[0:(num_ports-1)*(flow_ctrl_width-1)-1]),
	.flow_ctrl_out_tile		(flow_ctrl_out_tile[0:flow_ctrl_width-1]),
	.flit_ctrl_out_tile		(flit_ctrl_out_tile[0:flit_ctrl_width-1]),
	.flit_data_out_tile		(flit_data_out_tile[0:flit_data_width-1]),
	.error				(error),
	// Inputs
	.clk				(clk),
	.reset				(reset),
	.router_address			(router_address[0:router_addr_width-1]),
	.flit_ctrl_in_row_bus		(flit_ctrl_in_row_bus[0:num_vcs*(num_ports-1)*flit_ctrl_width-1]),
	.flit_data_in_row_bus		(flit_data_in_row_bus[0:num_vcs*(num_ports-1)*flit_data_width-1]),
	.flow_ctrl_in_row_bus		(flow_ctrl_in_row_bus[0:(num_ports-1)*flow_ctrl_width-1]),
	.flow_ctrl_in_col_bus		(flow_ctrl_in_col_bus[0:(num_ports-1)*(flow_ctrl_width-1)-1]),
	.flit_ctrl_in_col_bus		(flit_ctrl_in_col_bus[0:(num_ports-1)*flit_ctrl_width-1]),
	.flit_data_in_col_bus		(flit_data_in_col_bus[0:(num_ports-1)*flit_data_width-1]),
	.flit_ctrl_in_tile			(flit_ctrl_in_tile[0:flit_ctrl_width-1]),
	.flit_data_in_tile			(flit_data_in_tile[0:flit_data_width-1]),
	.flow_ctrl_in_tile			(flow_ctrl_in_tile[0:flow_ctrl_width-1]));
   

   assign flit_ctrl_in_tile 	= flit_ctrl;
   assign flit_data_in_tile 	= flit_data;
   assign flow_ctrl 		= flow_ctrl_out_tile;

/*
   generate
      genvar ecols;
      for(ecols =0; ecols <7; ecols=ecols+1)
	begin:ecolss
	   packet_source
		 #(
		   // Parameters
		   .max_packet_count	(max_packet_count),
		   .packet_rate		(20),
		   .initial_seed	(initial_seed+ecols+10),
		   .packet_count_width	(packet_count_width),
		   .num_flit_buffers	(num_col_buffers),
		   .num_header_buffers	(num_col_buffers),
		   .num_traffic_classes	(num_traffic_classes),
		   .num_routing_classes	(num_routing_classes),
		   .num_vcs_per_class	(num_vcs_per_class),
		   .num_ports		(num_ports),
		   .num_dimensions	(num_dimensions),
		   .num_routers_per_dim	(num_routers_per_dim),
		   .router_address	(0),
		   .num_neighbors_per_dim(num_neighbors_per_dim),
		   .packet_format	(packet_format),
		   .max_payload_length	(max_payload_length),
		   .min_payload_length	(min_payload_length),
		   .flit_data_width	(flit_data_width),
		   .restrict_turns	(restrict_turns),
		   .routing_function_type(routing_function_type),
		   .dimension_order	(dimension_order),
		   .port_id		(port_id),
		   .packet_length_mode	(packet_length_mode))
	   psecol
		 (
		  // Outputs
		  .flit_ctrl		(flit_ctrl_in_col_bus[ecols*flit_ctrl_width:(ecols+1)*flit_ctrl_width-1]),
		  .flit_data		(flit_data_in_col_bus[ecols*flit_data_width:(ecols+1)*flit_data_width-1]),
		  .out_flits		(out_flits[0:packet_count_width-1]),
		  .error		(error),
		  // Inputs
		  .clk			(clk),
		  .reset		(reset),
		  .flow_ctrl		(flow_ctrl_out_col_bus[(ecols)*(flow_ctrl_width-1):(ecols+1)*(flow_ctrl_width-1)-1]),
		  .run			(run));
	   
	   
	   end
   endgenerate

   

   generate
      genvar erows,vcs;
      for(erows =0; erows <7; erows=erows+1)
	begin:erowss
	   for(vcs = 0; vcs<2; vcs= vcs+1)
	     begin: vcss
		packet_source_yarc 
		 #(
		   // Parameters
		   .max_packet_count	(max_packet_count),
		   .packet_rate		(2),
		   .initial_seed	(initial_seed),
		   .packet_count_width	(packet_count_width),
		   .num_flit_buffers	(num_flit_buffers),
		   .num_header_buffers	(num_flit_buffers),
		   .num_traffic_classes	(num_traffic_classes),
		   .num_routing_classes	(num_routing_classes),
		   .num_vcs_per_class	(num_vcs_per_class),
		   .num_ports		(num_ports),
		   .num_dimensions	(num_dimensions),
		   .num_routers_per_dim	(num_routers_per_dim),
		   .router_address	(0),
		   .num_neighbors_per_dim(num_neighbors_per_dim),
		   .packet_format	(packet_format),
		   .max_payload_length	(max_payload_length),
		   .min_payload_length	(min_payload_length),
		   .flit_data_width	(flit_data_width),
		   .restrict_turns	(restrict_turns),
		   .routing_function_type(routing_function_type),
		   .dimension_order	(dimension_order),
		   .port_id		(port_id),
		   .packet_length_mode	(packet_length_mode))
		ps (
		    // Outputs
		    .flit_ctrl			(flit_ctrl_in_row_bus[(erows*num_vcs+vcs)*flit_ctrl_width:(erows*num_vcs+vcs+1)*flit_ctrl_width-1]),
		    .flit_data			(flit_data_in_row_bus[(erows*num_vcs+vcs)*flit_data_width:(erows*num_vcs+vcs+1)*flit_data_width-1]),
		    .out_flits			(out_flits[0:packet_count_width-1]),
		    .error				(error),
		    // Inputs
		    .clk				(clk),
		    .reset				(reset),
		    .flow_ctrl			(flow_ctrl[0:flow_ctrl_width-1]),
		    .run				(run));
		end
	   
	end
   endgenerate
   */
   //////////////////////////////////////////////////////////
   //test bench hacks
   //////////////////////////////////////////////////////////


   assign flit_ctrl_in_row_bus 	= {((num_ports-1)*flit_ctrl_width){1'b0}};
   assign flit_data_in_row_bus 	= {((num_ports-1)*flit_data_width){1'b0}};
   //assign flow_ctrl_in_row_bus 	={(num_ports-1)*flow_ctrl_width{1'b0}};
   assign flit_ctrl_in_col_bus 	= {((num_ports-1)*flit_ctrl_width){1'b0}};
   assign flit_data_in_col_bus 	= {((num_ports-1)*flit_data_width){1'b0}};
   //assign flow_ctrl_in_col_bus 	={(num_ports-1)*(flow_ctrl_width-1){1'b0}};
   //assign flow_ctrl_in_tile 	={flow_ctrl_width{1'b0}};
   

   c_dff
     #(.width(3),
       .reset_type(reset_type))
   tile_in_credit_gen
     (.clk(clk),
      .reset(reset),
      .d({flit_ctrl_out_tile[0],~flit_ctrl_out_tile[1],flit_ctrl_out_tile[1]}),
      .q(flow_ctrl_in_tile));

   generate
      genvar colgen;
      for(colgen = 0; colgen<num_ports-1;colgen=colgen+1)
	begin: colgengen
	   
	   c_dff
		   #(.width(flow_ctrl_width-1),
		     .reset_type(reset_type))
	   col_bus_credit_gen
		   (.clk(clk),
		    .reset(reset),
		    .d({flit_ctrl_out_col_bus[colgen*flit_ctrl_width:colgen*flit_ctrl_width+1]}),
		    .q(flow_ctrl_in_col_bus[colgen*(flow_ctrl_width-1):(colgen+1)*(flow_ctrl_width-1)-1]));
	   

	   


	   wire valid0 	     = (flit_ctrl_out_row_bus[0] && flit_data_out_row_bus[(0)*flit_data_width+colgen+1]);
	   
	   wire valid1  =(flit_ctrl_out_row_bus[flit_ctrl_width] && flit_data_out_row_bus[(1)*flit_data_width+colgen+1]);
	   
	
		
	   c_dff
	     #(.width(flow_ctrl_width),
	       .reset_type(reset_type))
	   row_gen
	     (.clk(clk),
	      .reset(reset),
	      .d({valid0|valid1,valid0,valid1}),
	      .q(flow_ctrl_in_row_bus[colgen*flow_ctrl_width:(colgen+1)*flow_ctrl_width-1]));
	   
	end // for (colgen = 0; colgen<num_ports-1;colgen=colgen+1)
   endgenerate
   

   /*stats*/

   wire [0:31] count_in_flits_s, count_in_flits_q;
   assign count_in_flits_s
     = 
       count_in_flits_q + pop_count(packets_in);
   
   c_dff
     #(.width(32),
       .reset_type(reset_type))
   count_in_flitsq
     (.clk(clk),
      .reset(reset),
      .d(count_in_flits_s),
      .q(count_in_flits_q));

   wire [0:31] count_in_flits;
   assign count_in_flits = count_in_flits_s;

   wire [0:31] count_self_out_s, count_self_out_q;
   assign count_self_out_s
     = 
       count_self_out_q + pop_count(self_out);
   
   c_dff
     #(.width(32),
       .reset_type(reset_type))
   count_self_outq
     (.clk(clk),
      .reset(reset),
      .d(count_self_out_s),
      .q(count_self_out_q));

   wire [0:31] count_self_out;
   assign count_self_out = count_self_out_s;


    wire [0:31] count_col_out_s, count_col_out_q;
   assign count_col_out_s
     = 
       count_col_out_q + pop_count(col_out);
   
   c_dff
     #(.width(32),
       .reset_type(reset_type))
   count_col_outq
     (.clk(clk),
      .reset(reset),
      .d(count_col_out_s),
      .q(count_col_out_q));

   wire [0:31] count_col_out;
   assign count_col_out = count_col_out_s;

    wire [0:31] count_row_out_s, count_row_out_q;
   assign count_row_out_s
     = 
       count_row_out_q + pop_count(row_out);
   
   c_dff
     #(.width(32),
       .reset_type(reset_type))
   count_row_outq
     (.clk(clk),
      .reset(reset),
      .d(count_row_out_s),
      .q(count_row_out_q));

   wire [0:31] count_row_out;
   assign count_row_out = count_row_out_s;
   /*end stats*/
   
   reg [0:flit_ctrl_width+flit_data_width-1] vectors[0:100], currentvec;
   reg [0:31]  vectornum;
   reg [0:31]  run_time;

   
   initial begin
      $readmemb("test_vector", vectors);
      vectornum     = 0;
      run_time 	    = 0;
      
   end 

   
   initial
     begin
	
	reset 	    = 1'b1;
	clk_en 	    = 1'b0;
	run 	    = 1'b0;
	currentvec  = 32'b0;
	
	#(Tclk);
	
	reset 	= 1'b0;
	clk_en 	= 1'b1;
	run 	= 1'b1;
	
	$display("Out of reset");
	
	end // initial begin
   

   
   always @(posedge clk) begin
      currentvec  = vectors[vectornum];  
      //if(flit_ctrl[0])
	//$display("%d %b %b",run_time,flit_ctrl,flit_data);
      
      if(run_time == end_time) begin
	 $display("Total %d flits in, %d flits out, %d flits column out, %d flits row out",count_in_flits,count_self_out,count_col_out, count_row_out);
	 
	 $finish;
	 end
      vectornum 	    = vectornum +1;
      run_time 		    = run_time +1;
   end
   
   always
     begin
	clk 		   <= clk_en;
	#(Tclk/2);
	clk <= 1'b0;
	#(Tclk/2);
     end
   
   initial begin : main
      $dumpfile("yarc.vcd");
      $dumpvars(0, dut);
      $sdf_annotate("yarc_tile.sdf",testbench.dut);
      
   end   
endmodule // testbench
