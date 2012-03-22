module testbench();
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
`include "parameters.v"

   parameter Tclk 		      = 2;
   // width required to select individual resource class
   localparam resource_class_idx_width = clogb(num_resource_classes);
   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   // total number of routers
   localparam num_routers
     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   // number of routers in each dimension
   localparam num_routers_per_dim = croot(num_routers, num_dimensions);
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   // connectivity within each dimension
   localparam connectivity
     = (topology == `TOPOLOGY_MESH) ?
       `CONNECTIVITY_LINE :
       (topology == `TOPOLOGY_TORUS) ?
       `CONNECTIVITY_RING :
       (topology == `TOPOLOGY_FBFLY) ?
       `CONNECTIVITY_FULL :
       -1;
   // number of adjacent routers in each dimension
   localparam num_neighbors_per_dim
     = ((connectivity == `CONNECTIVITY_LINE) ||
	(connectivity == `CONNECTIVITY_RING)) ?
       2 :
       (connectivity == `CONNECTIVITY_FULL) ?
       (num_routers_per_dim - 1) :
       -1;
   // number of input and output ports on router
   localparam num_ports
     = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   // width required for lookahead routing information
   localparam lar_info_width = port_idx_width + resource_class_idx_width;
   // total number of bits required for storing routing information
   localparam dest_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       (num_resource_classes * router_addr_width + node_addr_width) : 
       -1;
   // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   // channel width
   localparam channel_width 	    = flit_ctrl_width + flit_data_width;
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   // total number of bits required for storing header information
   
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       route_info_width: 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       route_info_width: 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (route_info_width + payload_length_width) : 
       -1;
   
   parameter max_reservation_size     = 256;
   parameter time_to_wait_width      = 8;
   localparam reservation_size_width  = clogb(max_reservation_size);

   // measurement interval in cycles
   parameter run_time 		      = 10000;
   integer seed;
   


   
   
   reg clk;
   reg reset;
   reg clk_en;
   reg run;
   
   wire valid;
   wire nic_error;
   wire packet_source_error;



   reg [0:channel_width-1] test_data;
   wire [0:channel_width-1] packet_source_data;
   wire [0:channel_width-1] input_data;

   assign valid       = packet_source_data[0];
   assign input_data  = valid?packet_source_data:test_data;
   
   
   wire [0:flow_ctrl_width-1] packet_source_fc;
   wire [0:flow_ctrl_width-1] input_fc;
   assign packet_source_fc  = (input_fc==3'b111)?input_fc:3'b0;   
   
   
   wire [0:channel_width-1] output_data;
   
   test_nic
     #(// Parameters
       .topology			(topology),
       .num_flits_per_vc		(num_flits_per_vc),
       .num_message_classes		(num_message_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_nodes			(num_nodes),
       .num_dimensions			(num_dimensions),
       .num_nodes_per_router		(num_nodes_per_router),
       .packet_format			(packet_format),
       .flow_ctrl_type			(flow_ctrl_type),
       .flow_ctrl_bypass		(flow_ctrl_bypass),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .routing_type			(routing_type),
       .dim_order			(dim_order),
       .elig_mask			(elig_mask),
       .max_reservation_size		(max_reservation_size),
       .time_to_wait_width		(time_to_wait_width),
       .reset_type			(reset_type))
   dut
     (// Outputs
      .channel_out			(output_data),
      .flow_ctrl(input_fc),
      .error(nic_error),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .run				(run),
      .router_address({router_addr_width{1'b1}}),
      .channel_in			(input_data));
   



   srp_packet_source
     #(// Parameters
       .time_to_wait_width		(time_to_wait_width),
       .initial_seed			(0),
       .max_packet_count		(-1),
       .packet_rate			(100),
       .packet_ratio			(100),
       .packet_count_reg_width		(32),
       .packet_length_mode		(0),
       .topology			(topology),
       .num_flits_per_vc		(num_flits_per_vc),
       .num_message_classes		(num_message_classes),
       .num_vcs_per_class		(num_vcs_per_class),
       .num_nodes			(num_nodes),
       .num_dimensions			(num_dimensions),
       .num_nodes_per_router		(num_nodes_per_router),
       .packet_format			(packet_format),
       .flow_ctrl_type			(flow_ctrl_type),
       .flow_ctrl_bypass		(flow_ctrl_bypass),
       .max_payload_length		(max_payload_length),
       .min_payload_length		(min_payload_length),
       .flit_data_width			(flit_data_width),
       .routing_type			(routing_type),
       .dim_order			(dim_order),
       .elig_mask			(elig_mask),
       .port_id				(0),
       .reset_type			(reset_type))
   test_source
     (// Outputs
      .channel				(packet_source_data),
      .flit_valid			(), //this comes a cycle early than data
      .error				(packet_source_error),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .router_address			({router_addr_width{1'b1}}),
      .flow_ctrl			(packet_source_fc),
      .run				(run));
   

   
   //clock
   always
     begin
	clk <= clk_en;
	#(Tclk/2);
	clk <= 1'b0;
	#(Tclk/2);
	end



   
   always@(posedge clk or posedge reset)
     begin
	if(reset)
	  begin
	     test_data <='b0;
	  end
	else
	  begin
	     test_data[0] <= ($dist_uniform(seed, 0,  99) < 95);
	     test_data[1:2]  <= 2'b00;
	     test_data[3]  <= 1'b1;
	     test_data[4:(flit_ctrl_width+header_info_width+2)-1] <= 'b0;
	     test_data[(flit_ctrl_width+header_info_width+2)+:reservation_size_width]
	       <=($dist_uniform(seed, 6,  255));//'h2;
	     test_data[(flit_ctrl_width+header_info_width+2)+reservation_size_width:
		       channel_width-1] <='b0;
	  end
     end // always@ (posedge clk or posedge reset)



   
   
   integer cycles;   
   initial
     begin
	seed 	    = 100;
	
   	reset 	    = 1'b0;
	clk_en 	    = 1'b0;
	run 	    = 1'b0;
	cycles 	    = 0;
	
	#(Tclk);
	#(Tclk/2);
	reset = 1'b1;
	#(Tclk);
	reset = 1'b0;
	#(Tclk);
	clk_en = 1'b1;
	#(Tclk/2);
	run 	= 1'b1;
	while(cycles < run_time)
	  begin
	     cycles 				= cycles + 1;
	     #(Tclk);
	  end
	$finish;      
     end
   
   
endmodule
