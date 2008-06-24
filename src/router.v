module router
  (CLK, RST, valid_in, vc_in, type_in, data_in, cred_valid_out, cred_vc_out,
   cred_type_out, valid_out, vc_out, type_out, data_out, cred_valid_in,
   cred_vc_in, cred_type_in);
   
   
`include "config.v"
`include "globals.v"
   
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   
   
   input CLK;
   input RST;
   
   input [0:num_ports*type_width-1] type_in_ip;
   input [0:num_ports*vc_idx_width-1] vc_in_ip;
   input [0:num_ports*data_width-1] data_in_ip;
   
   output [0:num_ports-1] cred_valid_out_ip;
   output [0:num_ports*vc_idx_width-1] cred_vc_out_ip;
   
   output [0:num_ports*type_width-1] type_out_op;
   output [0:num_ports*vc_idx_width-1] vc_out_op;
   output [0:num_ports*data_width-1] data_out_op;
   
   input [0:num_ports-1] cred_valid_in_op;
   input [0:num_ports*vc_idx_width-1] cred_vc_in_op;
   
   
   wire clk = CLK;
   wire reset = reset;
   
   wire [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_req_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 	  vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_gnt_ip_ivc_ovc;
   
   wire [0:num_ports*num_vcs*num_ports-1] sw_req_ip_ivc_op;
   wire [0:num_ports*num_vcs*num_ports-1] sw_req_nonspec_ip_ivc_op;
   wire [0:num_ports*num_vcs*num_vcs-1]   sw_req_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 	  sw_gnt_ip_ivc;
   
   wire [0:num_ports*data_width-1] 	  ipc_xbr_data_ip;
   wire [0:num_ports*vc_idx_width-1] 	  ipc_xbr_vc_ip;
   wire [0:num_ports*type_width-1] 	  ipc_xbr_type_ip;
   
   wire [0:num_ports*num_ports*num_vcs-1] vc_free_ip_op_ovc;
   
   
   // --------------------------------------------------------------------------
   // -- input ports
   // --------------------------------------------------------------------------
   
   generate
      
      genvar 			   ip;
      for (ip = 0; i < num_ports; ip = ip + 1)
	begin:ips

	   
	   // ------------------------------------------------------------------
	   // -- input controller
	   // ------------------------------------------------------------------
	   
	   ip_ctrl
	     #(.address(address),
	       .reset_type(reset_type))
	   ipc
	     (.clk(clk),
	      .reset(reset),
	      .data_in(data_in_ip[ip*data_width:(ip+1)*data_width-1]),
	      .vc_in(vc_in_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]),
	      .type_in(type_in_ip[ip*type_width:(ip+1)*type_width-1]),
	      .vc_req_ivc_op(vc_req_ip_ivc_op[ip*num_vcs*num_ports:
					      (ip+1)*num_vcs*num_ports-1]),
	      .vc_req_ivc_ovc(vc_req_ip_ivc_ovc[ip*num_vcs*num_vcs:
						(ip+1)*num_vcs*num_vcs]),
	      .vc_gnt_ivc(vc_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]),
	      .vc_gnt_ivc_ovc(vc_gnt_ip_ivc_ovc[ip*num_vcs*num_vcs:
						(ip+1)*num_vcs*num_vcs-1]),
	      .sw_req_ivc_op(sw_req_ip_ivc_op[ip*num_vcs*num_ports:
					      (ip+1)*num_vcs*num_ports-1]),
	      .sw_req_nonspec_ivc_op(sw_req_nonspec_ip_ivc_op[ip*num_vcs*
							      num_ports:
							      (ip+1)*num_vcs*
							      num_ports-1]),
	      .sw_req_ivc_ovc(sw_req_ip_ivc_ovc[ip*num_vcs*num_vcs:
						(ip+1)*num_vcs*num_vcs-1]),
	      .sw_gnt_ivc(sw_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]),
	      .data_out(ipc_xbr_data_ip[ip*data_width:(ip+1)*data_width-1]),
	      .vc_out(ipc_xbr_vc_ip[ip*vc_idx_width:(ip+1)*vc_idx_width-1]),
	      .type_out(ipc_xbr_type_ip[ip*type_width:(ip+1)*type_wdith-1]),
	      .cred_valid_out(cred_valid_out_ip[ip]),
	      .cred_vc_out(cred_vc_out_ip[ip*vc_idx_width:
					  (ip+1)*vc_idx_width-1]));

	   assign 
	   
	end
      
   endgenerate

   
   // --------------------------------------------------------------------------
   // -- virtual channel allocator
   // --------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] elig_op_ovc;
   wire [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   vc_alloc
     #(.reset_type(reset_type),
       .architecture(architecture_vca))
   vca
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op(vc_req_ip_ivc_op),
      .req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
      .elig_op_ovc(elig_op_ovc),
      .gnt_ip_ivc(vc_gnt_ip_ivc),
      .gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
      .gnt_op_ovc(vc_gnt_op_ovc));
   

   // --------------------------------------------------------------------------
   // -- switch allocator
   // --------------------------------------------------------------------------

   wire [0:num_ports*num_vcs-1] cred_op_ovc;
   sw_alloc
     #(.reset_type(reset_type),
       .architecture(architecture_swa))
   swa
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op(sw_req_ip_ivc_op),
      .req_ip_ivc_ovc(sw_req_ip_ivc_ovc),
      .cred_op_ovc(cred_op_ovc),
      .gnt_ip_ivc(sw_gnt_ip_ivc),
      .gnt_ip_op(sw_gnt_ip_op));
   
   
   // --------------------------------------------------------------------------
   // -- crossbar
   // --------------------------------------------------------------------------
   
   crossbar
     #(.num_ports(num_ports),
       .width(data_width),
       .architecture(architecture_xbr))
   xbr_data
     (.ctrl_in(sw_gnt_ip_op_q),
      .data_ip(ipc_xbr_data_ip),
      .data_op(data_out_op));
   
   crossbar
     #(.num_ports(num_ports),
       .width(vc_idx_width),
       .architecture(architecture_xbr))
   xbr_vc
     (.ctrl_in(sw_gnt_ip_op_q),
      .data_ip(ipc_xbr_vc_ip),
      .data_op(vc_out_op));
   
   crossbar
     #(.num_ports(num_ports),
       .width(type_width),
       .architecture(architecture_xbr))
   xbr_type
     (.ctrl_in(sw_gnt_ip_op_q),
      .data_ip(ipc_xbr_type_ip),
      .data_op(type_out_op));
   

   // --------------------------------------------------------------------------
   // -- output ports
   // --------------------------------------------------------------------------
   
   generate
      
      genvar 			  op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops

	   genvar ovc;
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		ovc_ctrl
		  #(.reset_type(reset_type))
		ovcc
		  (.clk(clk),
		   .reset(reset),
		   .push(),
		   .pop(),
		   .alloc(vc_gnt_op_ovc[op*num_vcs+ovc]),
		   .free(),
		   .elig(elig_op_ovc[op*num_vcs+ovc]),
		   .cred(cred_op_ovc[op*num_vcs+ovc]),
		   .errors());
		
	     end
	   
	end

   endgenerate

endmodule
