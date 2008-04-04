module router(CLK, RST,
	      valid_in,
	      head_in,
	      tail_in,
	      vc_in,
	      data_in,
	      cred_valid_out
	      cred_vc_out,
	      cred_type_out,
	      valid_out,
	      head_out,
	      tail_out,
	      vc_out,
	      data_out,
	      cred_valid_in,
	      cred_vc_in,
	      cred_type_in);

`include "functions.v"
   
   parameter num_ports = 5;
   parameter num_vcs = 2;
   parameter addr_width = 8;
   parameter data_width = 32;
   parameter address = 0;

   localparam vc_width = clogb(num_vcs);

   input CLK;
   input RST;

   input [0:num_ports-1] valid_in;
   input [0:num_ports-1] head_in;
   input [0:num_ports-1] tail_in;
   input [0:num_ports*vc_width-1] vc_in;
   input [0:num_ports*data_width-1] data_in;
   
   output wire [0:num_ports-1] cred_valid_out;
   output wire [0:num_ports*vc_width-1] cred_vc_out;
   output wire [0:num_ports-1] 		cred_type_out;
   
   output wire [0:num_ports-1] 		valid_out;
   output wire [0:num_ports-1] 		head_out;
   output wire [0:num_ports-1] 		tail_out;
   output wire [0:num_ports*vc_width-1] vc_out;
   output wire [0:num_ports*data_width-1] data_out;
   
   input [0:num_ports-1] cred_valid_in;
   input [0:num_ports*vc_width-1] cred_vc_in;
   input [0:num_ports-1] cred_type_in;
   
   wire 				  clk = CLK;
   wire 				  reset = reset;
   
   wire [0:num_ports*data_width-1]   fbf_ipc_data_ip;
   
   wire [0:num_ports*data_width-1]   ipc_xbr_data_ip;
   
   generate
      
      genvar 			     ip;
      for (ip = 0; i < num_ports; ip = ip + 1)
	begin:ips
	end
      
      genvar 			 op;
      for(op = 0; op < num_ports; op = op + 1)
	begin:ops
	end
      
   endgenerate
   
   vc_alloc
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .reset_type(reset_type),
       .hold_type(hold_type),
       .architecture(architecture_vca))
   vca
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op_ovc(ipc_vca_req_ip_ivc_op_ovc),
      .elig_op_ovc(opc_vca_elig_op_ovc),
      .gnt_ip_ivc_op_ovc(vca_opc_gnt_ip_ivc_op_ovc),
      .gnt_ip_ivc(vca_ipc_gnt_ip_ivc));

   wire [0:num_ports*num_ports-1] swa_xbr_gnt_ip_op;
   switch_allocator
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .reset_type(reset_type),
       .hold_type(hold_type),
       .architecture(architecture_swa))
   swa
     (.clk(clk),
      .reset(reset),
      .req_ip_ivc_op_ovc(ipc_swa_req_ip_ivc_op_ovc),
      .cred_op_ovc(opc_swa_cred_op_ovc),
      .gnt_ip_ivc(swa_ipc_gnt_ip_ivc),
      .gnt_ip_op(swa_xbr_gnt_ip_op));
   
   crossbar
     #(.num_ports(num_ports),
       .width(data_width+vc_width+2),
       .architecture(architecture_xbr))
   xbr
     (.data_ip({ipc_xbr_data_ip, ipc_xbr_vc_ip, ipc_xbr_head_ip,
		ipc_xbr_tail_ip}),
      .ctrl_in(swa_xbr_gnt_ip_op),
      .data_out({data_out, vc_out, head_out, tail_out}));

   or_nto1
     #(.width(num_ports),
       .num_ports(num_ports))
   or_gnt_ip
     (.data_in(swa_xbr_gnt_ip_op),
      .data_out(valid_out));

endmodule
