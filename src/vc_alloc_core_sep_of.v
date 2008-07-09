module vc_alloc_core_sep_of
  (clk, reset, vc_req_ip_ivc_op, vc_req_ip_ivc_ovc, vc_gnt_ip_ivc,
   vc_gnt_ip_ivc_ovc, vc_gnt_op_ovc);
   
   
`include "config.v"
`include "constants.v"
   
   
   parameter reset_type = reset_type_async;
   
   /* supported architectures:
    0: use round-robin arbiters
    1: use matrix arbiters */
   parameter architecture = 0;
   
   // ignore requests for output port same as input port
   parameter ignore_same_port = 1;
   
   // restrict which VCs a given packet can go on
   parameter restrict_vcs = 1;
   
   localparam architecture_arb = architecture & 1;
   
   
   input clk;
   input reset;
   
   input [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   input [0:num_ports*num_vcs*num_vcs-1] vc_req_ip_ivc_ovc;
   
   output [0:num_ports*num_vcs-1] vc_gnt_ip_ivc;
   output [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   output [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   
   wire [0:num_ports*num_vcs-1] vc_gnt_ip_ivc;
   wire [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs-1] 	vc_gnt_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // utility functions
   //---------------------------------------------------------------------------
   
   function [0:num_ports-1] port_mask(input integer port);
      begin
	 port_mask = {num_ports{1'b1}};
	 if(ignore_same_port)
	   port_mask[port] = 1'b0;
      end
   endfunction
   
   function [0:num_vcs-1] vc_mask(input integer vc);
      integer i;
      begin
	 vc_mask = {num_vcs{1'b0}};
	 for(i = 0; i < num_vcs; i = i + 1)
	   if(!restrict_vcs ||
	      ((get_traffic_class(vc) == get_traffic_class(i)) &&
	       ((get_routing_class(vc) != routing_class_minimal) ||
		(get_routing_class(i) == routing_class_minimal))))
	     vc_mask[i] = 1'b1;
      end
   endfunction
   
   function [0:num_vcs-1] vc_mask_rev(input integer vc);
      integer i;
      begin
	 vc_mask_rev = {num_vcs{1'b0}};
	 for(i = 0; i < num_vcs; i = i + 1)
	   if(!restrict_vcs ||
	      ((get_traffic_class(vc) == get_traffic_class(i)) &&
	       ((get_routing_class(vc) == routing_class_minimal) ||
		(get_routing_class(i) != routing_class_minimal))))
	     vc_mask_rev[i] = 1'b1;
      end
   endfunction
   
   function integer port_count(input integer port);
      begin
	 port_count = ignore_same_port ? num_ports - 1 : num_ports;
      end
   endfunction
   
   function integer vc_count(input integer vc);
      integer i;
      begin
	 vc_count = 0;
	 for(i = 0; i < num_vcs; i = i + 1)
	   if(!restrict_vcs ||
	      ((get_traffic_class(vc) == get_traffic_class(i)) &&
	       ((get_routing_class(vc) != routing_class_minimal) ||
		(get_routing_class(i) == routing_class_minimal))))
	     vc_count = vc_count + 1;
      end
   endfunction
   
   function integer vc_count_rev(input integer vc);
      integer i;
      begin
	 vc_count_rev = 0;
	 for(i = 0; i < num_vcs; i = i + 1)
	   if(!restrict_vcs ||
	      ((get_traffic_class(vc) == get_traffic_class(i)) &&
	       ((get_routing_class(vc) == routing_class_minimal) ||
		(get_routing_class(i) != routing_class_minimal))))
	     vc_count_rev = vc_count_rev + 1;
      end
   endfunction
   
   
   //---------------------------------------------------------------------------
   // global wires
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_ip_ivc_op_ovc;
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_in_ip_ivc_op_ovc;
   
   
   //---------------------------------------------------------------------------
   // input stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  ip;
      for(ip = 0; ip < num_ports; ip = ip + 1)
	begin:ips
	   
	   genvar ivc;
	   for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	     begin:ivcs
		
		//--------------------------------------------------------------
		// generate requests for output stage
		//--------------------------------------------------------------
		
		wire [0:num_ports-1] 	     vc_req_op;
		if(ignore_same_port)
		  assign vc_req_op
		    = vc_req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				       (ip*num_vcs+ivc+1)*num_ports-1] &
		      port_mask(ip);
		else
		  assign vc_req_op
		    = vc_req_ip_ivc_op[(ip*num_vcs+ivc)*num_ports:
				       (ip*num_vcs+ivc+1)*num_ports-1];
		
		wire [0:num_vcs-1] 	     vc_req_ovc;
		if(restrict_vcs)
		  assign vc_req_ovc
		    = vc_req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
					(ip*num_vcs+ivc+1)*num_vcs-1] &
		      vc_mask(ivc);
		else
		  assign vc_req_ovc
		    = vc_req_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
					(ip*num_vcs+ivc+1)*num_vcs-1];
		
		wire [0:num_ports*num_vcs-1] port_mask_op_ovc;
		replicator
		  #(.width(num_ports),
		    .count(num_vcs))
		port_mask_op_ovc_repl
		  (.data_in(vc_req_op),
		   .data_out(port_mask_op_ovc));
		
		wire [0:num_ports*num_vcs-1] req_out_op_ovc;
		assign req_out_op_ovc = port_mask_op_ovc &
					{num_ports{vc_req_ovc}};
		
		assign req_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					     (ip*num_vcs+ivc+1)*num_ports*
					     num_vcs-1]
			 = req_out_op_ovc;
		
		
		//--------------------------------------------------------------
		// first arbitration stage (select output VC)
		//--------------------------------------------------------------
		
		wire [0:num_ports*num_vcs-1] gnt_out_op_ovc;
		assign gnt_out_op_ovc
		  = gnt_out_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					  (ip*num_vcs+ivc+1)*num_ports*num_vcs
					  -1];
		
		wire [0:num_vcs-1] 	     gnt_out_ovc;
		or_nto1
		  #(.width(num_vcs),
		    .num_ports(num_ports))
		gnt_out_ovc_or
		  (.data_in(gnt_out_op_ovc),
		   .data_out(gnt_out_ovc));
		
		wire 			     gnt_out;
		assign gnt_out = |gnt_out_ovc;
		
		wire 			     update_arb;
		assign update_arb = gnt_out;
		
		wire [0:num_vcs-1] 	     req_in_ovc;
		assign req_in_ovc = gnt_out_ovc;
		
		wire [0:num_vcs-1] 	     gnt_in_ovc;
		if(restrict_vcs)
		  begin
		     if(vc_count(ivc) > 1)
		       begin
			  wire [0:vc_count(ivc)-1] req_in_ovc_trunc;
			  extractor
			    #(.width(num_vcs),
			      .mask(vc_mask(ivc)))
			  req_in_ovc_trunc_extr
			    (.data_in(req_in_ovc),
			     .data_out(req_in_ovc_trunc));
			  
			  wire [0:vc_count(ivc)-1] gnt_in_ovc_trunc;
			  arbiter
			    #(.num_ports(vc_count(ivc)),
			      .reset_type(reset_type),
			      .architecture(architecture_arb))
			  gnt_in_ovc_arb
			    (.clk(clk),
			     .reset(reset),
			     .update(update_arb),
			     .req(req_in_ovc_trunc),
			     .gnt(gnt_in_ovc_trunc));
			  
			  spreader
			    #(.width(num_vcs),
			      .mask(vc_mask(ivc)))
			  gnt_in_ovc_sprd
			    (.data_in(gnt_in_ovc_trunc),
			     .data_out(gnt_in_ovc));
		       end
		     else
		       begin
			  assign gnt_in_ovc = req_in_ovc & vc_mask(ivc);
		       end
		  end
		else
		  begin
		     arbiter
		       #(.num_ports(num_vcs),
			 .reset_type(reset_type),
			 .architecture(architecture_arb))
		     gnt_in_ovc_arb
		       (.clk(clk),
			.reset(reset),
			.update(update_arb),
			.req(req_in_ovc),
			.gnt(gnt_in_ovc));
		  end
		
		wire [0:num_ports*num_vcs-1] gnt_in_op_ovc;
		assign gnt_in_op_ovc = port_mask_op_ovc &
				       {num_ports{gnt_in_ovc}};
		
		assign gnt_in_ip_ivc_op_ovc[(ip*num_vcs+ivc)*num_ports*num_vcs:
					    (ip*num_vcs+ivc+1)*num_ports*num_vcs
					    -1]
			 = gnt_in_op_ovc;
		
		
		//--------------------------------------------------------------
		// generate global grants
		//--------------------------------------------------------------
		
		assign gnt_ip_ivc[ip*num_vcs+ivc] = gnt_out;
		
		assign gnt_ip_ivc_ovc[(ip*num_vcs+ivc)*num_vcs:
				      (ip*num_vcs+ivc+1)*num_vcs-1]
			 = gnt_in_ovc;
		
	     end
	   
	end
      
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // bit shuffling for changing sort order
   //---------------------------------------------------------------------------
   
   wire [0:num_ports*num_vcs-1] 	     gnt_in_op_ovc;
   or_nto1
     #(.width(num_ports*num_vcs),
       .num_ports(num_ports*num_vcs))
   gnt_in_op_ovc_or
     (.data_in(gnt_in_ip_ivc_op_ovc),
      .data_out(gnt_in_op_ovc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] req_out_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   req_out_op_ovc_ip_ivc_intl
     (.data_in(req_out_ip_ivc_op_ovc),
      .data_out(req_out_op_ovc_ip_ivc));
   
   wire [0:num_ports*num_vcs*num_ports*num_vcs-1] gnt_out_op_ovc_ip_ivc;
   interleaver
     #(.width(num_ports*num_vcs*num_ports*num_vcs),
       .num_blocks(num_ports*num_vcs))
   gnt_out_ip_ivc_op_ovc_intl
     (.data_in(gnt_out_op_ovc_ip_ivc),
      .data_out(gnt_out_ip_ivc_op_ovc));
   
   
   //---------------------------------------------------------------------------
   // output stage
   //---------------------------------------------------------------------------
   
   generate
      
      genvar 					  op;
      for (op = 0; op < num_ports; op = op + 1)
	begin:ops
	   
	   genvar ovc;
	   for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	     begin:ovcs
		
		//--------------------------------------------------------------
		// connect inputs
		//--------------------------------------------------------------
		
		
		//--------------------------------------------------------------
		// second stage arbitration (select input port and VC)
		//--------------------------------------------------------------
		
		wire 			     gnt_in;
		assign gnt_in = gnt_in_op_ovc[op*num_vcs+ovc];
		
		wire 			     update_arb;
		assign update_arb = gnt_in;
		
		wire [0:num_ports*num_vcs-1] req_out_ip_ivc;
		assign req_out_ip_ivc
		  = req_out_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					  (op*num_vcs+ovc+1)*num_ports*num_vcs
					  -1];
		
		wire [0:num_ports-1] 	     req_out_ip;
		wire [0:num_ports-1] 	     gnt_out_ip;
		
		wire [0:num_ports-1] 	     update_arb_ip;
		assign update_arb_ip = {num_ports{gnt_in}} & gnt_out_ip;
		
		wire [0:num_ports*num_vcs-1] gnt_out_ip_ivc;
		
		genvar 			     ip;
		for(ip = 0; ip < num_ports; ip = ip + 1)
		  begin:ips
		     
		     wire [0:num_vcs-1] req_out_ivc;
		     if(restrict_vcs)
		       assign req_out_ivc
			 = req_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1] &
			   vc_mask_rev(ovc);
		     else
		       assign req_out_ivc
			 = req_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1];
		     
		     assign req_out_ip[ip] = |req_out_ivc;
		     
		     wire [0:num_vcs-1] gnt_out_ivc;
		     if(restrict_vcs)
		       begin
			  if(vc_count_rev(ovc) > 1)
			    begin
			       wire [0:vc_count_rev(ovc)-1] req_out_ivc_trunc;
			       extractor
				 #(.width(num_vcs),
				   .mask(vc_mask_rev(ovc)))
			       req_out_ivc_trunc_extr
				 (.data_in(req_out_ivc),
				  .data_out(req_out_ivc_trunc));
			       
			       wire [0:vc_count_rev(ovc)-1] gnt_out_ivc_trunc;
			       arbiter
				 #(.num_ports(vc_count_rev(ovc)),
				   .reset_type(reset_type),
				   .architecture(architecture_arb))
			       gnt_out_ivc_arb
				 (.clk(clk),
				  .reset(reset),
				  .update(update_arb_ip[ip]),
				  .req(req_out_ivc_trunc),
				  .gnt(gnt_out_ivc_trunc));
			       
			       spreader
				 #(.width(num_vcs),
				   .mask(vc_mask_rev(ovc)))
			       gnt_out_ivc_sprd
				 (.data_in(gnt_out_ivc_trunc),
				  .data_out(gnt_out_ivc));
			    end
			  else
			    begin
			       assign gnt_out_ivc
				 = req_out_ivc & vc_mask_rev(ovc);
			    end
		       end
		     else
		       begin
			  arbiter
			    #(.num_ports(num_vcs),
			      .reset_type(reset_type),
			      .architecture(architecture_arb))
			  gnt_out_ivc_arb
			    (.clk(clk),
			     .reset(reset),
			     .update(update_arb),
			     .req(req_out_ivc),
			     .gnt(gnt_out_ivc));
		       end
		     
		     assign gnt_out_ip_ivc[ip*num_vcs:(ip+1)*num_vcs-1]
			      = gnt_out_ivc & {num_vcs{gnt_out_ip[ip]}};
		  end
		
		arbiter
		  #(.num_ports(num_ports),
		    .reset_type(reset_type),
		    .architecture(architecture_arb))
		gnt_out_ip_arb
		  (.clk(clk),
		   .reset(reset),
		   .update(update_arb),
		   .req(req_out_ip),
		   .gnt(gnt_out_ip));
		
		assign gnt_out_op_ovc_ip_ivc[(op*num_vcs+ovc)*num_ports*num_vcs:
					     (op*num_vcs+ovc+1)*num_ports*
					     num_vcs-1]
			 = gnt_out_ip_ivc;
		
	     end
	end
   endgenerate
   
   
   //---------------------------------------------------------------------------
   // generate global grant
   //---------------------------------------------------------------------------
   
   assign gnt_op_ovc = gnt_in_op_ovc;
   
endmodule
