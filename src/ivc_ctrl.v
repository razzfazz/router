module ivc_ctrl
  (clk, reset, flit_valid_in, flit_head_in, flit_tail_in, route_info_in,
   free_op, free_op_ovc, free_plus1_op_ovc, elig_op_ovc, vc_req_op, vc_req_ovc,
   vc_gnt_ovc, sw_req_nonspec_op, sw_req_spec_op, sw_gnt, flit_sent,
   flit_vc_out, flit_head_out, flit_tail_out, buff_write_addr, buff_read_addr);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "config_utils.v"
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter enable_spec_sw_alloc = 1;
   
   // replicate port decoding logic in routing logic
   parameter replicate_port_decoder = 0;
   
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
   input [0:num_ports*num_vcs-1] free_op_ovc;
   input [0:num_ports*num_vcs-1] free_plus1_op_ovc;
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   output [0:num_ports-1] vc_req_op;
   output [0:num_vcs-1] vc_req_ovc;
   input [0:num_vcs-1] vc_gnt_ovc;
   
   output [0:num_ports-1] sw_req_nonspec_op;
   output [0:num_ports-1] sw_req_spec_op;
   input sw_gnt;
   
   output flit_sent;
   output [0:vc_idx_width-1] flit_vc_out;
   output flit_head_out;
   output flit_tail_out;
   
   output [0:buffer_idx_width-1] buff_write_addr;
   output [0:buffer_idx_width-1] buff_read_addr;
   
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
   
   
   //---------------------------------------------------------------------------
   // keep track of VC allocation status
   //---------------------------------------------------------------------------
   
   wire [0:num_vcs-1] 	       elig_ovc;
   
   wire [0:num_vcs-1] 	       vc_gnt_masked_ovc;
   assign vc_gnt_masked_ovc = vc_gnt_ovc & elig_ovc & mask_ovc;
   
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
   
   generate
      
      if(enable_spec_sw_alloc)
	assign vc_allocated = vc_gnt_masked | allocated_q;
      else
	assign vc_allocated = allocated_q;
      
   endgenerate
   
   wire 		       all_allocated;
   assign all_allocated = sw_gnt & vc_allocated;
   
   wire 		       valid_q;
   
   assign flit_sent = valid_q & all_allocated;
   
   
   //---------------------------------------------------------------------------
   // keep track of when to get next header
   //---------------------------------------------------------------------------
   
   wire 		       hvsr_empty;
   
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
       .reset_type(reset_type))
   hvsr
     (.clk(clk),
      .reset(reset),
      .full(hvsr_full),
      .data_in(hvsr_data_in),
      .push(hvsr_push),
      .empty(hvsr_empty),
      .data_out(hvsr_data_out),
      .pop(hvsr_pop));
   
   // synopsys translate_off
   wire 		       error_hvsr;
   assign error_hvsr = ~hvsr_empty & ~valid_q;
   // synopsys translate_on
   
   assign flit_head_out = hvsr_data_out[0];
   assign flit_tail_out = hvsr_data_out[1];
   
   assign get_next_header = ~valid_q | (all_allocated & flit_tail_out);
   
   
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
   
   generate
      
      if(num_headers > 1)
	begin
	   
	   wire 		       hdsr_full;
	   shift_register
	     #(.width(route_info_width),
	       .depth(num_headers-1),
	       .reset_type(reset_type))
	   hdsr
	     (.clk(clk),
	      .reset(reset),
	      .full(hdsr_full),
	      .data_in(route_info_in),
	      .push(hdsr_push),
	      .empty(hdsr_empty),
	      .data_out(hdsr_data),
	      .pop(hdsr_pop));
	   
	end
      else
	begin
	   
	   assign hdsr_empty = 1'b1;
	   assign hdsr_data = {data_width{1'b0}};
	   
	end
      
   endgenerate
   
   // synopsys translate_off
   wire 		       error_hdsr;
   assign error_hdsr = ~hdsr_empty & ~valid_q;
   // synopsys translate_on
   
   wire 		       next_valid;
   assign next_valid = (flit_valid_in & flit_head_in) | ~hdsr_empty;
   
   wire [0:route_info_width-1] next_route_info;
   assign next_route_info = hdsr_empty ? route_info_in : hdsr_data;
   
   
   //---------------------------------------------------------------------------
   // routing logic
   //---------------------------------------------------------------------------
   
   wire [0:num_ports-1]        rtl_next_port;
   wire [0:num_vcs-1] 	       rtl_next_vcs;
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
      .next_vcs(rtl_next_vcs));
   
   
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
   
   wire [0:num_vcs-1] 	       vcs_s, vcs_q;
   assign vcs_s = get_next_header ? 
		  (rtl_next_vcs & mask_ovc) :
		  (vc_gnt_masked ? vc_gnt_masked_ovc : vcs_q);
   dff
     #(.width(num_vcs),
       .reset_type(reset_type))
   vcsq
     (.clk(clk),
      .reset(reset),
      .d(vcs_s),
      .q(vcs_q));
   
   
   //---------------------------------------------------------------------------
   // VC eligibility and credit tracking
   //---------------------------------------------------------------------------
   
   select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs))       
   elig_ovc_sel
     (.select(port_q),
      .data_in(elig_op_ovc),
      .data_out(elig_ovc));
   
   wire 		       free_unallocated;
   select_1ofn
     #(.num_ports(num_ports),
       .width(1))
   free_sel
     (.select(port_q),
      .data_in(free_op),
      .data_out(free_unallocated));
   
   wire [0:num_vcs-1] 	       free_ovc;
   select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs))
   free_ovc_sel
     (.select(port_q),
      .data_in(free_op_ovc),
      .data_out(free_ovc));
   
   wire [0:num_vcs-1] 	       free_plus1_ovc;
   select_1ofn
     #(.num_ports(num_ports),
       .width(num_vcs))
   free_plus1_ovc_sel
     (.select(port_q),
      .data_in(free_plus1_op_ovc),
      .data_out(free_plus1_ovc));
   
   wire 		       free_allocated;
   assign free_allocated
     = |((flit_sent ? free_plus1_ovc : free_ovc) & vcs_s & mask_ovc);
   
   
   //---------------------------------------------------------------------------
   // generate allocator control signals
   //---------------------------------------------------------------------------
   
   wire 		       fbc_empty;
   wire 		       fbc_empty_early;
   
   wire [0:num_ports-1]        sw_req_nonspec_op_s, sw_req_nonspec_op_q;
   assign sw_req_nonspec_op_s
     = port_s & {num_ports{~fbc_empty_early & allocated_s & free_allocated}};
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
      
      if(enable_spec_sw_alloc)
	begin
	   wire [0:num_ports-1] sw_req_spec_op_s, sw_req_spec_op_q;
	   assign sw_req_spec_op_s
	     = port_s & {num_ports{~fbc_empty_early & ~allocated_s}};
	   dff
	     #(.width(num_ports),
	       .reset_type(reset_type))
	   sw_req_spec_opq
	     (.clk(clk),
	      .reset(reset),
	      .d(sw_req_spec_op_s),
	      .q(sw_req_spec_op_q));
	   
	   assign sw_req_spec_op = sw_req_spec_op_q & free_unallocated;
	end
      else
	assign sw_req_spec_op = {num_ports{1'b0}};
      
   endgenerate
   
   wire [0:num_ports-1]        vc_req_op_s, vc_req_op_q;
   assign vc_req_op_s = port_s & {num_ports{valid_s & ~allocated_s}};
   dff
     #(.width(num_ports),
       .reset_type(reset_type))
   vc_req_opq
     (.clk(clk),
      .reset(reset),
      .d(vc_req_op_s),
      .q(vc_req_op_q));
   
   assign vc_req_op = vc_req_op_q;
   
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
   assign fbc_pop = flit_sent & ~fbc_empty;
   
   fifo_ctrl
     #(.depth(num_buffers),
       .reset_type(reset_type))
   fbc
     (.clk(clk),
      .reset(reset),
      .push(fbc_push),
      .pop(fbc_pop),
      .write_addr(buff_write_addr),
      .read_addr(buff_read_addr),
      .empty(fbc_empty),
      .empty_early(fbc_empty_early));
   
   // synopsys translate_off
   wire 		       error_fbc;
   assign error_fbc = ~fbc_empty & ~valid_q;
   // synopsys translate_on   
   
endmodule
