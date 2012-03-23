/*Message buffer
 * Can fetch message info from the message generator
 * Can extract grant time from grant
 */


module flow_buffer(/*autoarg*/
		   // Outputs
		   buffer_empty, reservation_ready, nonspec_ready, spec_ready,
		   output_data, error,
		   // Inputs
		   clk, run, reset, source_address, message_ready, message_size,
		   message_dest, grant_ready, ack_ready, nack_ready, input_data,
		   current_time, nic_gnt
		   );
`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"

   // select network topology
   parameter topology 		     = `TOPOLOGY_FBFLY;
   // flit buffer entries per VC
   parameter num_flits_per_vc 	     = 8;
   // width required to express number of flits in a VC
   localparam flit_count_width = clogb(num_flits_per_vc + 1);
   // number of bits required for flit buffer addresses
   localparam flit_buffer_idx_width  = clogb(num_flits_per_vc);
   // number of message classes (e.g. request, reply)
   parameter num_message_classes     = 2;
   // total number of packet classes
   localparam num_packet_classes     = num_message_classes;   
   // number of VCs per class
   parameter num_vcs_per_class 	     = 2;
   // number of VCs
   localparam num_vcs 		     = num_packet_classes * num_vcs_per_class;
   // width required to select individual VC
   localparam vc_idx_width 	     = clogb(num_vcs);
   // total number of nodes
   parameter num_nodes 		     = 64;
   // number of dimensions in network
   parameter num_dimensions 	     = 2;
   // number of nodes per router (a.k.a. concentration factor)
   parameter num_nodes_per_router    = 4;
   // total number of routers
   localparam num_routers	     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
   // number of routers in each dimension
   localparam num_routers_per_dim    = croot(num_routers, num_dimensions);
   // width required to select individual router in a dimension
   localparam dim_addr_width 	     = clogb(num_routers_per_dim);
   // width required to select individual router in entire network
   localparam router_addr_width      = num_dimensions * dim_addr_width;
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
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   // select packet format
   parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;
   // select type of flow control
   parameter flow_ctrl_type = `FLOW_CTRL_TYPE_CREDIT;
   // make incoming flow control signals bypass the output VC state tracking 
   // logic
   parameter flow_ctrl_bypass = 1;
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
   // maximum payload length (in flits)
   parameter max_payload_length = 4;
   // minimum payload length (in flits)
   parameter min_payload_length = 0;
   // number of bits required to represent all possible payload sizes
   localparam payload_length_width
     = clogb(max_payload_length-min_payload_length+1);
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   // width of flit payload data
   parameter flit_data_width   = 64;
   // channel width
   localparam channel_width    = flit_ctrl_width + flit_data_width;
   // width required for lookahead routing information
   localparam lar_info_width   = port_idx_width;
   // select routing function type
   parameter routing_type      = `ROUTING_TYPE_PHASED_DOR;
   // total number of bits required for storing routing information
   localparam dest_info_width
     = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
       ( router_addr_width + node_addr_width) : 
       -1;
   // total number of bits required for routing-related information
   localparam route_info_width = lar_info_width + dest_info_width;
   // total number of bits required for storing header information
   localparam header_info_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       route_info_width: 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       route_info_width : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (route_info_width + payload_length_width ) : 
       -1;
   // select order of dimension traversal
   parameter dim_order 		      = `DIM_ORDER_ASCENDING;
   // select whether to exclude full or non-empty VCs from VC allocation
   parameter elig_mask 		      = `ELIG_MASK_NONE;
   // maximum packet length (in flits)
   localparam max_packet_length       = 1 + max_payload_length;
   // total number of bits required to represent maximum packet length
   localparam packet_length_width     = clogb(max_packet_length);

   
   parameter max_reservation_size     = 256;
   localparam reservation_size_width  = clogb(max_reservation_size);
   parameter reset_type 	      = `RESET_TYPE_ASYNC;


   //default inputs
   input clk;
   input run;
   input reset;
   input [0:dest_info_width-1] source_address;
   

   
   //IO from the message generator
   input message_ready;
   input [0:reservation_size_width-1] message_size; //messages cannot be > reservation size for now
   input [0:dest_info_width-1] message_dest;
   output buffer_empty; //this buffer needs a message
   
   

   //IO from the NIC
   //no flow control on these input, the buffer must sink them
   input grant_ready;
   input ack_ready;
   input nack_ready;
   input [0:flit_data_width-1] input_data;
   input [0:31] current_time;


   input nic_gnt; //flow control for these output
   output reservation_ready;
   output nonspec_ready;
   output spec_ready;
   output [0:flit_data_width-1] output_data;


   output error;
   


   
   //FSM
   reg[0:2] state;
   localparam FB_EMPTY 	     =3'd0;
   localparam FB_RES_READY   =3'd1;
   localparam FB_SPEC_READY  =3'd2;
   localparam FB_SPEC_STOP   =3'd3;
   localparam FB_NON_SPEC    =3'd4;
   
   
   //"global" values
   wire [0:lar_info_width-1] message_lar;
   
   

   ///////////////////
   //New message from NIC
   wire [0:reservation_size_width-1] packet_total_s;
   wire [0:reservation_size_width-1] packet_total_q;
   assign packet_total_s  = message_ready?
			    message_size:
			    packet_total_q;
   c_dff
     #(.width				(reservation_size_width),
       .reset_type			(reset_type))
   message_count_reg
     (// Outputs
      .q				(packet_total_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(packet_total_s));
   wire [0:dest_info_width-1] message_dest_s;
   wire [0:dest_info_width-1] message_dest_q;
   assign message_dest_s  = message_ready?message_dest:message_dest_q;
   c_dff
     #(.width				(dest_info_width),
       .reset_type			(reset_type))
   message_dest_reg
     (// Outputs
      .q				(message_dest_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(message_dest_s));


   
   //This routing computation is hared for all packets (res/spec/nonspec)
   wire [0:num_ports-1] message_route_op;
   rtr_routing_logic
     #(.num_message_classes(1),
       .num_resource_classes(1),
       .num_routers_per_dim(num_routers_per_dim),
       .num_dimensions(num_dimensions),
       .num_nodes_per_router(num_nodes_per_router),
       .connectivity(connectivity),
       .routing_type(routing_type),
       .dim_order(dim_order))
   reservation_route_compute
     (.router_address(source_address[0:router_addr_width-1]),
      .sel_mc(1'b1),
      .sel_irc(1'b1),
      .dest_info(message_dest_s),
      .route_op( message_route_op),
      .route_orc());
   c_encode
     #(.num_ports(num_ports))
   message_route_port_enc
     (.data_in(message_route_op),
      .data_out(message_lar));   

   
   //creating reservation packet
   wire [0:flit_data_width-1] reservation_packet_s;
   wire [0:flit_data_width-1] reservation_packet_q;
   assign reservation_packet_s[0:lar_info_width-1] 
     = message_lar;
   assign reservation_packet_s[lar_info_width+:dest_info_width] 
     = message_dest_s;
   assign reservation_packet_s[lar_info_width+dest_info_width:header_info_width-1] 
     = 'b0;//psize
   assign reservation_packet_s[header_info_width+:2] = 2'b00; //srp_type
   assign reservation_packet_s[(header_info_width+2)+:reservation_size_width] 
     = message_ready? //reservation-size
       message_size:
       reservation_packet_q[(header_info_width+2)+:reservation_size_width];
   assign reservation_packet_s[(header_info_width+2+reservation_size_width)+:dest_info_width] = source_address; //source address
   assign reservation_packet_s[(header_info_width+2+reservation_size_width)+dest_info_width:flit_data_width-1]
     ='b0;
   c_dff
     #(.width				(flit_data_width),
       .reset_type			(reset_type))
   reservation_packet_reg
     (// Outputs
      .q				(reservation_packet_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(reservation_packet_s));

   
   ///////////////////
     //Grant transition
   wire [0:31] granted_time_s;
   wire [0:31] granted_time_q;
   assign granted_time_s = grant_ready?
			   input_data[flit_data_width-32:flit_data_width-1]:
			   granted_time_q;
   
   c_dff
     #(.width				(32),
       .reset_type			(reset_type))
   grant_time_reg
     (// Outputs
      .q				(granted_time_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(granted_time_s));

   
   

   //////////////////
     //spec linked list
   wire spec_tail  = 1'b1;
   

   
   //FSM update   
   always @ (posedge clk, posedge reset)
     begin
	if(reset)
	  state   <=FB_EMPTY;
	else
	  begin
	     case(state)
	       FB_EMPTY:
		 if(message_ready) //new message from nic
		   state <=FB_RES_READY;
	       
	       FB_RES_READY:
		 if(nic_gnt) //nic accepted reservation packet
		   begin
		      state <= FB_SPEC_READY;//this is correct
		      state <= FB_SPEC_STOP;//this is test
		   end
	       FB_SPEC_READY:
		 if(nack_ready | grant_ready)
		   state <=FB_SPEC_STOP;
	       FB_SPEC_STOP:
		 if(current_time >granted_time_s)
		   begin
		      //state <=FB_NON_SPEC; //this is correct
		      state <=FB_EMPTY;//this is test
		   end
	       default:
		 state 	    <=FB_EMPTY;
	     endcase
	  end
     end // always @ (posedge clk, posedge reset)


   //update these conditions
   assign spec_ready 	     = (state==FB_SPEC_READY) | ~spec_tail;
   assign nonspec_ready      = (state==FB_NON_SPEC);
   
   assign reservation_ready  = (state==FB_RES_READY);
   assign buffer_empty 	     = (state==FB_EMPTY);
   assign output_data 	     = reservation_ready?
			       reservation_packet_q:
			       {flit_data_width{1'b0}};
   
   wire [0:3] ready_sum = spec_ready+reservation_ready+nonspec_ready;
   assign error  = (ready_sum > 1);
endmodule