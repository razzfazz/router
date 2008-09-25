module ivc_ctrl
  (clk, reset, flit_valid_in, flit_head_in, flit_tail_in, route_info_in,
   free_op, free_op_ovc, vc_req_op, vc_req_ovc, vc_gnt_ovc, sw_req_nonspec_op,
   sw_req_spec_op, sw_gnt_nonspec, sw_gnt_spec, flit_sent, flit_vc_out,
   flit_head_out, flit_tail_out, buff_write_addr, buff_read_addr, error,
   events);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "config_utils.v"
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter sw_spec_enable = 1;

   /*
    0: check that credit is available at all potential output VCs before issuing
       request
    1: check that credit is available at all potential output VCs in parallel
       with allocation, then mask grants
    2: check that credit is available at slected output VC while doing
       allocation, then mask grants
    */
   parameter sw_spec_cred_check = 0;
   
   // replicate port decoding logic in routing logic
   parameter replicate_port_decoder = 0;
   
   parameter perf_ctr_enable = 1;
   
   parameter checker_enable = 1;
   parameter checker_capture_mode = 0;
   parameter error_recovery = 0;
   
   parameter reset_type = reset_type_async;
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   parameter [0:port_idx_width-1] port_id = {port_idx_width{1'b0}};
   parameter [0:vc_idx_width-1] vc_id = {vc_idx_width{1'b0}};
   
   localparam [0:num_vcs*num_vcs-1] mask_ivc_ovc
     = create_mask_ivc_ovc(restrict_vcs);
   localparam [0:num_vcs-1] mask_ovc
     = mask_ivc_ovc[vc_id*num_vcs:(vc_id+1)*num_vcs-1];
   
   
   input clk;
   input reset;
   
   input flit_valid_in;
   input flit_head_in;
   input flit_tail_in;
   
   input [0:route_info_width-1] route_info_in;
   
   input [0:num_ports-1] free_op;
   input [0:num_ports*num_vcs*2-1] free_op_ovc;
   
   output [0:num_ports-1] vc_req_op;
   output [0:num_vcs-1] vc_req_ovc;
   input [0:num_vcs-1] vc_gnt_ovc;
   
   output [0:num_ports-1] sw_req_nonspec_op;
   output [0:num_ports-1] sw_req_spec_op;
   input sw_gnt_nonspec;
   input sw_gnt_spec;
   
   output flit_sent;
   output [0:vc_idx_width-1] flit_vc_out;
   output flit_head_out;
   output flit_tail_out;
   
   output [0:buffer_idx_width-1] buff_write_addr;
   output [0:buffer_idx_width-1] buff_read_addr;
   
   output error;
   
   output [0:4] events;
   
   
   wire [0:num_ports-1] vc_req_op;
   wire [0:num_vcs-1] 	vc_req_ovc;
   
   wire [0:num_ports-1] sw_req_nonspec_op;
   wire [0:num_ports-1] sw_req_spec_op;
   
   wire 		flit_sent;
   wire [0:vc_idx_width-1] flit_vc_out;
   wire 		   flit_head_out;
   wire 		   flit_tail_out;
   
   wire [0:buffer_idx_width-1] buff_write_addr;
   wire [0:buffer_idx_width-1] buff_read_addr;
   
   wire 		       error;
   
   wire [0:4] 		       events;
   
   
   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	       vc_gnt_masked_ovc;
   assign vc_gnt_masked_ovc = vc_gnt_ovc & mask_ovc;
   
   wire 		       vc_gnt_masked;
   assign vc_gnt_masked = |vc_gnt_masked_ovc;
   
   wire 		       get_next_header;
   wire 		       allocated_s, allocated_q;
   assign allocated_s = (allocated_q | vc_gnt_masked) & ~get_next_header;
   dff
     #(.width(1),
       .reset_type(reset_type))
   allocatedq
     (.clk(clk),
      .reset(reset),
      .d(allocated_s),
      .q(allocated_q));
   
   wire 		       vc_allocated;
   wire 		       sw_allocated;
   wire 		       free_unallocated;
   wire 		       free_allocated;
   
   generate
      
      if(sw_spec_enable)
	begin
	   assign vc_allocated = vc_gnt_masked | allocated_q;
	   case(sw_spec_cred_check)
	     0:
	       begin
		  assign sw_allocated
		    = sw_gnt_nonspec | sw_gnt_spec;
	       end
	     1:
	       begin
		  assign sw_allocated
		    = sw_gnt_nonspec | (sw_gnt_spec & free_unallocated);
	       end
	     2:
	       begin
		  assign sw_allocated
		    = sw_gnt_nonspec | (sw_gnt_spec & free_allocated);
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
   
   wire 		       hvsr_empty;
   wire 		       hvsr_error;
   
   generate
      
      if(num_headers > 1)
	begin
	   
	   wire 		       hvsr_push;
	   assign hvsr_push = flit_valid_in;
	   
	   wire 		       hvsr_pop;
	   assign hvsr_pop = all_allocated & ~hvsr_empty;
	   
	   wire [0:1] 		       hvsr_data_in;
	   assign hvsr_data_in = {flit_head_in, flit_tail_in};
	   
	   wire 		       hvsr_full;
	   wire [0:1] 		       hvsr_data_out;
	   shift_register
	     #(.width(2),
	       .depth(num_buffers),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .error_recovery(error_recovery),
	       .reset_type(reset_type))
	   hvsr
	     (.clk(clk),
	      .reset(reset),
	      .full(hvsr_full),
	      .data_in(hvsr_data_in),
	      .push(hvsr_push),
	      .empty(hvsr_empty),
	      .data_out(hvsr_data_out),
	      .pop(hvsr_pop),
	      .error(hvsr_error));
	   
	   assign flit_head_out = hvsr_data_out[0];
	   assign flit_tail_out = hvsr_data_out[1];
	   
	   assign get_next_header = ~valid_q | (all_allocated & flit_tail_out);
	   
	end
      else
	begin
	   
	   wire wait_tail_s, wait_tail_q;
	   assign wait_tail_s = (wait_tail_q | (flit_valid_in & flit_tail_in)) &
				~fbc_empty_early;
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   wait_tailq
	     (.clk(clk),
	      .reset(reset),
	      .d(wait_tail_s),
	      .q(wait_tail_q));
	   
	   assign hvsr_error = wait_tail_q & flit_valid_in;
	   
	   assign hvsr_empty = 1'b1;
	   assign flit_head_out = 1'b0;
	   assign flit_tail_out = 1'b0;
	   
	   assign get_next_header = ~valid_q | (wait_tail_q & fbc_empty_early);
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // header buffer
   //---------------------------------------------------------------------------
   
   wire 		       hdsr_empty;
   
   wire 		       hdsr_push;
   assign hdsr_push
     = flit_valid_in & flit_head_in & (~hdsr_empty | ~get_next_header);
   
   wire 		       hdsr_pop;
   assign hdsr_pop = get_next_header & ~hdsr_empty;
   
   wire [0:route_info_width-1] hdsr_data;
   wire 		       hdsr_error;
   
   generate
      
      if(num_headers > 1)
	begin
	   
	   wire 		       hdsr_full;
	   shift_register
	     #(.width(route_info_width),
	       .depth(num_headers-1),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .error_recovery(error_recovery),
	       .reset_type(reset_type))
	   hdsr
	     (.clk(clk),
	      .reset(reset),
	      .full(hdsr_full),
	      .data_in(route_info_in),
	      .push(hdsr_push),
	      .empty(hdsr_empty),
	      .data_out(hdsr_data),
	      .pop(hdsr_pop),
	      .error(hdsr_error));
	   
	end
      else
	begin
	   
	   assign hdsr_empty = 1'b1;
	   assign hdsr_data = {route_info_width{1'b0}};
	   assign hdsr_error = 1'b0;
	   
	end
      
   endgenerate
   
   wire 		       next_valid;
   assign next_valid = (flit_valid_in & flit_head_in) | ~hdsr_empty;
   
   wire [0:route_info_width-1] next_route_info;
   assign next_route_info = hdsr_empty ? route_info_in : hdsr_data;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1]        rtl_next_port;
   wire [0:num_vcs-1] 	       rtl_next_vcs;
   wire 		       rtl_error_unmasked;
   routing_logic
     #(.replicate_port_decoder(replicate_port_decoder),
       .address(address),
       .reset_type(reset_type))
   rtl
     (.clk(clk),
      .reset(reset),
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
   assign vcs_updated = vc_gnt_masked ? vc_gnt_masked_ovc : vcs_q;
   
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
   
   wire 		       flit_sent_prev_s, flit_sent_prev_q;
   assign flit_sent_prev_s = flit_sent;
   dff
     #(.width(1),
       .reset_type(reset_type))
   flit_sent_prevq
     (.clk(clk),
      .reset(reset),
      .d(flit_sent_prev_s),
      .q(flit_sent_prev_q));
   
   wire [0:2]                  flit_sent_count;
   assign flit_sent_count = {flit_sent_prev_q & flit_sent,
			     flit_sent_prev_q ^ flit_sent,
			     ~(flit_sent_prev_q | flit_sent)};
   
   wire [0:num_vcs-1] 	       next_free_ovc;
   
   generate
      
      genvar 		       ovc;
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
      
   endgenerate
   
   assign free_allocated = |(next_free_ovc & vcs_updated & mask_ovc);
   
   
   //---------------------------------------------------------------------------
   // generate allocator control signals
   //---------------------------------------------------------------------------
   
   wire 		       fbc_empty;
   
   wire [0:num_ports-1]        sw_req_nonspec_op_s, sw_req_nonspec_op_q;
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
	   
	   case(sw_spec_cred_check)
	     0:
	       begin
		  assign sw_req_spec_op = sw_req_spec_op_q & free_unallocated;
	       end
	     1, 2:
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
   
   // NOTE: don't need to use vc_gnt_masked_ovc here, as flit_valid would not be
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
   fifo_ctrl
     #(.depth(num_buffers),
       .checker_enable(checker_enable),
       .checker_capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push(fbc_push),
      .pop(fbc_pop),
      .write_addr(buff_write_addr),
      .read_addr(buff_read_addr),
      .empty(fbc_empty),
      .empty_early(fbc_empty_early),
      .error(fbc_error));
   
   //---------------------------------------------------------------------------
   // error checking
   //---------------------------------------------------------------------------
   
   wire [0:3] 		       errors_in;
   assign errors_in = {~hvsr_empty & ~valid_q,
                       ~hdsr_empty & ~valid_q,
                       ~fbc_empty & ~valid_q,
		       rtl_error};
   
   wire [0:3] 		       errors_out;
   checker
     #(.num_errors(4),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out | hvsr_error | hdsr_error | fbc_error;
   
   
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
   
   wire 		       ev_flit_sent;
   assign ev_flit_sent = valid_q & ~fbc_empty & all_allocated;
   
   wire 		       ev_flit_sent_spec;
   assign ev_flit_sent_spec = valid_q & ~fbc_empty & vc_gnt_masked &
			      ~allocated_q & sw_allocated;
   
   generate

      if(perf_ctr_enable > 0)
	begin
	   wire [0:4] 	       events_s, events_q;
	   assign events_s = {ev_no_flit,
			      ev_flit_stalled_vc,
			      ev_flit_stalled_sw,
			      ev_flit_sent,
			      ev_flit_sent_spec};
	   dff
	     #(.width(5),
	       .reset_type(reset_type))
	   eventsq
	     (.clk(clk),
	      .reset(reset),
	      .d(events_s),
	      .q(events_q));
	   assign events = events_q;
	end
      else
	begin
	   assign events = 5'd0;
	end
      
   endgenerate
   
endmodule
