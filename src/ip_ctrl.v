module ip_ctrl
  (clk, reset, router_address, port_id, flit_valid_in, flit_vc_in, flit_head_in,
   flit_tail_in, flit_data_in, free_ivc_op, free_op_ovc, cred_op_ovc,
   vc_req_ivc_op, vc_req_ivc_ovc, vc_gnt_ivc_ovc, sw_req_nonspec_ivc_op,
   sw_req_spec_ivc_op, sw_gnt_nonspec_ivc, sw_gnt_spec_ivc, flit_valid_out,
   flit_vc_out, flit_head_out, flit_tail_out, flit_data_out, cred_valid_out,
   cred_vc_out, error);
   
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
   
   // flit buffer entries per VC
   parameter num_flit_buffers = 8;
   
   // width required to select a buffer
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // width of sum of event signals from all VCs
   localparam event_width = clogb(num_vcs) + 1;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // number of input and output ports on router
   parameter num_ports = 5;
   
   // width required to select individual port
   localparam port_idx_width = clogb(num_ports);
   
   // number of dimensions in network
   parameter num_dimensions = 2;
   
   // number of routers in each dimension
   parameter num_routers_per_dim = 4;
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // number of adjacent routers in each dimension
   parameter num_neighbors_per_dim = 2;
   
   // number of nodes per router (a.k.a. consentration factor)
   localparam num_nodes_per_router
     = num_ports - num_dimensions * num_neighbors_per_dim;
   
   // width required to select individual node at current router
   localparam node_addr_width = clogb(num_nodes_per_router);
   
   // width of global addresses
   localparam addr_width = router_addr_width + node_addr_width;
   
   // total number of bits required for storing routing information
   localparam route_info_width = 2 * addr_width;
   
   // flit width
   parameter data_width = 64;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_BY_RELATION;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter sw_spec_enable = 1;
   
   // select method for credit checking
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_LEVEL)
   parameter sw_spec_cred_check = `SW_SPEC_CRED_CHECK_SEL_POST;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
      
   // number of entries in flit buffer
   localparam fbf_depth = num_vcs*num_flit_buffers;
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(fbf_depth);
   
   // wdith of the flit buffer register file
   localparam fbf_data_width = (num_header_buffers > 1) ?
			       (1+data_width) :
			       (2+data_width);
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // ID of current input port
   input [0:port_idx_width-1] port_id;
   
   // valid flit data available
   input flit_valid_in;
   
   // which VC is flit travelling on
   // (note: valid only when flit_valid_in=1)
   input [0:vc_idx_width-1] flit_vc_in;
   
   // flit is head
   // (note: valid only when flit_valid_in=1)
   input flit_head_in;
   
   // flit is tail
   // (note: valid only when flit_valid_in=1)
   input flit_tail_in;
   
   // flit data
   // (note: valid only when flit_valid_in=1)
   input [0:data_width-1] flit_data_in;
   
   // summary signal indicating all output VCs at given output port for a given 
   // input VC have at least one credit available
   // (note: only used for CREDIT_HANDLING_TYPE_LEVEL)
   input [0:num_vcs*num_ports-1] free_ivc_op;
   
   // at least one credit available for given output VC at given output port
   // (note: only used for CREDIT_HANDLING_TYPE_LEVEL)
   input [0:num_ports*num_vcs*2-1] free_op_ovc;
   
   // credits from output controller
   // (note: only used for CREDIT_HANDLING_TYPE_PUSH)
   input [0:num_ports*num_vcs-1] cred_op_ovc;
   
   // request VC allocation for given port
   output [0:num_vcs*num_ports-1] vc_req_ivc_op;
   wire [0:num_vcs*num_ports-1] vc_req_ivc_op;
   
   // allowable VCs for VC allocation
   output [0:num_vcs*num_vcs-1] vc_req_ivc_ovc;
   wire [0:num_vcs*num_vcs-1] 	vc_req_ivc_ovc;
   
   // granted output VC
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   // non-speculative switch allocator requests
   output [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   
   // speculative switch allocator requests
   output [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   wire [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   
   // non-speculative switch allocator grants
   input [0:num_vcs-1] sw_gnt_nonspec_ivc;
   
   // speculative switch allocator grants
   input [0:num_vcs-1] sw_gnt_spec_ivc;
   
   // outgoing flit valid
   output flit_valid_out;
   wire 			flit_valid_out;
   
   // destination VC for outgoing flit
   // (note: only valid if flit_valid_out=1)
   output [0:vc_idx_width-1] flit_vc_out;
   wire [0:vc_idx_width-1] 	flit_vc_out;
   
   // outgoing flit is head
   // (note: only valid if flit_valid_out=1)
   output flit_head_out;
   wire 			flit_head_out;
   
   // outgoing flit is tail
   // (note: only valid if flit_valid_out=1)
   output flit_tail_out;
   wire 			flit_tail_out;
   
   // flit data for outgoing flit
   // (note: only valid if flit_valid_out=1)
   output [0:data_width-1] flit_data_out;
   wire [0:data_width-1] 	flit_data_out;
   
   // outgoing credit valid
   output cred_valid_out;
   wire 			cred_valid_out;
   
   // VC indicator for outgoing credit
   // (note: only valid if cred_valid_out=1)
   output [0:vc_idx_width-1] cred_vc_out;
   wire [0:vc_idx_width-1] 	cred_vc_out;
   
   // internal error condition detected
   output error;
   wire 			error;
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   // extract routing information from header data
   wire [0:route_info_width-1] 	route_info_in;
   assign route_info_in = flit_data_in[0:route_info_width-1];
   
   wire [0:num_vcs-1] 		flit_sent_ivc;
   wire [0:num_vcs*vc_idx_width-1] flit_vc_ivc;
   wire [0:num_vcs-1] 		   flit_tail_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] buff_write_addr_ivc;
   wire [0:num_vcs*flit_buffer_idx_width-1] buff_read_addr_ivc;
   wire [0:num_vcs-1] 			    ivcc_error_ivc;
   wire [0:num_vcs*6-1] 		    events_ivc;
   generate
      
      genvar 				    ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire flit_valid;
	   assign flit_valid = flit_valid_in && (flit_vc_in == ivc);
	   
	   wire [0:num_ports-1] free_op;
	   assign free_op = free_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1];
	   
	   wire [0:num_vcs-1] 	vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
	   
	   wire 		sw_gnt_nonspec;
	   assign sw_gnt_nonspec = sw_gnt_nonspec_ivc[ivc];
	   
	   wire 		sw_gnt_spec;
	   assign sw_gnt_spec = sw_gnt_spec_ivc[ivc];
	   
	   wire [0:num_ports-1] vc_req_op;
	   wire [0:num_vcs-1] 	vc_req_ovc;
	   wire [0:num_ports-1] sw_req_nonspec_op;
	   wire [0:num_ports-1] sw_req_spec_op;
	   wire 		flit_sent;
	   wire [0:vc_idx_width-1] flit_vc;
	   wire 		   flit_tail;
	   wire [0:flit_buffer_idx_width-1] buff_write_addr;
	   wire [0:flit_buffer_idx_width-1] buff_read_addr;
	   wire 			    ivcc_error;
	   wire [0:5] 			    events;
	   ivc_ctrl
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_vcs(num_vcs),
	       .vc_id(ivc),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_ports(num_ports),
	       .num_dimensions(num_dimensions),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .routing_function_type(routing_function_type),
	       .credit_handling_type(credit_handling_type),
	       .header_fifo_type(header_fifo_type),
	       .sw_spec_enable(sw_spec_enable),
	       .sw_spec_cred_check(sw_spec_cred_check),
	       .perf_ctr_enable(perf_ctr_enable),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type))
	   ivcc
	     (.clk(clk),
	      .reset(reset),
	      .router_address(router_address),
	      .port_id(port_id),
	      .flit_valid_in(flit_valid),
	      .flit_head_in(flit_head_in),
	      .flit_tail_in(flit_tail_in),
	      .route_info_in(route_info_in),
	      .free_op(free_op),
	      .free_op_ovc(free_op_ovc),
	      .cred_op_ovc(cred_op_ovc),
	      .vc_req_op(vc_req_op),
	      .vc_req_ovc(vc_req_ovc),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .sw_req_nonspec_op(sw_req_nonspec_op),
	      .sw_req_spec_op(sw_req_spec_op),
	      .sw_gnt_nonspec(sw_gnt_nonspec),
	      .sw_gnt_spec(sw_gnt_spec),
	      .flit_sent(flit_sent),
	      .flit_vc_out(flit_vc),
	      .flit_tail_out(flit_tail),
	      .buff_write_addr(buff_write_addr),
	      .buff_read_addr(buff_read_addr),
	      .error(ivcc_error),
	      .events(events));
	   
	   assign vc_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = vc_req_op;
	   assign vc_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1] = vc_req_ovc;
	   assign sw_req_nonspec_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = sw_req_nonspec_op;
	   assign sw_req_spec_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = sw_req_spec_op;
	   assign flit_sent_ivc[ivc] = flit_sent;
	   assign flit_vc_ivc[ivc*vc_idx_width:(ivc+1)*vc_idx_width-1]
		    = flit_vc;
	   assign flit_tail_ivc[ivc] = flit_tail;
	   assign buff_write_addr_ivc[ivc*flit_buffer_idx_width:
				      (ivc+1)*flit_buffer_idx_width-1]
		    = buff_write_addr;
	   assign buff_read_addr_ivc[ivc*flit_buffer_idx_width:
				     (ivc+1)*flit_buffer_idx_width-1]
		    = buff_read_addr;
	   assign ivcc_error_ivc[ivc] = ivcc_error;
	   assign events_ivc[ivc*6:(ivc+1)*6-1] = events;
	   
	end
      
   endgenerate
   
   assign error = |ivcc_error_ivc;
   
   
   //---------------------------------------------------------------------------
   // address computation
   //---------------------------------------------------------------------------
   
   wire [0:flit_buffer_idx_width-1] 	    buff_write_offset;
   mux_nto1
     #(.num_ports(num_vcs),
       .width(flit_buffer_idx_width))
   buff_write_offset_sel
     (.select(flit_vc_in),
      .data_in(buff_write_addr_ivc),
      .data_out(buff_write_offset));
   
   wire [0:flit_buffer_idx_width-1] 	    buff_read_offset;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(flit_buffer_idx_width))
   buff_read_offset_sel
     (.select(flit_sent_ivc),
      .data_in(buff_read_addr_ivc),
      .data_out(buff_read_offset));
   
   wire [0:vc_idx_width-1] 		    buff_write_base;
   assign buff_write_base = flit_vc_in;
   
   wire [0:vc_idx_width-1] 		    buff_read_base;
   encoder
     #(.num_ports(num_vcs))
   buff_read_base_enc
     (.data_in(flit_sent_ivc),
      .data_out(buff_read_base));
   
   wire [0:fbf_addr_width-1] 		    fbf_write_addr;
   assign fbf_write_addr = {buff_write_base, buff_write_offset};
   
   wire [0:fbf_addr_width-1] 		    fbf_read_addr;
   assign fbf_read_addr = {buff_read_base, buff_read_offset};
   
   
   //---------------------------------------------------------------------------
   // for adaptive routing, must update route info if we're transitioning from
   // non-minimal to minimal at this hop!
   //---------------------------------------------------------------------------
   
   wire [0:route_info_width-1] 		    route_info;
   assign route_info = flit_data_in[0:route_info_width-1];
   
   wire [0:addr_width-1] 		    next_address;
   assign next_address = route_info[0:addr_width-1];
   
   wire [0:addr_width-1] 		    final_address;
   assign final_address = route_info[addr_width:2*addr_width-1];
   
   wire 				    update_addr;
   assign update_addr = flit_head_in &&
			(router_address == next_address[0:router_addr_width-1]);
   
   wire [0:route_info_width-1] 		    next_route_info;
   assign next_route_info
     = {update_addr ? final_address : next_address, final_address};
   
   wire [0:data_width-1] 		    flit_data_muxed;
   assign flit_data_muxed[0:route_info_width-1] = next_route_info;
   assign flit_data_muxed[route_info_width:data_width-1]
	    = flit_data_in[route_info_width:data_width-1];
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire 				    fbf_write_enable;
   assign fbf_write_enable = flit_valid_in;

   wire [0:fbf_data_width-1] 		    fbf_write_data, fbf_read_data;
   regfile
     #(.width(fbf_data_width),
       .depth(fbf_depth))
   fbf
     (.clk(clk),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(fbf_write_data),
      .read_address(fbf_read_addr),
      .read_data(fbf_read_data));
   
   generate
      
      if(num_header_buffers == 1)
	begin
	   
	   assign fbf_write_data[0] = flit_head_in;
	   assign fbf_write_data[1] = flit_tail_in;
	   assign fbf_write_data[2:data_width+1] = flit_data_muxed;
	   
	   assign flit_head_out = fbf_read_data[0];
	   assign flit_tail_out = fbf_read_data[1];
	   assign flit_data_out = fbf_read_data[2:data_width+1];
	   
	end
      else
	begin
	   
	   assign fbf_write_data[0] = flit_head_in;
	   assign fbf_write_data[1:data_width] = flit_data_muxed;
	   
	   assign flit_head_out = fbf_read_data[0];
	   assign flit_data_out = fbf_read_data[1:data_width];
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate outputs to switch
   //---------------------------------------------------------------------------
   
   wire 				       flit_valid_s, flit_valid_q;
   assign flit_valid_s = |flit_sent_ivc;
   dff
     #(.width(1),
       .reset_type(reset_type))
   flit_validq
     (.clk(clk),
      .reset(reset),
      .d(flit_valid_s),
      .q(flit_valid_q));
   
   assign flit_valid_out = flit_valid_q;
   
   generate
      
      if(num_header_buffers > 1)
	begin
	   
	   wire flit_tail_s, flit_tail_q;
	   select_1ofn
	     #(.num_ports(num_vcs),
	       .width(1))
	   flit_tail_s_sel
	     (.select(flit_sent_ivc),
	      .data_in(flit_tail_ivc),
	      .data_out(flit_tail_s));
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   flit_tailq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_tail_s),
	      .q(flit_tail_q));
	   
	   assign flit_tail_out = flit_tail_q;
	   
	end
      
   endgenerate
   
   // output VCs are tracket in input VC controllers, so we can just reuse that 
   // information here
   wire [0:vc_idx_width-1] flit_vc_s, flit_vc_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(vc_idx_width))
   flit_vc_s_sel
     (.select(flit_sent_ivc),
      .data_in(flit_vc_ivc),
      .data_out(flit_vc_s));
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   flit_vcq
     (.clk(clk),
      .reset(reset),
      .d(flit_vc_s),
      .q(flit_vc_q));
   
   assign flit_vc_out = flit_vc_q;
   
   
   //---------------------------------------------------------------------------
   // generate outgoing credits
   //---------------------------------------------------------------------------
   
   wire 		   cred_valid_s, cred_valid_q;
   assign cred_valid_s = |flit_sent_ivc;
   dff
     #(.width(1),
       .reset_type(reset_type))
   cred_validq
     (.clk(clk),
      .reset(reset),
      .d(cred_valid_s),
      .q(cred_valid_q));
   
   assign cred_valid_out = cred_valid_q;
   
   wire [0:vc_idx_width-1] cred_vc_s, cred_vc_q;
   encoder
     #(.num_ports(num_vcs))
   cred_vc_out_enc
     (.data_in(flit_sent_ivc),
      .data_out(cred_vc_s));
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   cred_vcq
     (.clk(clk),
      .reset(reset),
      .d(cred_vc_s),
      .q(cred_vc_q));
   
   assign cred_vc_out = cred_vc_q;
   
   
   //---------------------------------------------------------------------------
   // performance counters
   //---------------------------------------------------------------------------
   
   wire [0:6*num_vcs-1]    events;
   interleaver
     #(.width(num_vcs*6),
       .num_blocks(num_vcs))
   events_intl
     (.data_in(events_ivc),
      .data_out(events));
   
   genvar 		   ctr;
   generate
      if(perf_ctr_enable > 0)
	begin
	   for(ctr = 0; ctr < 6; ctr = ctr + 1)
	     begin:ctrs
		wire [0:event_width-1] event_sum;
		add_nto1
		  #(.num_ports(num_vcs),
		    .width(1))
		event_sum_add
		  (.data_in(events[ctr*num_vcs:(ctr+1)*num_vcs-1]),
		   .data_out(event_sum));
		
		wire [0:perf_ctr_width-1] ctr_s, ctr_q;
		assign ctr_s = ctr_q + event_sum;
		dff
		  #(.width(perf_ctr_width),
		    .reset_type(reset_type))
		ctrq
		  (.clk(clk),
		   .reset(reset),
		   .d(ctr_s),
		   .q(ctr_q));
	     end
	end
   endgenerate
   
endmodule
