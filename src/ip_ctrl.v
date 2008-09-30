module ip_ctrl
  (clk, reset, flit_valid_in, flit_vc_in, flit_head_in, flit_tail_in,
   flit_data_in, free_ivc_op, free_op_ovc, cred_op_ovc, vc_req_ivc_op,
   vc_req_ivc_ovc, vc_gnt_ivc_ovc, sw_req_nonspec_ivc_op, sw_req_spec_ivc_op,
   sw_gnt_nonspec_ivc, sw_gnt_spec_ivc, flit_valid_out, flit_vc_out,
   flit_head_out, flit_tail_out, flit_data_out, cred_valid_out, cred_vc_out,
   error);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
`include "config_utils.v"

   // select method for credit signaling from output to input controller
   //  0: indicate credit level to input side
   //  1: push credits to input side one by one
   parameter credit_handling_type = 1;
   
   // enable speculative (i.e., while VC is being allocated as well) switch
   // allocation
   parameter sw_spec_enable = 1;
   
   // select method for credit checking
   // (note: this parameter is only used if credit_handling_type=0)
   //  0: check that credit is available at all potential output VCs before
   //     issuing request
   //  1: check that credit is available at all potential output VCs in parallel
   //     with allocation, then mask grants
   //  2: check that credit is available at slected output VC while doing
   //     allocation, then mask grants
   parameter sw_spec_cred_check = 0;
   
   // replicate port decoding logic in routing logic
   parameter replicate_port_decoder = 0;
   
   parameter perf_ctr_enable = 1;
   parameter perf_ctr_width = 32;
   
   parameter checker_enable = 1;
   parameter checker_capture_mode = 0;
   parameter error_recovery = 0;
   
   parameter reset_type = reset_type_async;
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   parameter [0:port_idx_width-1] port_id = {port_idx_width{1'b0}};
   
   localparam fbf_depth = num_vcs*num_buffers;
   localparam fbf_addr_width = clogb(fbf_depth);
   
   localparam event_width = clogb(num_vcs) + 1;
   
   
   input clk;
   input reset;
   
   input flit_valid_in;
   input [0:vc_idx_width-1] flit_vc_in;
   input flit_head_in;
   input flit_tail_in;
   input [0:data_width-1] flit_data_in;
   
   input [0:num_vcs*num_ports-1] free_ivc_op;
   input [0:num_ports*num_vcs*2-1] free_op_ovc;
   
   input [0:num_ports*num_vcs-1] cred_op_ovc;
   
   output [0:num_vcs*num_ports-1] vc_req_ivc_op;
   output [0:num_vcs*num_vcs-1] vc_req_ivc_ovc;
   input [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
   
   output [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   output [0:num_vcs*num_ports-1] sw_req_spec_ivc_op;
   input [0:num_vcs-1] sw_gnt_nonspec_ivc;
   input [0:num_vcs-1] sw_gnt_spec_ivc;
   
   output flit_valid_out;
   output [0:vc_idx_width-1] flit_vc_out;
   output flit_head_out;
   output flit_tail_out;
   output [0:data_width-1] flit_data_out;
   
   output cred_valid_out;
   output [0:vc_idx_width-1] cred_vc_out;
   
   output error;
   
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
   
   wire 			error;
   
   
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
   wire [0:num_vcs-1] 		       ivcc_error_ivc;
   wire [0:num_vcs*6-1] 	       events_ivc;
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
	   wire 		   flit_head;
	   wire 		   flit_tail;
	   wire [0:buffer_idx_width-1] buff_write_addr;
	   wire [0:buffer_idx_width-1] buff_read_addr;
	   wire 		       ivcc_error;
	   wire [0:5] 		       events;
	   ivc_ctrl
	     #(.credit_handling_type(credit_handling_type),
	       .sw_spec_enable(sw_spec_enable),
	       .sw_spec_cred_check(sw_spec_cred_check),
	       .replicate_port_decoder(replicate_port_decoder),
	       .perf_ctr_enable(perf_ctr_enable),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .error_recovery(error_recovery),
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
	      .flit_head_out(flit_head),
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
	   assign flit_head_ivc[ivc] = flit_head;
	   assign flit_tail_ivc[ivc] = flit_tail;
	   assign buff_write_addr_ivc[ivc*buffer_idx_width:
				      (ivc+1)*buffer_idx_width-1]
		    = buff_write_addr;
	   assign buff_read_addr_ivc[ivc*buffer_idx_width:
				     (ivc+1)*buffer_idx_width-1]
		    = buff_read_addr;
	   assign ivcc_error_ivc[ivc] = ivcc_error;
	   assign events_ivc[ivc*6:(ivc+1)*6-1] = events;
	   
	end
      
   endgenerate
   
   assign error = |ivcc_error_ivc;
   
   
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
   assign update_addr = flit_head_in &&
			(address[0:router_addr_width-1] ==
			 next_address[0:router_addr_width-1]);
   
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
   
   generate
      
      if(num_headers > 1)
	begin
	   
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
	   
	   assign flit_data_out = fbf_read_data[0:data_width-1];
	   
	end
      else
	begin
	   
	   wire [0:(data_width+2)-1] 	       fbf_write_data;
	   assign fbf_write_data
	     = {flit_data_muxed, flit_head_in, flit_tail_in};
	   
	   wire [0:(data_width+2)-1] 	       fbf_read_data;
	   regfile
	     #(.width(data_width+2),
	       .depth(fbf_depth))
	   fbf
	     (.clk(clk),
	      .write_enable(fbf_write_enable),
	      .write_address(fbf_write_addr),
	      .write_data(fbf_write_data),
	      .read_address(fbf_read_addr),
	      .read_data(fbf_read_data));
	   
	   assign flit_data_out = fbf_read_data[0:data_width-1];
	   assign flit_head_out = fbf_read_data[data_width];
	   assign flit_tail_out = fbf_read_data[data_width+1];
	   
	end
      
   endgenerate
   
   
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
   
   generate

      if(num_headers > 1)
	begin
	   
	   // in this case, head and tail bits are tracked in input VC
	   // controller anyway, so we can just reuse that information here
	   wire flit_head_s, flit_head_q;
	   select_1ofn
	     #(.num_ports(num_vcs),
	       .width(1))
	   flit_head_s_sel
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
   
   
   //---------------------------------------------------------------------------
   // performance counters
   //---------------------------------------------------------------------------
   
   wire [0:6*num_vcs-1]        events;
   interleaver
     #(.width(num_vcs*6),
       .num_blocks(num_vcs))
   events_intl
     (.data_in(events_ivc),
      .data_out(events));
   
   genvar 		       ctr;
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
