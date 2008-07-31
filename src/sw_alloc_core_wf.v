module sw_alloc_core_wf
  (clk, reset, sw_req_ip_ivc_op, sw_gnt_ip_ivc, sw_gnt_ip_op);
   
`include "functions.v"
`include "constants.v"
`include "config.v"
`include "config_utils.v"
   
   parameter reset_type = reset_type_async;
   
   /*
    0: wavefront, mux inputs for priority
    1: wavefront, replicate logic for priorities
    2: wavefront, diagonal propagation allocator
    3: wavefront, rotate inputs for priority
    */
   parameter allocator_type = 0;
   
   /*
    0: round-robin arbiters
    1: matrix arbiters
    */
   parameter arbiter_type = 0;
   
   localparam [0:num_ports*num_ports-1] mask_ip_op
     = create_mask_ip_op(ignore_same_port);
   
   
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
	   // input-side arbitration (pre-select winning VC for each output)
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] sw_req_ivc_op;
	   assign sw_req_ivc_op
	     = sw_req_ip_ivc_op[ip*num_vcs*num_ports:
				(ip+1)*num_vcs*num_ports-1] &
	       {num_vcs{mask_ip_op[ip*num_ports:(ip+1)*num_ports-1]}};
	   
	   wire [0:num_vcs*num_ports-1] req_in_ivc_op;
	   assign req_in_ivc_op = sw_req_ivc_op;
	   
	   wire [0:num_ports-1] 	req_out_op;
	   or_nto1
	     #(.width(num_ports),
	       .num_ports(num_vcs))
	   req_out_op_or
	     (.data_in(sw_req_ivc_op),
	      .data_out(req_out_op));
	   
	   assign req_out_ip_op[ip*num_ports:(ip+1)*num_ports-1] = req_out_op;
	   
	   wire [0:num_ports*num_vcs-1] req_in_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req_in_op_ivc_intl
	     (.data_in(req_in_ivc_op),
	      .data_out(req_in_op_ivc));
	   
	   wire [0:num_ports-1] 	gnt_out_op;
	   assign gnt_out_op = gnt_out_ip_op[ip*num_ports:(ip+1)*num_ports-1];
	   
	   wire [0:num_ports*num_vcs-1] gnt_in_op_ivc;
	   genvar 			op;
	   for(op = 0; op < num_ports; op = op + 1)
	     begin:ops
		
		wire 			update_arb;
		assign update_arb = gnt_out_op[op];
		
		wire [0:num_vcs-1] 	req_in_ivc;
		assign req_in_ivc = req_in_op_ivc[op*num_vcs:(op+1)*num_vcs-1];
		
		wire [0:num_vcs-1] 	gnt_in_ivc;
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
		
		assign gnt_in_op_ivc[op*num_vcs:(op+1)*num_vcs-1] = gnt_in_ivc;
		
	     end
	   
	   wire [0:num_vcs*num_ports-1] gnt_in_ivc_op;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_ports))
	   gnt_in_ivc_op_intl
	     (.data_in(gnt_in_op_ivc),
	      .data_out(gnt_in_ivc_op));
	   
	   
	   //-------------------------------------------------------------------
	   // use output-side grants to select winning VC
	   //-------------------------------------------------------------------
	   
	   wire [0:num_vcs*num_ports-1] req_masked_ivc_op;
	   assign req_masked_ivc_op = {num_vcs{gnt_out_op}} & gnt_in_ivc_op;
	   
	   wire [0:num_ports*num_vcs-1] req_masked_op_ivc;
	   interleaver
	     #(.width(num_vcs*num_ports),
	       .num_blocks(num_vcs))
	   req_masked_ivc_op_intl
	     (.data_in(req_masked_ivc_op),
	      .data_out(req_masked_op_ivc));
	   
	   wire [0:num_vcs-1] 		sw_gnt_ivc;
	   or_nto1
	     #(.width(num_vcs),
	       .num_ports(num_ports))
	   sw_gnt_ivc_or
	     (.data_in(req_masked_op_ivc),
	      .data_out(sw_gnt_ivc));
	   
	   assign sw_gnt_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] = sw_gnt_ivc;
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // output stage (match first-stage requests to output ports)
   //---------------------------------------------------------------------------
   
   // if there are any requests at all in a cycle, at least one of them will
   // eventually be granted, so update priorities
   wire 				update_alloc;
   assign update_alloc = |req_out_ip_op;
   
   wf_alloc
     #(.num_ports(num_ports),
       .reset_type(reset_type),
       .allocator_type(allocator_type),
       .mask(mask_ip_op))
   gnt_out_ip_op_alloc
     (.clk(clk),
      .reset(reset),
      .update(update_alloc),
      .req(req_out_ip_op),
      .gnt(gnt_out_ip_op));
   
   
   //---------------------------------------------------------------------------
   // generate global grants
   //---------------------------------------------------------------------------
   
   assign sw_gnt_ip_op = gnt_out_ip_op;
   
endmodule
