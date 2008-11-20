$Id$
module router
  (clk, reset, router_address, flit_valid_in_ip, flit_vc_in_ip, flit_head_in_ip,
   flit_tail_in_ip, flit_data_in_ip, cred_valid_out_ip, cred_vc_out_ip,
   flit_valid_out_op, flit_vc_out_op, flit_head_out_op, flit_tail_out_op,
   flit_data_out_op, cred_valid_in_op, cred_vc_in_op, error);
   
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
   
   // maximum number of packets that can be in a given VC buffer simultaneously
   parameter num_header_buffers = 4;
   
   // number of traffic classes (e.g. read, write)
   parameter num_traffic_classes = 2;
   
   // number of routing classes (e.g. minimal, adaptive)
   parameter num_routing_classes = 2;
   
   // total number of packet classes
   localparam num_classes = num_traffic_classes * num_routing_classes;
   
   // number of VCs per class
   parameter num_vcs_per_class = 1;
   
   // number of VCs
   localparam num_vcs = num_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);
   
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
   
   // flit width
   parameter data_width = 64;
   
   // enable performance counter
   parameter perf_ctr_enable = 1;
   
   // width of each counter
   parameter perf_ctr_width = 32;
   
   // include error checking logic
   parameter checker_enable = 1;
   parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;
   
   // select routing function type
   parameter routing_function_type = `ROUTING_FUNCTION_TYPE_BY_RELATION;
   
   // select method for credit signaling from output to input controller
   parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;
   
   // select implementation variant for header FIFO
   parameter header_fifo_type = `FIFO_TYPE_INDEXED;
   
   // select implementation variant for flit buffer register file
   parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;
   
   // select method for credit checking
   // (note: this parameter is only used for CREDIT_HANDLING_TYPE_LEVEL)
   parameter sw_spec_cred_check = `SW_SPEC_CRED_CHECK_SEL_POST;
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for VC allocator
   parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for switch allocator
   parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;
   
   // select which arbiter type to use for switch allocator
   parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select speculation level for switch allocator
   parameter sw_spec_level = `SW_SPEC_LEVEL_ANY_NONSPEC_MASKS;
   
   localparam sw_spec_enable = (sw_spec_level != `SW_SPEC_LEVEL_NONE);
   
   // select crossbar implementation variant
   parameter crossbar_type = `CROSSBAR_TYPE_MUX;
   
   // width of each crossbar port
   localparam crossbar_width = 1 + vc_idx_width + 2 + data_width;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // current router's address
   input [0:router_addr_width-1] router_address;
   
   // valid flit data available at input port(s)
   input [0:num_ports-1] flit_valid_in_ip;
   
   // which VC(s) is/are incoming flit(s) travelling on
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports*vc_idx_width-1] flit_vc_in_ip;
   
   // incoming flit(s) is/are head(s)
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports-1] flit_head_in_ip;
   
   // incoming flit(s) is/are tail(s)
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports-1] flit_tail_in_ip;
   
   // flit data for each incoming flit
   // (note: only valid when corresponding bit in flit_valid_in_ip is high)
   input [0:num_ports*data_width-1] flit_data_in_ip;
   
   // outgoing credit(s) valid
   output [0:num_ports-1] cred_valid_out_ip;
   wire [0:num_ports-1] cred_valid_out_ip;
   
   // VC indicators for outgoing credit(s)
   // (note: only valid when corresponding bit in cred_valid_out_ip is high)
   output [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   wire [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   // valid flit data available at output port(s)
   output [0:num_ports-1] flit_valid_out_op;
   wire [0:num_ports-1] 	     flit_valid_out_op;
   
   // which VC(s) is/are outgoing flit(s) travelling on
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   wire [0:num_ports*vc_idx_width-1] flit_vc_out_op;
   
   // outgoing flit(s) is/are head(s)
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports-1] flit_head_out_op;
   wire [0:num_ports-1] 	     flit_head_out_op;
   
   // outgoing flit(s) is/are tail(s)
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports-1] flit_tail_out_op;
   wire [0:num_ports-1] 	     flit_tail_out_op;
   
   // flit data for each outgoing flit
   // (note: only valid when corresponding bit in flit_valid_out_op is high)
   output [0:num_ports*data_width-1] flit_data_out_op;
   wire [0:num_ports*data_width-1]   flit_data_out_op;
   
   // incoming credit(s) available
   input [0:num_ports-1] cred_valid_in_op;
   
   // VC indicators for incoming flit(s)
   // (note: only valid when corresponding bit in cred_valid_in_op is high)
   input [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   // internal error condition detected
   output error;
   wire 			     error;
   
   
   //---------------------------------------------------------------------------
   // input ports
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	  elig_op_ovc;
   wire [0:num_vcs*num_ports-1] 	  free_ivc_op;
   wire [0:num_ports*num_vcs*2-1] 	  free_op_ovc;
   wire [0:num_ports*num_vcs-1] 	  cred_op_ovc;
   
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
	   
	   wire [0:port_idx_width-1] port_id;
	   assign port_id = ip;
	   
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
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_vcs(num_vcs),
	       .num_traffic_classes(num_traffic_classes),
	       .num_routing_classes(num_routing_classes),
	       .num_ports(num_ports),
	       .num_dimensions(num_dimensions),
	       .num_routers_per_dim(num_routers_per_dim),
	       .num_neighbors_per_dim(num_neighbors_per_dim),
	       .data_width(data_width),
	       .routing_function_type(routing_function_type),
	       .credit_handling_type(credit_handling_type),
	       .header_fifo_type(header_fifo_type),
	       .fbf_regfile_type(fbf_regfile_type),
	       .sw_spec_enable(sw_spec_enable),
	       .sw_spec_cred_check(sw_spec_cred_check),
	       .perf_ctr_enable(perf_ctr_enable),
	       .perf_ctr_width(perf_ctr_width),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .reset_type(reset_type))
	   ipc
	     (.clk(clk),
	      .reset(reset),
	      .router_address(router_address),
	      .port_id(port_id),
	      .flit_valid_in(flit_valid_in),
	      .flit_vc_in(flit_vc_in),
	      .flit_head_in(flit_head_in),
	      .flit_tail_in(flit_tail_in),
	      .flit_data_in(flit_data_in),
	      .free_ivc_op(free_ivc_op),
	      .free_op_ovc(free_op_ovc),
	      .cred_op_ovc(cred_op_ovc),
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
     #(.num_traffic_classes(num_traffic_classes),
       .num_routing_classes(num_routing_classes),
       .num_vcs_per_class(num_vcs_per_class),
       .num_ports(num_ports),
       .arbiter_type(vc_arbiter_type),
       .vc_allocator_type(vc_allocator_type),
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
     #(.num_vcs(num_vcs),
       .num_ports(num_ports),
       .sw_allocator_type(sw_allocator_type),
       .arbiter_type(sw_arbiter_type),
       .sw_spec_level(sw_spec_level),
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
	   wire [0:num_vcs-1] 	     cred_ovc;
	   wire 		     opc_error;
	   op_ctrl
	     #(.num_flit_buffers(num_flit_buffers),
	       .num_header_buffers(num_header_buffers),
	       .num_vcs(num_vcs),
	       .checker_enable(checker_enable),
	       .checker_capture_mode(checker_capture_mode),
	       .credit_handling_type(credit_handling_type),
	       .cred_level_width(2),
	       .reset_type(reset_type))
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
	      .cred_ovc(cred_ovc),
	      .error(opc_error));
	   
	   assign elig_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = elig_ovc;
	   assign free_op_ovc[op*num_vcs*2:(op+1)*num_vcs*2-1] = free_ovc;
	   assign free_op_ivc[op*num_vcs:(op+1)*num_vcs-1] = free_ivc;
	   assign cred_op_ovc[op*num_vcs:(op+1)*num_vcs-1] = cred_ovc;
	   
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
