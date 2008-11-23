// $Id$
module vc_alloc
  (clk, reset, vc_req_ip_ivc_op, vc_req_ip_ivc_ovc, elig_op_ovc,
   vc_gnt_ip_ivc_ovc, vc_gnt_op_ovc);
   
`include "constants.v"
   
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
   
   // number of input and output ports on switch
   parameter num_ports = 5;
   
   // select which arbiter type to use in allocator
   parameter arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;
   
   // select implementation variant for VC allocator
   parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_SEP_IF;
   
   // select implementation variant for wavefront allocator
   // (note: only valid for VC_ALLOCATOR_TYPE_WF_BASE+x
   localparam wf_allocator_type = vc_allocator_type-`VC_ALLOCATOR_TYPE_WF_BASE;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // request VC allocation for given port (for each input VC)
   input [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   
   // allowable VCs for VC allocation (for each input VC)
   input [0:num_ports*num_vcs*num_vcs-1] vc_req_ip_ivc_ovc;
   
   // output VC is eligible for allocation (i.e., not currently allocated)
   input [0:num_ports*num_vcs-1] elig_op_ovc;
   
   // granted output VC (to inpt controller)
   output [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   wire [0:num_ports*num_vcs*num_vcs-1] vc_gnt_ip_ivc_ovc;
   
   // output VC was granted (to output controller)
   output [0:num_ports*num_vcs-1] vc_gnt_op_ovc;
   wire [0:num_ports*num_vcs-1] 	vc_gnt_op_ovc;
   
   generate
      
      case(vc_allocator_type)
	`VC_ALLOCATOR_TYPE_SEP_IF:
	  begin
	     vc_alloc_core_sep_if
	       #(.num_traffic_classes(num_traffic_classes),
		 .num_routing_classes(num_routing_classes),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .reset_type(reset_type))
	     core_sep_if
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	  end
	`VC_ALLOCATOR_TYPE_SEP_OF:
	  begin
	     vc_alloc_core_sep_of
	       #(.num_traffic_classes(num_traffic_classes),
		 .num_routing_classes(num_routing_classes),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .arbiter_type(arbiter_type),
		 .reset_type(reset_type))
	     core_sep_of
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	  end
      endcase
      
      if(vc_allocator_type >= `VC_ALLOCATOR_TYPE_WF_BASE)
	begin
	   vc_alloc_core_wf
	       #(.num_traffic_classes(num_traffic_classes),
		 .num_routing_classes(num_routing_classes),
		 .num_vcs_per_class(num_vcs_per_class),
		 .num_ports(num_ports),
		 .wf_allocator_type(wf_allocator_type),
		 .reset_type(reset_type))
	     core_wf
	       (.clk(clk),
		.reset(reset),
		.vc_req_ip_ivc_op(vc_req_ip_ivc_op),
		.vc_req_ip_ivc_ovc(vc_req_ip_ivc_ovc),
		.elig_op_ovc(elig_op_ovc),
		.vc_gnt_ip_ivc_ovc(vc_gnt_ip_ivc_ovc),
		.vc_gnt_op_ovc(vc_gnt_op_ovc));
	end
      
   endgenerate
   
endmodule
