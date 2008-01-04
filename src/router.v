module router(CLK, RST,
	      data_in,
	      data_out,
	      ctrl_in,
	      ctrl_out);

   parameter num_ports = 5;
   parameter num_vcs = 2;
   parameter addr_width = 8;
   parameter data_width = 32;
   parameter address = 0;
   
   localparam ctrl_width = clogb(num_vcs)+1;

   input CLK;
   input RST;

   input [0:num_ports*data_width-1] data_in;
   output [0:num_ports*data_width-1] data_out;

   input [0:num_ports*ctrl_width-1]  ctrl_in;
   output [0:num_ports*ctrl_width-1] ctrl_out;

   wire 			     clk = CLK;
   wire 			     reset = reset;

   // [sort order: input ports]
   wire [0:num_ports*data_width-1]   ipc_xbr_data_ip;
   wire [0:num_ports-1] 	     swa_xbr_ctrl_ip;
   
   genvar 			     i;
   
   generate
      for (i = 0; i < num_ports; i = i + 1)
	begin:input_ports
	   
	   wire [0:data_width-1] data;
	   
	   assign data = data_in[i*data_width:(i+1)*data_width-1];
	   
	   wire [0:ctrl_width-1] ctrl;

	   assign ctrl = ctrl_in[i*ctrl_width:(i+1)*ctrl_width-1];
	   
	   input_controller
	     #(.address(address),
	       .num_vcs(num_vcs),
	       .data_width(data_width),
	       .use_clock_gating(use_clock_gating))
	   ipc
	     (.clk(clk),
	      .reset(reset),
	      .data_in(data),
	      .data_out(ipc_xbr_data),
	      .cred_out(cred));

	   assign cred_out[] = cred;
	   
	end

      for(i = 0; i < num_ports; i = i + 1)
	begin:output_ports

	   output_controller
	     #(.num_vcs(num_vcs),
	       .ctrl_width
	end
      
   endgenerate

   vc_allocator
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .use_arbiter_type(use_arbiter_type),
       .use_clock_gating(use_clock_gating),
       .use_allocator_type(use_allocator_type))
   vca
     (.clk(clk),
      .reset(reset),
      .req(vc_alloc_req_ip_ivc_op_ovc),
      .gnt(vc_alloc_gnt_ip_ivc_op_ovc));

   switch_allocator
     #(.num_ports(num_ports),
       .num_vcs(num_vcs),
       .use_arbiter_type(use_arbiter_type),
       .use_clock_gating(use_clock_gating),
       .use_output_first(use_output_first),
       .use_allocator_type(use_allocator_type))
   swa
     (.clk(clk),
      .reset(reset),
      .req(sw_alloc_req_ip_ivc_op_ovc),
      .gnt(sw_alloc_gnt_ip_ivc_op_ovc));

   crossbar
     #(.num_ports(num_ports),
       .width(data_width))
   xbr
     (.data_in(ipc_xbr_data_ip),
      .ctrl_in(swa_xbr_ctrl),
      .data_out(data_out));
   
endmodule
