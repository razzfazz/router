module ip_ctrl
  (clk, reset, flit_valid_in, flit_vc_in, flit_head_in, flit_tail_in,
   flit_data_in, free_ivc_op, free_op_ovc, free_plus1_op_ovc, elig_op_ovc,
   vc_req_ivc_op, vc_req_ivc_ovc, vc_gnt_ivc_ovc, sw_req_nonspec_ivc_op,
   sw_req_spec_ivc_op, sw_gnt_ivc, flit_valid_out, flit_vc_out, flit_head_out,
   flit_tail_out, flit_data_out, cred_valid_out, cred_vc_out);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "config_utils.v"
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter enable_spec_sw_alloc = 1;
   
   // check for credit before issuing speculative switch allocation requests
   parameter spec_sw_alloc_checks_cred = 0;
   
   // replicate port decoding logic in routing logic
   parameter replicate_port_decoder = 0;
   
   parameter reset_type = reset_type_async;
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   parameter [0:port_idx_width-1] port_id = {port_idx_width{1'b0}};
   
   localparam fbf_depth = num_vcs*num_buffers;
   localparam fbf_addr_width = clogb(fbf_depth);
   
   
   input clk;
   input reset;
   
   input flit_valid_in;
   input [0:vc_idx_width-1] flit_vc_in;
   input flit_head_in;
   input flit_tail_in;
   input [0:data_width-1] flit_data_in;
   
   input [0:num_vcs*num_ports-1] free_ivc_op;
   input [0:num_ports*num_vcs-1] free_op_ovc;
   input [0:num_ports*num_vcs-1] free_plus1_op_ovc;
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   output [0:num_vcs*num_ports-1] vc_req_ivc_op;
   output [0:num_vcs*num_vcs-1] vc_req_ivc_ovc;
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   output [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   output [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   input [0:num_vcs-1] sw_gnt_ivc;
   
   output flit_valid_out;
   output [0:vc_idx_width-1] flit_vc_out;
   output flit_head_out;
   output flit_tail_out;
   output [0:data_width-1] flit_data_out;
   
   output cred_valid_out;
   output [0:vc_idx_width-1] cred_vc_out;
   
   wire [0:num_vcs*num_ports-1] vc_req_ivc_op;
   wire [0:num_vcs*num_vcs-1] 	vc_req_ivc_ovc;
   
   wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   wire [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   
   wire 			flit_valid_out;
   wire [0:vc_idx_width-1] 	flit_vc_out;
   wire 			flit_head_out;
   wire 			flit_tail_out;
   wire [0:data_width-1] 	flit_data_out;
   
   wire 			cred_valid_out;
   wire [0:vc_idx_width-1] 	cred_vc_out;
   
   
   //---------------------------------------------------------------------------
   // input vc controllers
   //---------------------------------------------------------------------------
   
   // extract routing information from header data
   wire [0:route_info_width-1] 	route_info_in;
   assign route_info_in = get_route_info(flit_data_in);
   
   wire [0:num_vcs-1] 		flit_sent_ivc;
   wire [0:num_vcs*vc_idx_width-1] flit_vc_ivc;
   wire [0:num_vcs-1] 		   flit_head_ivc;
   wire [0:num_vcs-1] 		   flit_tail_ivc;
   wire [0:num_vcs*buffer_idx_width-1] buff_write_addr_ivc;
   wire [0:num_vcs*buffer_idx_width-1] buff_read_addr_ivc;
   generate
      
      genvar 			ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire flit_valid;
	   assign flit_valid = flit_valid_in && (flit_vc_in == ivc);
	   
	   wire [0:num_ports-1] free_op;
	   assign free_op = free_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1];
	   
	   wire [0:num_vcs-1] 	vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1];
	   
	   wire 		sw_gnt;
	   assign sw_gnt = sw_gnt_ivc[ivc];
	   
	   wire [0:num_ports-1] vc_req_op;
	   wire [0:num_vcs-1] 	vc_req_ovc;
	   wire [0:num_ports-1] sw_req_nonspec_op;
	   wire [0:num_ports-1] sw_req_spec_op;
	   wire 		flit_sent;
	   wire [0:vc_idx_width-1] flit_vc;
	   wire 		   flit_head;
	   wire 		   flit_tail;
	   wire [0:buffer_idx_width-1] buff_write_addr;
	   wire [0:buffer_idx_width-1] buff_read_addr;
	   ivc_ctrl
	     #(.enable_spec_sw_alloc(enable_spec_sw_alloc),
	       .spec_sw_alloc_checks_cred(spec_sw_alloc_checks_cred),
	       .replicate_port_decoder(replicate_port_decoder),
	       .reset_type(reset_type),
	       .address(address),
	       .port_id(port_id),
	       .vc_id(ivc))
	   ivcc
	     (.clk(clk),
	      .reset(reset),
	      .flit_valid_in(flit_valid),
	      .flit_head_in(flit_head_in),
	      .flit_tail_in(flit_tail_in),
	      .route_info_in(route_info_in),
	      .free_op(free_op),
	      .free_op_ovc(free_op_ovc),
	      .free_plus1_op_ovc(free_plus1_op_ovc),
	      .elig_op_ovc(elig_op_ovc),
	      .vc_req_op(vc_req_op),
	      .vc_req_ovc(vc_req_ovc),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .sw_req_nonspec_op(sw_req_nonspec_op),
	      .sw_req_spec_op(sw_req_spec_op),
	      .sw_gnt(sw_gnt),
	      .flit_sent(flit_sent),
	      .flit_vc_out(flit_vc),
	      .flit_head_out(flit_head),
	      .flit_tail_out(flit_tail),
	      .buff_write_addr(buff_write_addr),
	      .buff_read_addr(buff_read_addr));
	   
	   assign vc_req_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1] = vc_req_op;
	   assign vc_req_ivc_ovc[ivc*num_vcs:(ivc+1)*num_vcs-1] = vc_req_ovc;
	   assign sw_req_nonspec_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = sw_req_nonspec_op;
	   assign sw_req_spec_ivc_op[ivc*num_ports:(ivc+1)*num_ports-1]
		    = sw_req_spec_op;
	   assign flit_sent_ivc[ivc] = flit_sent;
	   assign flit_vc_ivc[ivc*vc_idx_width:(ivc+1)*vc_idx_width-1]
		    = flit_vc;
	   assign flit_head_ivc[ivc] = flit_head;
	   assign flit_tail_ivc[ivc] = flit_tail;
	   assign buff_write_addr_ivc[ivc*buffer_idx_width:
				      (ivc+1)*buffer_idx_width-1]
		    = buff_write_addr;
	   assign buff_read_addr_ivc[ivc*buffer_idx_width:
				     (ivc+1)*buffer_idx_width-1]
		    = buff_read_addr;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // address computation
   //---------------------------------------------------------------------------
   
   wire [0:buffer_idx_width-1]        buff_write_offset;
   mux_nto1
     #(.num_ports(num_vcs),
       .width(buffer_idx_width))
   buff_write_offset_sel
     (.select(flit_vc_in),
      .data_in(buff_write_addr_ivc),
      .data_out(buff_write_offset));
   
   wire [0:buffer_idx_width-1]        buff_read_offset;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(buffer_idx_width))
   buff_read_offset_sel
     (.select(flit_sent_ivc),
      .data_in(buff_read_addr_ivc),
      .data_out(buff_read_offset));
   
   wire [0:vc_idx_width-1] 	       buff_write_base;
   assign buff_write_base = flit_vc_in;
   
   wire [0:vc_idx_width-1] 	       buff_read_base;
   encoder
     #(.num_ports(num_vcs))
   buff_read_base_enc
     (.data_in(flit_sent_ivc),
      .data_out(buff_read_base));
   
   wire [0:fbf_addr_width-1] 	       fbf_write_addr;
   assign fbf_write_addr = {buff_write_base, buff_write_offset};
   
   wire [0:fbf_addr_width-1] 	       fbf_read_addr;
   assign fbf_read_addr = {buff_read_base, buff_read_offset};
   
   
   //---------------------------------------------------------------------------
   // for adaptive routing, must update route info if we're transitioning from
   // non-minimal to minimal at this hop!
   //---------------------------------------------------------------------------
   
   wire [0:route_info_width-1] 	       route_info;
   assign route_info = get_route_info(flit_data_in);
   
   wire [0:addr_width-1] 	       next_address;
   assign next_address = get_next_address(route_info);
   
   wire [0:addr_width-1] 	       final_address;
   assign final_address = get_final_address(route_info);
   
   wire 			       update_addr;
   assign update_addr = flit_head_in && (address == next_address);
   
   wire [0:route_info_width-1] 	       next_route_info;
   assign next_route_info
     = create_route_info(update_addr ? final_address : next_address,
			 final_address);
   
   wire [0:data_width-1] 	       flit_data_muxed;
   assign flit_data_muxed = set_route_info(flit_data_in, next_route_info);
   
   
   //---------------------------------------------------------------------------
   // flit buffer
   //---------------------------------------------------------------------------
   
   wire 			       fbf_write_enable;
   assign fbf_write_enable = flit_valid_in;

   wire [0:data_width-1] 	       fbf_write_data;
   assign fbf_write_data = flit_data_muxed;

   wire [0:data_width-1] 	       fbf_read_data;
   regfile
     #(.width(data_width),
       .depth(fbf_depth))
   fbf
     (.clk(clk),
      .write_enable(fbf_write_enable),
      .write_address(fbf_write_addr),
      .write_data(fbf_write_data),
      .read_address(fbf_read_addr),
      .read_data(fbf_read_data));
   
   
   //---------------------------------------------------------------------------
   // generate outputs to switch
   //---------------------------------------------------------------------------
   
   wire 			       flit_valid_s, flit_valid_q;
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
   
   assign flit_data_out = fbf_read_data;
   
   // head and tail bits are tracked in input VC controllers, so reuse those
   wire 			       flit_head_s, flit_head_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   head_s_sel
     (.select(flit_sent_ivc),
      .data_in(flit_head_ivc),
      .data_out(flit_head_s));
   dff
     #(.width(1),
       .reset_type(reset_type))
   flit_headq
     (.clk(clk),
      .reset(reset),
      .d(flit_head_s),
      .q(flit_head_q));
   
   assign flit_head_out = flit_head_q;
   
   wire 			       flit_tail_s, flit_tail_q;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   tail_s_sel
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
   
   // output VCs are tracket in input VC controllers, so reuse these
   wire [0:vc_idx_width-1] 	       flit_vc_s, flit_vc_q;
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

   wire 		       cred_valid_s, cred_valid_q;
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
   
   wire [0:vc_idx_width-1]     cred_vc_s, cred_vc_q;
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
   
endmodule
