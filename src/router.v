module router
  (clk, reset, flit_valid_in_ip, flit_vc_in_ip, flit_head_in_ip,
   flit_tail_in_ip, flit_data_in_ip, cred_valid_out_ip, cred_vc_out_ip,
   flit_valid_out_op, flit_vc_out_op, flit_head_out_op, flit_tail_out_op,
   flit_data_out_op, cred_valid_in_op, cred_vc_in_op, error);
   
`include "functions.v"
`include "config.v"
`include "constants.v"
   
   // enable performance counters
   parameter perf_ctr_enable = 1;
   
   // width of performance counters
   parameter perf_ctr_width = 32;
   
   // enable error checkers
   parameter checker_enable = 1;
   
   /*
    0: do not capture (hold) errors
    1: capture (hold) first error only
    2: capture (hold) all errors
    */
   parameter checker_capture_mode = 0;
   
   // enable error recovery
   parameter error_recovery = 0;
   
   parameter reset_type = reset_type_async;
   
   // current router's address
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   // replicate port decoding logic in routing logic
   parameter replicate_port_decoder = 1;
   
   /*
    0: separable, input-first
    1: separable, output-first
    */
   parameter vc_allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter vc_arbiter_type = 1;
   
   /*
    0: separable, input-first
    1: separable, output-first
    2: wavefront, mux inputs for priority
    3: wavefront, replicate logic for priorities
    4: wavefront, diagonal propagation allocator
    5: wavefront, rotate inputs for priority
    6: wavefront, false combinational loop
    */
   parameter sw_allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter sw_arbiter_type = 1;
   
   /*
    0: disable speculative switch allocation
    1: only use speculative grants if no non-speculative requests/grants present
    2: use speculative grants when not conflicting with non-spec requests
    3: use speculative grants when not conflicting with non-spec grants
    */
   parameter sw_spec_level = 3;
   
   /*
    0: check that credit is available at all potential output VCs before issuing
       request
    1: check that credit is available at all potential output VCs in parallel
       with allocation, then mask grants
    2: check that credit is available at slected output VC while doing
       allocation, then mask grants
    */
   parameter sw_spec_cred_check = 2;
   
   // select method for credit signaling from output to input controller
   //  0: indicate credit level to input side
   //  1: push credits to input side one by one
   parameter credit_handling_type = 1;
   
   /*
    0: use tristate buses
    1: use multiplexers
    */
   parameter crossbar_type = 1;
   
   localparam crossbar_width = 1 + vc_idx_width + 2 + data_width;
   
   
   input clk;
   input reset;
   
   input [0:num_ports-1] flit_valid_in_ip;
   input [0:num_ports*vc_idx_width-1] flit_vc_in_ip;
   input [0:num_ports-1] flit_head_in_ip;
   input [0:num_ports-1] flit_tail_in_ip;
   input [0:num_ports*data_width-1] flit_data_in_ip;
   
   output [0:num_ports-1] cred_valid_out_ip;
   output [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   output [0:num_ports-1] flit_valid_out_op;
   output [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   output [0:num_ports-1] flit_head_out_op;
   output [0:num_ports-1] flit_tail_out_op;
   output [0:num_ports*data_width-1] flit_data_out_op;
   
   input [0:num_ports-1] cred_valid_in_op;
   input [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   output error;
   
   wire [0:num_ports-1] cred_valid_out_ip;
   wire [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   wire [0:num_ports-1] 	     flit_valid_out_op;
   wire [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   wire [0:num_ports-1] 	     flit_head_out_op;
   wire [0:num_ports-1] 	     flit_tail_out_op;
   wire [0:num_ports*data_width-1]   flit_data_out_op;
   
   wire 			     error;
   
   
   //---------------------------------------------------------------------------
   // input ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	  elig_op_ovc;
   wire [0:num_vcs*num_ports-1] 	  free_ivc_op;
   wire [0:num_ports*num_vcs*2-1] 	  free_op_ovc;
   
   wire [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_req_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 	  vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs*num_ports-1] sw_req_nonspec_ip_ivc_op;
   wire [0:num_ports*num_vcs*num_ports-1] sw_req_spec_ip_ivc_op;
   wire [0:num_ports*num_vcs-1] 	  sw_gnt_nonspec_ip_ivc;
   wire [0:num_ports*num_vcs-1] 	  sw_gnt_spec_ip_ivc;
   wire [0:num_ports*num_ports-1] 	  sw_gnt_ip_op;
   
   wire [0:num_ports*crossbar_width-1] 	  xbr_data_in_ip;
   
   wire [0:num_ports-1] 		  ipc_error_ip;
   
   generate
      
      genvar 			   ip;
      for (ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   
	   //-------------------------------------------------------------------
	   // input controller
	   //-------------------------------------------------------------------
	   
	   wire flit_valid_in;
	   assign flit_valid_in = flit_valid_in_ip[ip];
	   
	   wire [0:vc_idx_width-1] flit_vc_in;
	   assign flit_vc_in = flit_vc_in_ip[ip*vc_idx_width:
					     (ip+1)*vc_idx_width-1];
	   
	   wire 		   flit_head_in;
	   assign flit_head_in = flit_head_in_ip[ip];
	   
	   wire 		   flit_tail_in;
	   assign flit_tail_in = flit_tail_in_ip[ip];
	   
	   wire [0:data_width-1]   flit_data_in;
	   assign flit_data_in = flit_data_in_ip[ip*data_width:
						 (ip+1)*data_width-1];
	   
	   wire [0:num_vcs*num_vcs-1] vc_gnt_ivc_ovc;
	   assign vc_gnt_ivc_ovc = vc_gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:
						     (ip+1)*num_vcs*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_nonspec_ivc;
	   assign sw_gnt_nonspec_ivc
	     = sw_gnt_nonspec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	      sw_gnt_spec_ivc;
	   assign sw_gnt_spec_ivc
	     = sw_gnt_spec_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
	   
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
	   wire 			ipc_error;
	   ip_ctrl
	     #(.credit_handling_type(credit_handling_type),
	       .sw_spec_enable(sw_spec_level > 0),
	       .sw_spec_cred_check(sw_spec_cred_check),
	       .replicate_port_decoder(replicate_port_decoder),
	       .address(address),
	       .port_id(ip),
	       .perf_ctr_enable(perf_ctr_enable),
	       .perf_ctr_width(perf_ctr_width),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .error_recovery(error_recovery),
	       .reset_type(reset_type))
	   ipc
	     (.clk(clk),
	      .reset(reset),
	      .flit_valid_in(flit_valid_in),
	      .flit_vc_in(flit_vc_in),
	      .flit_head_in(flit_head_in),
	      .flit_tail_in(flit_tail_in),
	      .flit_data_in(flit_data_in),
	      .free_ivc_op(free_ivc_op),
	      .free_op_ovc(free_op_ovc),
	      .vc_req_ivc_op(vc_req_ivc_op),
	      .vc_req_ivc_ovc(vc_req_ivc_ovc),
	      .vc_gnt_ivc_ovc(vc_gnt_ivc_ovc),
	      .sw_req_nonspec_ivc_op(sw_req_nonspec_ivc_op),
	      .sw_req_spec_ivc_op(sw_req_spec_ivc_op),
	      .sw_gnt_nonspec_ivc(sw_gnt_nonspec_ivc),
	      .sw_gnt_spec_ivc(sw_gnt_spec_ivc),
	      .flit_valid_out(flit_valid_out),
	      .flit_vc_out(flit_vc_out),
	      .flit_head_out(flit_head_out),
	      .flit_tail_out(flit_tail_out),
	      .flit_data_out(flit_data_out),
	      .cred_valid_out(cred_valid_out),
	      .cred_vc_out(cred_vc_out),
	      .error(ipc_error));
	   
	   assign vc_req_ip_ivc_op[ip*num_vcs*num_ports:
				   (ip+1)*num_vcs*num_ports-1] = vc_req_ivc_op;
	   assign vc_req_ip_ivc_ovc[ip*num_vcs*num_vcs:
				    (ip+1)*num_vcs*num_vcs-1] = vc_req_ivc_ovc;
	   assign sw_req_nonspec_ip_ivc_op[ip*num_vcs*num_ports:
					   (ip+1)*num_vcs*num_ports-1]
		    = sw_req_nonspec_ivc_op;
	   assign sw_req_spec_ip_ivc_op[ip*num_vcs*num_ports:
					(ip+1)*num_vcs*num_ports-1]
		    = sw_req_spec_ivc_op;
	   assign xbr_data_in_ip[ip*crossbar_width:(ip+1)*crossbar_width-1]
		    = {flit_valid_out, flit_vc_out, flit_head_out,
		       flit_tail_out, flit_data_out};
	   assign cred_valid_out_ip[ip] = cred_valid_out;
	   assign cred_vc_out_ip[ip*vc_idx_width:
				 (ip+1)*vc_idx_width-1] = cred_vc_out;
	   assign ipc_error_ip[ip] = ipc_error;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // virtual channel allocator
   //---------------------------------------------------------------------------
   
   vc_alloc
     #(.allocator_type(vc_allocator_type),
       .arbiter_type(vc_arbiter_type),
       .reset_type(reset_type))
   vca
     (.clk(clk),
      .reset(reset),
      .vc_req_ip_ivc_op(vc_req_ip_ivc_op),
      .vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
      .elig_op_ovc(elig_op_ovc),
      .vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
      .vc_gnt_op_ovc(vc_gnt_op_ovc));
   
   
   //---------------------------------------------------------------------------
   // switch allocator
   //---------------------------------------------------------------------------
   
   sw_alloc
     #(.allocator_type(sw_allocator_type),
       .arbiter_type(sw_arbiter_type),
       .spec_level(sw_spec_level),
       .error_recovery(error_recovery),
       .reset_type(reset_type))
   swa
     (.clk(clk),
      .reset(reset),
      .sw_req_nonspec_ip_ivc_op(sw_req_nonspec_ip_ivc_op),
      .sw_req_spec_ip_ivc_op(sw_req_spec_ip_ivc_op),
      .sw_gnt_nonspec_ip_ivc(sw_gnt_nonspec_ip_ivc),
      .sw_gnt_spec_ip_ivc(sw_gnt_spec_ip_ivc),
      .sw_gnt_ip_op(sw_gnt_ip_op));
   
   
   //---------------------------------------------------------------------------
   // crossbar
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	xbr_ctrl_ip_op_s, xbr_ctrl_ip_op_q;
   assign xbr_ctrl_ip_op_s = sw_gnt_ip_op;
   dff
     #(.width(num_ports*num_ports),
       .reset_type(reset_type))
   xbr_ctrl_ip_opq
     (.clk(clk),
      .reset(reset),
      .d(xbr_ctrl_ip_op_s),
      .q(xbr_ctrl_ip_op_q));
   
   wire [0:num_ports*crossbar_width-1] 	xbr_data_out_op;
   crossbar
     #(.num_ports(num_ports),
       .width(crossbar_width),
       .crossbar_type(crossbar_type))
   xbr_data
     (.ctrl_ip_op(xbr_ctrl_ip_op_q),
      .data_ip(xbr_data_in_ip),
      .data_op(xbr_data_out_op));
   
   
   //---------------------------------------------------------------------------
   // output ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	free_op_ivc;

   wire [0:num_ports-1] 		opc_error_op;
   
   generate
      
      genvar 			  op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   wire [0:crossbar_width-1] xbr_data_out;
	   assign xbr_data_out = xbr_data_out_op[op*crossbar_width:
						 (op+1)*crossbar_width-1];
	   
	   wire 		     flit_valid;
	   assign flit_valid = xbr_data_out[0];
	   
	   wire [0:vc_idx_width-1]   flit_vc;
	   assign flit_vc = xbr_data_out[1:vc_idx_width];
	   
	   wire 		     flit_head;
	   assign flit_head = xbr_data_out[vc_idx_width+1];
	   
	   wire 		     flit_tail;
	   assign flit_tail = xbr_data_out[vc_idx_width+2];
	   
	   wire [0:data_width-1]     flit_data;
	   assign flit_data = xbr_data_out[(vc_idx_width+3):
					   (vc_idx_width+3+data_width)-1];
	   
	   wire 		     cred_valid_in;
	   assign cred_valid_in = cred_valid_in_op[op];
	   
	   wire [0:vc_idx_width-1]   cred_vc_in;
	   assign cred_vc_in = cred_vc_in_op[op*vc_idx_width:
					     (op+1)*vc_idx_width-1];
	   
	   wire [0:num_vcs-1] 	     vc_gnt_ovc;
	   assign vc_gnt_ovc = vc_gnt_op_ovc[op*num_vcs:(op+1)*num_vcs-1];
	   
	   wire [0:num_vcs-1] 	     elig_ovc;
	   wire [0:num_vcs*2-1]      free_ovc;
	   wire [0:num_vcs-1] 	     free_ivc;
	   wire 		     opc_error;
	   op_ctrl
	     #(.checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type),
	       .credit_handling_type(credit_handling_type),
	       .cred_level_width(2))
	   opc
	     (.clk(clk),
	      .reset(reset),
	      .cred_valid_in(cred_valid_in),
	      .cred_vc_in(cred_vc_in),
	      .vc_gnt_ovc(vc_gnt_ovc),
	      .flit_valid_in(flit_valid),
	      .flit_vc_in(flit_vc),
	      .flit_tail_in(flit_tail),
	      .elig_ovc(elig_ovc),
	      .free_ovc(free_ovc),
	      .free_ivc(free_ivc),
	      .error(opc_error));
	   
	   assign elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = elig_ovc;
	   assign free_op_ovc[op*num_vcs*2:(op+1)*num_vcs*2-1] = free_ovc;
	   assign free_op_ivc[op*num_vcs:(op+1)*num_vcs-1] = free_ivc;
	   
	   assign flit_valid_out_op[op] 
		    = flit_valid;
	   assign flit_vc_out_op[op*vc_idx_width:(op+1)*vc_idx_width-1]
		    = flit_vc;
	   assign flit_head_out_op[op]
		    = flit_head;
	   assign flit_tail_out_op[op]
		    = flit_tail;
	   assign flit_data_out_op[op*data_width:(op+1)*data_width-1]
		    = flit_data;
	   assign opc_error_op[op] = opc_error;
	   
	end
      
   endgenerate
   
   //---------------------------------------------------------------------------
   // bit shuffling to change sort order
   //---------------------------------------------------------------------------
   
   interleaver
     #(.width(num_ports*num_vcs),
       .num_blocks(num_ports))
   free_ivc_op_intl
     (.data_in(free_op_ivc),
      .data_out(free_ivc_op));
   
   
   //---------------------------------------------------------------------------
   // error reporting
   //---------------------------------------------------------------------------
   
   wire [0:2*num_ports-1] 	     errors_in;
   assign errors_in = {ipc_error_ip, opc_error_op};
   
   wire [0:2*num_ports-1] 	     errors_out;
   checker
     #(.num_errors(2*num_ports),
       .enable(checker_enable),
       .capture_mode(checker_capture_mode),
       .reset_type(reset_type))
   chk
     (.clk(clk),
      .reset(reset),
      .errors_in(errors_in),
      .errors_out(errors_out));
   
   assign error = |errors_out;
   
endmodule
