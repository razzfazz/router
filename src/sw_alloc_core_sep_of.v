module sw_alloc_core_sep_of
  (clk, reset, sw_req_ip_ivc_op, sw_gnt_ip_ivc, sw_gnt_ip_op);
   
`include "functions.v"
`include "constants.v"
`include "config.v"
`include "config_utils.v"
   
   parameter reset_type = reset_type_async;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter arbiter_type = 0;
   
   localparam [0:num_ports*num_ports-1] mask_ip_op
     = create_mask_ip_op(ignore_same_port);
   
   localparam [0:num_ports*num_ports-1] mask_op_ip
     = create_mask_op_ip(ignore_same_port);
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] sw_req_ip_ivc_op;
   
   output [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   output [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   wire [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   wire [0:num_ports*num_ports-1] sw_gnt_ip_op;
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] gnt_in_ip_op;
   wire [0:num_ports*num_ports-1] req_out_ip_op;
   wire [0:num_ports*num_ports-1] gnt_out_ip_op;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 			  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   //-------------------------------------------------------------------
	   // generate requests for output stage
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] sw_req_ivc_op;
	   assign sw_req_ivc_op
	     = sw_req_ip_ivc_op[ip*num_vcs*num_ports:
				(ip+1)*num_vcs*num_ports-1] &
	       {num_vcs{mask_ip_op[ip*num_ports:(ip+1)*num_ports-1]}};
	   
	   wire [0:num_ports-1] 	req_out_op;
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_out_op_or
	     (.data_in(sw_req_ivc_op),
	      .data_out(req_out_op));
	   
	   assign req_out_ip_op[ip*num_ports:(ip+1)*num_ports-1] = req_out_op;
	   
	   
	   //-------------------------------------------------------------------
	   // use output-side grants to filter out eligible input VCs
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] 	gnt_out_op;
	   assign gnt_out_op
	     = gnt_out_ip_op[ip*num_ports:(ip+1)*num_ports-1] &
	       mask_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_vcs*num_ports-1] req_masked_ivc_op;
	   assign req_masked_ivc_op = {num_vcs{gnt_out_op}} & sw_req_ivc_op;


	   wire [0:num_ports*num_vcs-1] req_masked_op_ivc;
	   interleaver
	     #(.width(num_ports*num_vcs),
	       .num_blocks(num_vcs))
	   req_masked_op_ivc_intl
	     (.data_in(req_masked_ivc_op),
	      .data_out(req_masked_op_ivc));
	   
	   wire [0:num_vcs-1] 		req_in_ivc;
	   or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   req_in_ivc_or
	     (.data_in(req_masked_op_ivc),
	      .data_out(req_in_ivc));
	   
	   
	   //-------------------------------------------------------------------
	   // perform input-side arbitration
	   //-------------------------------------------------------------------
	   
	   wire 			update_arb;
	   assign update_arb = |gnt_out_op;
	   
	   wire [0:num_vcs-1] 		     gnt_in_ivc;
	   arbiter
	     #(.num_ports(num_vcs),
	       .reset_type(reset_type),
	       .arbiter_type(arbiter_type))
	   gnt_in_ivc_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req_in_ivc),
	      .gnt(gnt_in_ivc));
	   
	   assign sw_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = gnt_in_ivc;
	   
	   
	   //-------------------------------------------------------------------
	   // generate global grants
	   //-------------------------------------------------------------------
	   
	   // since multiple ports may have been granted in the output stage, we
	   // must select the winning one
	   wire [0:num_ports-1] 	     sw_gnt_op;
	   select_1ofn
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   sw_gnt_op_sel
	     (.select(gnt_in_ivc),
	      .data_in(sw_req_ivc_op),
	      .data_out(sw_gnt_op));
	   
	   assign sw_gnt_ip_op[ip*num_ports:(ip+1)*num_ports-1] = sw_gnt_op;
	   
	   
	   //-------------------------------------------------------------------
	   // feed grants back to output stage
	   //-------------------------------------------------------------------
	   
	   assign gnt_in_ip_op[ip*num_ports:(ip+1)*num_ports-1] = sw_gnt_op;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_ports-1] 	     gnt_in_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_in_op_ip_intl
     (.data_in(gnt_in_ip_op),
      .data_out(gnt_in_op_ip));
   
   wire [0:num_ports*num_ports-1] 	     req_out_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   req_out_op_ip_intl
     (.data_in(req_out_ip_op),
      .data_out(req_out_op_ip));
   
   wire [0:num_ports*num_ports-1] 	     gnt_out_op_ip;
   interleaver
     #(.width(num_ports*num_ports),
       .num_blocks(num_ports))
   gnt_out_ip_op_intl
     (.data_in(gnt_out_op_ip),
      .data_out(gnt_out_ip_op));
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 				     op;
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   //-------------------------------------------------------------------
	   // output-side arbitration stage (select input port)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_ports-1] req_out_ip;
	   assign req_out_ip = req_out_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   wire [0:num_ports-1] gnt_in_ip;
	   assign gnt_in_ip = gnt_in_op_ip[op*num_ports:(op+1)*num_ports-1];
	   
	   // if any VC requesting this output port was granted at any input
	   // port in the first stage, the corresponding second-stage grant must
	   // have taken place before that, so we can update priorities
	   wire 		update_arb;
	   assign update_arb = |gnt_in_ip;
	   
	   wire [0:num_ports-1] gnt_out_ip;
	   arbiter
	     #(.num_ports(num_ports),
	       .reset_type(reset_type),
	       .arbiter_type(arbiter_type),
	       .mask(mask_op_ip[op*num_ports:(op+1)*num_ports-1]))
	   gnt_out_ip_arb
	     (.clk(clk),
	      .reset(reset),
	      .update(update_arb),
	      .req(req_out_ip),
	      .gnt(gnt_out_ip));
	   
	   assign gnt_out_op_ip[op*num_ports:(op+1)*num_ports-1] = gnt_out_ip;
	   
	end
      
   endgenerate
   
endmodule
