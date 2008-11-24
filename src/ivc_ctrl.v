// $Id$
// input VC controller
module ivc_ctrl
  (clk, reset, router_address, port_id, flit_valid_in, flit_head_in,
   flit_tail_in, route_info_in, free_op, free_op_ovc, cred_op_ovc, vc_req_op,
   vc_req_ovc, vc_gnt_ovc, sw_req_nonspec_op, sw_req_spec_op, sw_gnt_nonspec,
   sw_gnt_spec, flit_sent, flit_vc_out, flit_tail_out, fbf_write_addr,
   fbf_read_addr, error, events);
   
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
   
   // width of credit hold register
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_PUSH)
   localparam cred_hold_width = clogb(num_flit_buffers);
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of VCs
   parameter num_vcs = 4;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
   // ID of current input VC
   parameter [0:vc_idx_width-1] vc_id = {vc_idx_width{1'b0}};
   
   // required address size for flit buffer
   localparam fbf_addr_width = clogb(num_vcs*num_flit_buffers);
   
   // index of leftmost entry in shared flit buffer
   localparam fbf_min_addr = vc_id*num_flit_buffers;
   
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
   
   // width required to select individual router in network
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
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // ID of current input port
   input [0:port_idx_width-1] port_id;
   
   // valid flit data available
   input flit_valid_in;
   
   // flit is head
   // (note: valid only when flit_valid_in=1)
   input flit_head_in;
   
   // flit is tail
   // (note: valid only when flit_valid_in=1)
   input flit_tail_in;
   
   // routing information associated with current flit
   // (note: valid only when flit_valid_in=1 and flit_head_in=1)
   input [0:route_info_width-1] route_info_in;
   
   // summary signal indicating all output VCs at given output port have at 
   // least one credit available
   // (note: only used for CREDIT_HANDLING_TYPE_LEVEL)
   input [0:num_ports-1] free_op;
   
   // at least one credit available for given output VC at given output port
   // (note: only used for CREDIT_HANDLING_TYPE_LEVEL)
   input [0:num_ports*num_vcs*2-1] free_op_ovc;
   
   // credits from output controller
   // (note: only used for CREDIT_HANDLING_TYPE_PUSH)
   input [0:num_ports*num_vcs-1] cred_op_ovc;
   
   // requests VC allocation for given port
   output [0:num_ports-1] vc_req_op;
   wire [0:num_ports-1] vc_req_op;
   
   // allowable VCs for VC allocation
   output [0:num_vcs-1] vc_req_ovc;
   wire [0:num_vcs-1] 	vc_req_ovc;
   
   // granted output VC
   input [0:num_vcs-1] vc_gnt_ovc;
   
   // non-speculative switch allocator requests
   output [0:num_ports-1] sw_req_nonspec_op;
   wire [0:num_ports-1] sw_req_nonspec_op;
   
   // speculative switch allocator requests
   output [0:num_ports-1] sw_req_spec_op;
   wire [0:num_ports-1] sw_req_spec_op;
   
   // non-speculative switch allocator grants
   input sw_gnt_nonspec;
   
   // speculative switch allocator grants
   input sw_gnt_spec;
   
   // outgoing flit indicator
   output flit_sent;
   wire 		flit_sent;
   
   // destination VC for outgoing flit
   // (note: only valid if flit_sent=1)
   output [0:vc_idx_width-1] flit_vc_out;
   wire [0:vc_idx_width-1] flit_vc_out;
   
   // outgoing flit is tail
   // (note: only valid if flit_sent=1 and num_header_buffers>1)
   output flit_tail_out;
   wire 		   flit_tail_out;
   
   // write pointer for shared flit buffer
   output [0:fbf_addr_width-1] fbf_write_addr;
   wire [0:fbf_addr_width-1] fbf_write_addr;
   
   // read pointer for shared flit buffer
   output [0:fbf_addr_width-1] fbf_read_addr;
   wire [0:fbf_addr_width-1] fbf_read_addr;
   
   // internal error condition detected
   output error;
   wire 		     error;
   
   // performance counter events
   // (note: only valid if perf_ctr_enable=1)
   output [0:5] events;
   wire [0:5] 		     events;
   
   
   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   
   wire 		     vc_gnt;
   assign vc_gnt = |vc_gnt_ovc;
   
   wire 		     get_next_header;
   wire 		     allocated_s, allocated_q;
   assign allocated_s = (allocated_q | vc_gnt) & ~get_next_header;
   dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .d(allocated_s),
      .q(allocated_q));
   
   wire 		     vc_allocated;
   wire 		     sw_allocated;
   wire 		     free_unallocated;
   wire 		     free_allocated;
   
   generate
      
      if(sw_spec_enable)
	begin
	   assign vc_allocated = vc_gnt | allocated_q;
	   case(credit_handling_type)
	     `CREDIT_HANDLING_TYPE_LEVEL:
	       begin
		  case(sw_spec_cred_check)
		    `SW_SPEC_CRED_CHECK_ALL_PRE:
		      begin
			 assign sw_allocated
			   = sw_gnt_nonspec | sw_gnt_spec;
		      end
		    `SW_SPEC_CRED_CHECK_ALL_POST:
		      begin
			 assign sw_allocated
			   = sw_gnt_nonspec | (sw_gnt_spec & free_unallocated);
		      end
		    `SW_SPEC_CRED_CHECK_SEL_POST:
		      begin
			 assign sw_allocated
			   = sw_gnt_nonspec | (sw_gnt_spec & free_allocated);
		      end
		  endcase
	       end
	     `CREDIT_HANDLING_TYPE_PUSH:
	       begin
		  assign sw_allocated = sw_gnt_nonspec | sw_gnt_spec;
	       end
	   endcase
	end
      else
	begin
	   assign vc_allocated = allocated_q;
	   assign sw_allocated = sw_gnt_nonspec;
	end
      
   endgenerate
   
   wire 		       all_allocated;
   assign all_allocated = sw_allocated & vc_allocated;
   
   wire 		       valid_q;
   
   assign flit_sent = valid_q & all_allocated;
   
   
   //---------------------------------------------------------------------------
   // keep track of when to get next header
   //---------------------------------------------------------------------------
   
   wire 		       fbc_empty_early;
   wire 		       tail_tracker_error;
   
   generate
      
      if(num_header_buffers > 1)
	begin
	   
	   // keep track of location(s) of all tail flits in flit buffer so we
	   // know when to get the next header data from header FIFO
	   wire [0:num_flit_buffers-1] tail_queue;
	   
	   genvar 		       idx;
	   
	   for(idx = 0; idx < num_flit_buffers; idx = idx + 1)
	     begin:idxs
		
		wire capture;
		assign capture
		  = flit_valid_in && (fbf_write_addr == (fbf_min_addr + idx));
		
		/*wire tail_s, tail_q;
		assign tail_s = capture ? flit_tail_in : tail_q;
		dff
		  #(.width(1),
		    .reset_type(reset_type))
		tailq
		  (.clk(clk),
		   .reset(reset),
		   .d(tail_s),
		   .q(tail_q));*/
		reg  tail_q;
		always @(posedge clk)
		  if(capture)
		    tail_q <= flit_tail_in;
		
		assign tail_queue[idx]
			 = tail_q && (fbf_read_addr == (fbf_min_addr + idx));
		
	     end
	   
	   assign flit_tail_out = |tail_queue;
	   
	   // overflow and underflow are already handled in fifo_ctrl
	   assign tail_tracker_error = 1'b0;
	   
	   assign get_next_header = ~valid_q | (all_allocated & flit_tail_out);
	   
	end
      else
	begin
	   
	   // after we've seen a tail flit coming in, we need to wait for the
	   // whole flit buffer to drain before we accept the next heeader
	   wire wait_vc_empty_s, wait_vc_empty_q;
	   assign wait_vc_empty_s
	     = (wait_vc_empty_q | (flit_valid_in & flit_tail_in)) &
	       ~fbc_empty_early;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   wait_vc_emptyq
	     (.clk(clk),
	      .reset(reset),
	      .d(wait_vc_empty_s),
	      .q(wait_vc_empty_q));
	   
	   // we should not see new flits come in until the VC has been fully
	   // drained after the last packet
	   assign tail_tracker_error = wait_vc_empty_q & flit_valid_in;
	   
	   assign flit_tail_out = 1'b0;
	   
	   // start accepting new packets once VC buffer is fully drained after
	   // last one
	   assign get_next_header
	     = ~valid_q | (wait_vc_empty_q & fbc_empty_early);
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // header buffer
   //---------------------------------------------------------------------------
   
   wire 	hdff_empty;
   
   wire 	hdff_push;
   assign hdff_push
     = flit_valid_in & flit_head_in & (~hdff_empty | ~get_next_header);
   
   wire 	hdff_pop;
   assign hdff_pop = get_next_header & ~hdff_empty;
   
   wire [0:route_info_width-1] hdff_data;
   wire 		       hdff_error;
   
   generate
      
      if(num_header_buffers > 1)
	begin
	   
	   wire 		       hdff_full;
	   fifo
	     #(.depth(num_header_buffers-1),
	       .width(route_info_width),
	       .fifo_type(header_fifo_type),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type))
	   hdff
	     (.clk(clk),
	      .reset(reset),
	      .full(hdff_full),
	      .data_in(route_info_in),
	      .push(hdff_push),
	      .empty(hdff_empty),
	      .data_out(hdff_data),
	      .pop(hdff_pop),
	      .error(hdff_error));
	   
	end
      else
	begin
	   
	   assign hdff_empty = 1'b1;
	   assign hdff_data = {route_info_width{1'b0}};
	   assign hdff_error = 1'b0;
	   
	end
      
   endgenerate
   
   wire 		       next_valid;
   assign next_valid = (flit_valid_in & flit_head_in) | ~hdff_empty;
   
   wire [0:route_info_width-1] next_route_info;
   assign next_route_info = hdff_empty ? route_info_in : hdff_data;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1]        rtl_next_port;
   wire [0:num_vcs-1] 	       rtl_next_vcs;
   wire 		       rtl_error_unmasked;
   routing_logic
     #(.num_vcs(num_vcs),
       .num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_ports(num_ports),
       .num_dimensions(num_dimensions),
       .num_routers_per_dim(num_routers_per_dim),
       .num_neighbors_per_dim(num_neighbors_per_dim),
       .routing_function_type(routing_function_type),
       .reset_type(reset_type))
   rtl
     (.clk(clk),
      .reset(reset),
      .router_address(router_address),
      .route_info(next_route_info),
      .port_id(port_id),
      .vc_id(vc_id),
      .next_port(rtl_next_port),
      .next_vcs(rtl_next_vcs),
      .error(rtl_error_unmasked));
   
   wire 		       rtl_error;
   assign rtl_error = rtl_error_unmasked & get_next_header & next_valid;
   
   
   //---------------------------------------------------------------------------
   // currently active header
   //---------------------------------------------------------------------------
   
   wire 		       valid_s;
   assign valid_s = get_next_header ? next_valid : valid_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   validq
     (.clk(clk),
      .reset(reset),
      .d(valid_s),
      .q(valid_q));
   
   wire [0:num_ports-1]        port_s, port_q;
   assign port_s = get_next_header ? rtl_next_port : port_q;
   dff
     #(.width(num_ports),
       .reset_type(reset_type))
   portq
     (.clk(clk),
      .reset(reset),
      .d(port_s),
      .q(port_q));
   
   wire [0:num_vcs-1] 	       vcs_q;
   
   wire [0:num_vcs-1] 	       vcs_updated;
   assign vcs_updated = vc_gnt ? vc_gnt_ovc : vcs_q;
   
   wire [0:num_vcs-1] 	       vcs_s;
   assign vcs_s = get_next_header ? rtl_next_vcs : vcs_updated;
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vcsq
     (.clk(clk),
      .reset(reset),
      .d(vcs_s),
      .q(vcs_q));
   
   
   //---------------------------------------------------------------------------
   // credit tracking
   //---------------------------------------------------------------------------
   
   wire 		       cred_tracker_error;
   
   generate
      
      case(credit_handling_type)
	`CREDIT_HANDLING_TYPE_LEVEL:
	  begin
	     
	     select_1ofn
	       #(.num_ports(num_ports),
		 .width(1))
	     free_sel
	       (.select(port_q),
		.data_in(free_op),
		.data_out(free_unallocated));
	     
	     wire [0:num_vcs*2-1]        free_ovc;
	     select_1ofn
	       #(.num_ports(num_ports),
		 .width(num_vcs*2))
	     free_ovc_sel
	       (.select(port_q),
		.data_in(free_op_ovc),
		.data_out(free_ovc));
	     
	     wire 			 flit_sent_prev_s, flit_sent_prev_q;
	     assign flit_sent_prev_s = flit_sent & ~get_next_header;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     flit_sent_prevq
	       (.clk(clk),
		.reset(reset),
		.d(flit_sent_prev_s),
		.q(flit_sent_prev_q));
	     
	     wire [0:2] 		 flit_sent_count;
	     assign flit_sent_count = {flit_sent_prev_q & flit_sent,
				       flit_sent_prev_q ^ flit_sent,
				       ~(flit_sent_prev_q | flit_sent)};
	     
	     wire [0:num_vcs-1] 	 next_free_ovc;
	     
	     genvar 			 ovc;
	     for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	       begin:ovcs
		  
		  wire [0:1] free;
		  assign free = free_ovc[ovc*2:(ovc+1)*2-1];
		  
		  wire [0:2] free_by_count;
		  assign free_by_count = {|free, free[0], &free};
		  
		  wire       next_free;
		  select_1ofn
		    #(.num_ports(3),
		      .width(1))
		  next_free_sel
		    (.select(flit_sent_count),
		     .data_in(free_by_count),
		     .data_out(next_free));
		  
		  assign next_free_ovc[ovc] = next_free;
		  
	       end
	     
	     assign free_allocated = |(next_free_ovc & vcs_updated);
	     
	     assign cred_tracker_error = 1'b0;
	     
	  end
	`CREDIT_HANDLING_TYPE_PUSH:
	  begin
	     
	     assign free_unallocated = 1'b0;
	     
	     wire [0:num_vcs-1] 	       cred_ovc;
	     select_1ofn
	       #(.num_ports(num_ports),
		 .width(num_vcs))
	     cred_ovc_sel
	       (.select(port_q),
		.data_in(cred_op_ovc),
		.data_out(cred_ovc));
	     
	     wire 			       cred;
	     assign cred = |(cred_ovc & vcs_updated);
	     
	     wire [0:cred_hold_width-1]        cred_hold_q;
	     
	     wire 			       has_cred_s, has_cred_q;
	     assign has_cred_s
	       = (vc_gnt ?
		  ~sw_gnt_spec :
		  ((has_cred_q & ~sw_gnt_nonspec) | (|cred_hold_q))) | cred;
	     dff
	       #(.width(1),
		 .reset_type(reset_type))
	     has_credq
	       (.clk(clk),
		.reset(reset),
		.d(has_cred_s),
		.q(has_cred_q));
	     
	     assign free_allocated = has_cred_s;
	     
	     wire 			       incr_cred_hold;
	     assign incr_cred_hold = cred & ~sw_gnt_nonspec;
	     
	     wire 			       decr_cred_hold;
	     assign decr_cred_hold = ~cred & sw_gnt_nonspec & |cred_hold_q;
	     
	     wire [0:cred_hold_width-1]        cred_hold_s;
	     assign cred_hold_s
	       = vc_gnt ?
		 ({cred_hold_width{1'b0}} + (cred & ~sw_gnt_spec)) :
		 allocated_q ?
		 (cred_hold_q + incr_cred_hold - decr_cred_hold) :
		 cred_hold_q;
	     dff
	       #(.width(cred_hold_width),
		 .reset_type(reset_type))
	     cred_holdq
	       (.clk(clk),
		.reset(reset),
		.d(cred_hold_s),
		.q(cred_hold_q));
	     
	     assign cred_tracker_error
	       = allocated_q && (cred_hold_q == num_flit_buffers-1) &&
		 incr_cred_hold;
	     
	  end
      endcase
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate allocator control signals
   //---------------------------------------------------------------------------
   
   wire 				       fbc_empty;
   
   wire [0:num_ports-1] 		       sw_req_nonspec_op_s,
					       sw_req_nonspec_op_q;
   assign sw_req_nonspec_op_s
     = port_s &
       {num_ports{valid_s & ~fbc_empty_early & allocated_s & free_allocated}};
   dff
     #(.width(num_ports),
       .reset_type(reset_type))
   sw_req_nonspec_opq
     (.clk(clk),
      .reset(reset),
      .d(sw_req_nonspec_op_s),
      .q(sw_req_nonspec_op_q));
   
   assign sw_req_nonspec_op = sw_req_nonspec_op_q;
   
   generate
      
      if(sw_spec_enable)
	begin
	   
	   wire [0:num_ports-1] sw_req_spec_op_s, sw_req_spec_op_q;
	   assign sw_req_spec_op_s
	     = port_s & {num_ports{valid_s & ~fbc_empty_early & ~allocated_s}};
	   dff
	     #(.width(num_ports),
	       .reset_type(reset_type))
	   sw_req_spec_opq
	     (.clk(clk),
	      .reset(reset),
	      .d(sw_req_spec_op_s),
	      .q(sw_req_spec_op_q));
	   
	   case(credit_handling_type)
	     `CREDIT_HANDLING_TYPE_LEVEL:
	       begin
		  case(sw_spec_cred_check)
		    `SW_SPEC_CRED_CHECK_ALL_PRE:
		      begin
			 assign sw_req_spec_op
			   = sw_req_spec_op_q & free_unallocated;
		      end
		    `SW_SPEC_CRED_CHECK_ALL_POST, `SW_SPEC_CRED_CHECK_SEL_POST:
		      begin
			 assign sw_req_spec_op = sw_req_spec_op_q;
		      end
		  endcase
	       end
	     `CREDIT_HANDLING_TYPE_PUSH:
	       begin
		  assign sw_req_spec_op = sw_req_spec_op_q;
	       end
	   endcase
	   
	end
      else
	assign sw_req_spec_op = {num_ports{1'b0}};
      
   endgenerate
   
   assign vc_req_op = port_q;
   
   wire [0:num_vcs-1] 	       vc_req_ovc_s, vc_req_ovc_q;
   assign vc_req_ovc_s = vcs_s & {num_vcs{valid_s & ~allocated_s}};
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vc_req_ovcq
     (.clk(clk),
      .reset(reset),
      .d(vc_req_ovc_s),
      .q(vc_req_ovc_q));
   
   assign vc_req_ovc = vc_req_ovc_q;
   
   
   //---------------------------------------------------------------------------
   // generate target output VC to send along with flit data
   // (valid when flit_sent=1)
   //---------------------------------------------------------------------------
   
   // NOTE: don't need to use vc_gnt_ovc here, as flit_valid would not be
   // generated in the first place if grant was masked, so we don't care about
   // flit_vc_dec in this case!
   wire [0:num_vcs-1] 	       flit_vc_dec;
   assign flit_vc_dec = allocated_q ? vcs_q : vc_gnt_ovc;
   encoder
     #(.num_ports(num_vcs))
   vc_out_enc
     (.data_in(flit_vc_dec),
      .data_out(flit_vc_out));
   
   
   //---------------------------------------------------------------------------
   // flit buffer control
   //---------------------------------------------------------------------------
   
   wire 		       fbc_push;
   assign fbc_push = flit_valid_in;
   
   wire 		       fbc_pop;
   assign fbc_pop = all_allocated & ~fbc_empty;
   
   wire 		       fbc_error;
   wire 		       fbc_full;
   wire 		       fbc_full_early;
   fifo_ctrl
     #(.addr_width(fbf_addr_width),
       .offset(fbf_min_addr),
       .depth(num_flit_buffers),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push(fbc_push),
      .pop(fbc_pop),
      .write_addr(fbf_write_addr),
      .read_addr(fbf_read_addr),
      .empty(fbc_empty),
      .empty_early(fbc_empty_early),
      .full(fbc_full),
      .full_early(fbc_full_early),
      .error(fbc_error));
   
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   wire [0:4] 		       errors_in;
   assign errors_in = {~hdff_empty & ~valid_q,
                       ~fbc_empty & ~valid_q,
		       tail_tracker_error,
		       cred_tracker_error,
		       rtl_error};
   
   wire [0:4] 		       errors_out;
   checker
     #(.num_errors(5),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out | hdff_error | fbc_error;
   
   
   //---------------------------------------------------------------------------
   // instrumentation
   //---------------------------------------------------------------------------
   
   wire 		       ev_no_flit;
   assign ev_no_flit = valid_q & fbc_empty;
   
   wire 		       ev_flit_stalled_vc;
   assign ev_flit_stalled_vc = valid_q & ~fbc_empty & ~vc_allocated;
   
   wire 		       ev_flit_stalled_sw;
   assign ev_flit_stalled_sw = valid_q & ~fbc_empty & vc_allocated &
			       ~sw_allocated;
   
   wire 		       ev_spec_failed;
   assign ev_spec_failed = valid_q & ~fbc_empty & ~vc_allocated & sw_allocated;
   
   wire 		       ev_flit_sent;
   assign ev_flit_sent = valid_q & ~fbc_empty & all_allocated;
   
   wire 		       ev_flit_sent_spec;
   assign ev_flit_sent_spec = valid_q & ~fbc_empty & vc_gnt &
			      ~allocated_q & sw_allocated;
   
   generate
      
      if(perf_ctr_enable > 0)
	begin
	   wire [0:5] 	       events_s, events_q;
	   assign events_s = {ev_no_flit,
			      ev_flit_stalled_vc,
			      ev_flit_stalled_sw,
			      ev_spec_failed,
			      ev_flit_sent,
			      ev_flit_sent_spec};
	   dff
	     #(.width(6),
	       .reset_type(reset_type))
	   eventsq
	     (.clk(clk),
	      .reset(reset),
	      .d(events_s),
	      .q(events_q));
	   assign events = events_q;
	end
      else
	assign events = 6'd0;
      
   endgenerate
   
endmodule
