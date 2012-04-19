/*Message buffer
 * Can fetch message info from the message generator
 * Can extract grant time from grant
 * basic spec, nonspec, ack handling is working 
 * basic nack, retransmitworking
 * 
 * need lots and lots of extensive tests
 */


module flow_buffer(/*autoarg*/
   // Outputs
   host_next_flit, buffer_empty, reservation_ready, nonspec_ready,
   spec_ready, output_data, output_head, output_tail, error,
   // Inputs
   clk, run, reset, source_address, message_ready, message_size,
   message_dest, host_data_valid, host_data_head, host_data_tail,
   host_data, grant_ready, ack_ready, nack_ready, nic_data,
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
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + num_vcs) :
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

   parameter spec_buffer_capacity     = 4;
   localparam spec_buffer_width       = clogb(spec_buffer_capacity);   
   
   parameter time_to_wait_width       = 8;
   parameter max_reservation_size     = 16; //packtes
   localparam reservation_size_width  = clogb(max_reservation_size);
   parameter reset_type 	      = `RESET_TYPE_ASYNC;

   //SRP packet related
`include "srp_format.v"

   //default inputs
   input clk;
   input run;
   input reset;
   input [0:dest_info_width-1] source_address;

   
   //IO from the message generator
   //we use message_ready vs has_message, becaues the meesage generator may have multiple
   //flow buffer it could use
   input message_ready; 
   input [0:reservation_size_width-1] message_size; //messages cannot be > reservation size
   input [0:dest_info_width-1] message_dest;
   input host_data_valid;
   input host_data_head;
   input host_data_tail;
   output host_next_flit; //get a new flit on the next cycle
   input [0:flit_data_width-1] host_data;
   output buffer_empty; //allows the message generator to select this buffer
   
   
   //IO from the NIC
   //no flow control on these input, the buffer must sink them
   input grant_ready;
   input ack_ready;
   input nack_ready;
   input [0:flit_data_width-1] nic_data;
   input [0:31] current_time;
   
   //output from the buffer are flow controled   
   input nic_gnt; 
   output reservation_ready;
   output nonspec_ready;
   output spec_ready;
   output [0:flit_data_width-1] output_data;
   output output_head;
   output output_tail;
   
   output error;

   
   //flow buffer FSM
   reg[0:2] state;
   localparam FB_EMPTY 	     =3'd0;
   localparam FB_RES_READY   =3'd1;
   localparam FB_SPEC_READY  =3'd2;
   localparam FB_SPEC_STOP   =3'd3;
   localparam FB_NONSPEC    =3'd4;
   
   //routing info identical for all packets
   wire [0:lar_info_width-1] message_lar;

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

   //this tracks if we are in the middle of importing a packet from the the host
   wire consumed_head  = host_data_head&host_next_flit;
   wire consumed_tail  = host_data_tail&host_next_flit;
   wire host_after_head_s;
   wire host_after_head;
   assign host_after_head_s = consumed_head?
			      (consumed_tail?
			       1'b0:
			       1'b1):
			      (consumed_tail?
			       1'b0:
			       host_after_head);
   //host tracker
   c_dff
     #(.width				(1),
       .reset_type			(reset_type))
   host_state_reg
     (// Outputs
      .q				(host_after_head),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(host_after_head_s));
   
   
   
   ///////////////////
   //New message from NIC
   //guaranteed sent
   wire [0:reservation_size_width-1] packets_available;
   
   wire [0:1] packets_debit;
   wire [0:reservation_size_width-1] packets_remaining_s;
   wire [0:reservation_size_width-1] packets_remaining_q;
   assign packets_remaining_s  = message_ready?
				message_size:
				packets_remaining_q-packets_debit;
   c_dff
     #(.width				(reservation_size_width),
       .reset_type			(reset_type))
   packets_remaining_reg
     (// Outputs
      .q				(packets_remaining_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(packets_remaining_s));
   
   //prevents spec from sending too many packets
   wire spec_credit; //when ack/nack received
   wire spec_debit; //when head flit is sent
   wire spec_tail_debit; //when tail flit is sent
   wire [0:reservation_size_width-1] packets_spec_s;
   wire [0:reservation_size_width-1] packets_spec_q;
   assign packets_spec_s  = packets_spec_q + spec_debit - spec_credit;
   c_dff
     #(.width				(reservation_size_width),
       .reset_type			(reset_type))
   packets_spec_reg
     (// Outputs
      .q				(packets_spec_q),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .active				(run),
      .d				(packets_spec_s));
   
   assign packets_available  = packets_remaining_q-packets_spec_q;
     
   //--------------------------
   //Reservation packet packing
   wire [0:flit_data_width-1] reservation_packet_s;
   wire [0:flit_data_width-1] reservation_packet_q;
   wire [0:payload_length_width-1] reservation_payload_size = {payload_length_width{1'b0}};
   assign reservation_packet_s[0:res_size_start-1] ={message_lar,
						     message_dest_s,
						     reservation_payload_size,
						      2'b00};
   assign reservation_packet_s[res_size_start+:reservation_size_width] 
     = message_ready? //reservation-size
       message_size:
       reservation_packet_q[(header_info_width+2)+:reservation_size_width];
   assign reservation_packet_s[res_src_start+:dest_info_width] = source_address; //source address
   assign reservation_packet_s[res_data_start:flit_data_width-1]
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

   
   //----------------------
   //Grant packet processing
   wire [0:31] granted_time_s;
   wire [0:31] granted_time_q;
   //assumption, grant_ready will not assert when state==FB_EMPTY
   assign granted_time_s  = (state==FB_EMPTY)? 
			    32'b0: //all 0 means no grant
			    (grant_ready?
			     nic_data[grant_time_start:flit_data_width-1]:
			     granted_time_q); //hold
   c_dff
     #(.width				(32),
       .reset_type			(reset_type))
   grant_time_reg
     (// Outputs
      .q				(granted_time_q),
      // Inputs
      .clk				(clk),
      .reset				(reset ),
      .active				(run),
      .d				(granted_time_s));


   
   //-------------------
   //spec packet injection
   wire new_spec_packet;

   wire spec_buffer_available ;
   wire [0:spec_buffer_width-1] clear_spec_buffer;
   wire [0:spec_buffer_capacity-1] clear_spec_buffer_decode;
   wire [0:spec_buffer_width-1] current_spec_buffer;
   wire [0:spec_buffer_capacity-1] current_spec_buffer_decode;
   wire retransmit;
   wire [0:spec_buffer_width-1] retran_spec_buffer;
   wire [0:spec_buffer_capacity-1] retran_spec_buffer_decode;

   
   wire spec_continue_s;
   wire spec_continue_q;
   wire spec_head;
   wire spec_tail;
   wire [0:flit_data_width-1] spec_packet;

   wire [0:flit_data_width-1] spec_buffer_pop_data;
   wire [0:2*spec_buffer_capacity-1] spec_buffer_errors;
   wire [0:spec_buffer_capacity-1] spec_buffer_full;
   wire [0:spec_buffer_capacity-1] spec_buffer_empty;
   wire [0:spec_buffer_capacity-1] spec_buffer_almost_empty;
   

   c_decode
     #(.num_ports			(spec_buffer_capacity))
   spec_buffer_push_decode
     ( // Outputs
      .data_out				(current_spec_buffer_decode),
      // Inputs
      .data_in				(current_spec_buffer));
   c_decode
     #(.num_ports			(spec_buffer_capacity))
   spec_buffer_clear_decode
     (// Outputs
      .data_out				(clear_spec_buffer_decode),
      // Inputs
      .data_in				(clear_spec_buffer));
   c_decode
     #(.num_ports			(spec_buffer_capacity))
   spec_buffer_pop_decode
     (// Outputs
      .data_out				(retran_spec_buffer_decode),
      // Inputs
      .data_in				(retran_spec_buffer));
   
   c_multi_lane_fifo
     #(// Parameters
       .num_lanes			(spec_buffer_capacity),
       .num_buffers_per_lane		(max_packet_length),
       .data_width			(flit_data_width),
       .regfile_type			(`REGFILE_TYPE_FF_2D),
       .reset_type			(reset_type))
   spec_buffer_fifo
     (// Outputs
      .push_addr_ln			(),
      .pop_data				(spec_buffer_pop_data),
      .pop_addr_ln			(),
      .peek_data			(),
      .almost_empty_ln			(spec_buffer_almost_empty),
      .empty_ln				(spec_buffer_empty),
      .full_ln				(spec_buffer_full),
      .errors_ln			(spec_buffer_errors),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .clear                            (clear_spec_buffer_decode &{spec_buffer_capacity{ack_ready}}),
      .push_active			(run),
      .push_valid			(nic_gnt & spec_ready),
      .push_sel_ln			(current_spec_buffer_decode),
      .push_data			(spec_packet),
      .pop_active			(run),
      .pop_valid			(retransmit & nic_gnt),
      .pop_sel_ln			(retran_spec_buffer_decode));
   
   

   //Start up free list - used before real free list is built
   wire free_list_init;
   wire[0:spec_buffer_width] free_list_init_s;
   wire[0:spec_buffer_width] free_list_init_q;
   assign free_list_init_s  = free_list_init?
				free_list_init_q+spec_tail_debit:
				free_list_init_q;
   c_dff
     #(.width(spec_buffer_width+1),
       .reset_type(reset_type))
   free_list_init_reg
     (.d(free_list_init_s), 
      .q(free_list_init_q),
      .clk(clk),
      .active(run),
      .reset(reset));  
   assign free_list_init  = (free_list_init_q<spec_buffer_capacity);

   //Real free list
   wire [0:1] free_list_errors;
   wire free_list_push;
   wire free_list_pop;
   wire free_list_empty;
   wire free_list_full;
   wire [0:spec_buffer_width-1] free_pop_buffer;
   wire [0:spec_buffer_width-1] free_push_buffer;
   
   c_fifo
     #(// Parameters
       .depth				(spec_buffer_capacity),
       .width				(spec_buffer_width),
       .regfile_type			(`REGFILE_TYPE_FF_2D),
       .reset_type			(reset_type))
   free_list
     (// Outputs
      .pop_data				(free_pop_buffer),
      .almost_empty			(),
      .empty				(free_list_empty),
      .almost_full			(),
      .full				(free_list_full),
      .errors				(free_list_errors),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .push_active			(run),
      .pop_active			(run),
      .push				(free_list_push),
      .pop				(free_list_pop),
      .push_data			(free_push_buffer));

   assign spec_buffer_available  = free_list_init | ~free_list_empty;
   assign current_spec_buffer 	 = free_list_init?free_list_init_q[1:spec_buffer_width]:free_pop_buffer;
   

   //prevents nonspec from cutting into spec in the middle of a packet
   assign spec_continue_s  = (spec_continue_q & ~host_data_tail) |
			     (new_spec_packet & nic_gnt);
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   spec_packet_state
     (.q(spec_continue_q),
       .clk(clk),
       .reset(reset),
       .active(run),
       .d(spec_continue_s));

   
   //Conditions for speculative injection
   assign new_spec_packet  = (state==FB_SPEC_READY) & //state
			     host_data_valid & host_data_head & //proper packet
			     spec_buffer_available & //spec buffer is free
			     (|packets_available);//insure we dont' send too much
   
   assign spec_ready 	 = spec_continue_q | new_spec_packet;
   assign spec_debit 	 = host_data_head & nic_gnt & spec_ready;
   assign spec_tail_debit= host_data_tail & nic_gnt & spec_ready;
   assign free_list_pop  = spec_tail_debit&~free_list_init;
   
   
   assign spec_head 	 = host_data_head;
   assign spec_tail 	 = host_data_tail;

   //spec  packet injection
   wire [0:payload_length_width-1] spec_payload_size = max_payload_length;
   c_select_1ofn
     #(.num_ports(2),
       .width(spec_data_start))
   spec_head_mux
     (.select({~spec_head,spec_head}),
      .data_in({host_data[0+:spec_data_start], //body flit
		//head flit
		message_lar,
		message_dest_s,
		spec_payload_size,
		2'b00,
		{time_to_wait_width{1'b1}},
		source_address,
		current_spec_buffer}),
      .data_out(spec_packet[0+:spec_data_start]));
 
   //data payload
   assign spec_packet[spec_data_start:flit_data_width-1] =  host_data[spec_data_start:flit_data_width-1];





   
   
   //-------------------
   //nonspec packet packing
   wire nonspec_head ;
   wire nonspec_tail ;
   wire [0:flit_data_width-1] nonspec_packet;

   //Retransmission list
   wire [0:1] retran_list_errors;
   wire retran_list_push;
   wire retran_list_pop;
   wire retran_list_empty;
   wire retran_list_full;
   wire [0:spec_buffer_width-1] retran_push_buffer;
   
   c_fifo
     #(// Parameters
       .depth				(spec_buffer_capacity),
       .width				(spec_buffer_width),
       .regfile_type			(`REGFILE_TYPE_FF_2D),
       .reset_type			(reset_type))
   retran_list
     (// Outputs
      .pop_data				(retran_spec_buffer),
      .almost_empty			(),
      .empty				(retran_list_empty),
      .almost_full			(),
      .full				(retran_list_full),
      .errors				(retran_list_errors),
      // Inputs
      .clk				(clk),
      .reset				(reset),
      .push_active			(run),
      .pop_active			(run),
      .push				(retran_list_push),
      .pop				(retran_list_pop),
      .push_data			(retran_push_buffer));

   //wire retransmit_done  = |(spec_buffer_empty & retran_spec_buffer_decode);
   wire retransmit_last  = |(spec_buffer_almost_empty & retran_spec_buffer_decode);
   wire retransmit;
   wire retransmit_q;
   assign retransmit  = (~retran_list_empty & ~host_after_head);
   assign retran_list_pop  = retransmit & retransmit_last & nic_gnt;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   retransmit_continue_state
     (.q(retransmit_q),
       .clk(clk),
       .reset(reset),
       .active(run),
      .d(retransmit));
   
   wire [0:2] nonspec_sel ={~host_data_head& ~retransmit,
			    host_data_head  & ~retransmit,
			    retransmit};
   
   
   wire [0:payload_length_width-1] nonspec_payload_size = max_payload_length;
   c_select_1ofn
     #(.num_ports(3),
       .width(flit_data_width+2))
   nonspec_head_mux
     (.select(nonspec_sel),
      .data_in({host_data[0:flit_data_width-1],host_data_head, host_data_tail,//body flit
		//head
		message_lar,
		message_dest_s,
		nonspec_payload_size,
		2'b00,
		host_data[nonspec_data_start:flit_data_width-1],
		host_data_head,
		host_data_tail,
		//retran
		spec_buffer_pop_data, 
		|(spec_buffer_full & retran_spec_buffer_decode),
		|(spec_buffer_almost_empty & retran_spec_buffer_decode)
		}),
      .data_out({nonspec_packet[0:flit_data_width-1], nonspec_head,  nonspec_tail}));
   
   
   wire inject_nonspec 	= (state==FB_NONSPEC) &  //state
	~spec_continue_q &  //don't cut in
	(|packets_available); //don't retransmit until nack


   //-------------------
   //ack pack processing
   //-------------------
   assign packets_debit       = (nonspec_tail & nic_gnt & inject_nonspec) + (ack_ready);
   assign free_push_buffer    = retran_list_pop? 
				retran_spec_buffer:
				nic_data[ack_id_start+:spec_buffer_width];
   assign clear_spec_buffer   = free_push_buffer;
   assign free_list_push      = ack_ready | retran_list_pop ;
   
   
   //-------------------
   //nack processing
   //-------------------
   assign retran_push_buffer  = nic_data[nack_id_start+:spec_buffer_width];
   assign retran_list_push    = nack_ready;
   assign spec_credit 	      = ack_ready|nack_ready;//either way
   

   //FSM update   
   always @ (posedge clk, posedge reset)
     begin
	if(reset)
	  state 	     <=FB_EMPTY;
	else
	  begin
	     case(state)
	       FB_EMPTY:
		 if(message_ready) //new message from nic
		   state <=FB_RES_READY;
	       FB_RES_READY:
		 if(nic_gnt) //nic accepted reservation packet
		   begin
		      state <= FB_SPEC_READY;
		   end
	       FB_SPEC_READY:
		 if(nack_ready | grant_ready)
		   state <=FB_SPEC_STOP;
	       FB_SPEC_STOP:
		 if(current_time >granted_time_s && (|granted_time_s))
		   begin
		      state <=FB_NONSPEC;
		   end
	       FB_NONSPEC:
		 if(~(|packets_remaining_s))
		   begin		      
		      state 	    <=FB_EMPTY;
		   end
	       default:
		 state 	    <=FB_EMPTY;
	     endcase
	  end
     end // always @ (posedge clk, posedge reset)


   //update these conditions
   //assign spec_ready 	    updated above
   assign nonspec_ready      = inject_nonspec;
   
   assign reservation_ready  = (state==FB_RES_READY);
   assign buffer_empty 	     = (state==FB_EMPTY);



   c_select_1ofn
     #(// Parameters
       .num_ports			(3),
       .width				(flit_data_width+2))
   injection_mux
     (// Outputs
      .data_out				({output_data, output_head, output_tail}),
      // Inputs
      .select				({reservation_ready,
					  nonspec_ready, 
					  spec_ready}),
      .data_in				({{reservation_packet_q,1'b1, 1'b1}, 
					  {nonspec_packet, nonspec_head, nonspec_tail},
					  {spec_packet, spec_head, spec_tail} }));


   assign host_next_flit  = (spec_ready | (nonspec_ready&~retransmit)) & nic_gnt;
      
   wire [0:3] ready_sum = spec_ready+reservation_ready+nonspec_ready;
   assign error  = (ready_sum > 1);
endmodule // flow_buffer



