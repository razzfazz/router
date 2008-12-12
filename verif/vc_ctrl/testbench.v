module testbench();
   
   parameter Tclk = 2;
   parameter runtime = 1000;
   parameter rate_out = 50;
   parameter max_length = 8;
   parameter max_delay = 2;
   parameter initial_seed = 0;
   
`include "config.v"
`include "globals.v"
   
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   parameter architecture_vca = 0;
   parameter architecture_swa = 0;
   parameter architecture_arb = 0;
   localparam [0:addr_width-1] dest_address = address+num_nodes_per_router-1;
   localparam count_width = clogb(num_buffers+1);
   
   
   reg clk;
   reg reset;
   reg drain;
   
   wire ipc_ovcc0_cred_valid_s, ipc_ovcc0_cred_valid_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   ipc_ovcc0_cred_validq
     (.clk(clk),
      .reset(reset),
      .d(ipc_ovcc0_cred_valid_s),
      .q(ipc_ovcc0_cred_valid_q));

   wire [0:vc_idx_width-1] ipc_ovcc0_cred_ivc_s, ipc_ovcc0_cred_ivc_q;
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   ipc_ovcc0_cred_ivcq
     (.clk(clk),
      .reset(reset),
      .d(ipc_ovcc0_cred_ivc_s),
      .q(ipc_ovcc0_cred_ivc_q));
   
   wire [0:num_vcs-1] 	   ipc_ovcc0_cred_ivc_1hot;
   
   decoder
     #(.num_ports(num_vcs))
   ipc_ovcc0_cred_ivc_dec
     (.data_in(ipc_ovcc0_cred_ivc_q),
      .data_out(ipc_ovcc0_cred_ivc_1hot));
   
   wire [0:num_vcs-1] 	   ovcc0_ipc_valid_ivc;
   wire [0:num_vcs*data_width-1] ovcc0_ipc_data_ivc;
   wire [0:num_vcs-1] 		 ovcc0_ipc_head_ivc;
   wire [0:num_vcs-1] 		 ovcc0_ipc_tail_ivc;
   wire [0:num_vcs-1] 		 req_ivc;
   wire [0:num_vcs-1] 		 gnt_ivc;
   wire 			 update_arb;
   assign update_arb = |req_ivc;
   arbiter
     #(.num_ports(num_vcs),
       .reset_type(reset_type),
       .architecture(architecture_arb))
   ivc_arb
     (.clk(clk),
      .reset(reset),
      .update(update_arb),
      .req(req_ivc),
      .gnt(gnt_ivc));
   
   generate
      genvar ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs

	   wire cred_valid;
	   assign cred_valid = ipc_ovcc0_cred_ivc_1hot[ivc] &
			       ipc_ovcc0_cred_valid_q;
	   
	   wire [0:data_width-1] data;
	   wire 		 head;
	   wire 		 tail;
	   packet_source
	     #(.initial_seed(initial_seed + ivc),
	       .max_length(max_length),
	       .max_delay(max_delay),
	       .reset_type(reset_type),
	       .address(dest_address))
	   psrc
	     (.clk(clk),
	      .reset(reset | |ivc),// FIXME
	      .valid(req_ivc[ivc]),
	      .data(data),
	      .head(head),
	      .tail(tail),
	      .cred_valid(cred_valid & ~drain));

	   always @(negedge clk)
	     begin
		if(gnt_ivc[ivc])
		  $display($time, " ivc%0d OUT: %x.", ivc, data);
	     end

	   assign ovcc0_ipc_data_ivc[ivc*data_width:(ivc+1)*data_width-1]
		    = data;
	   assign ovcc0_ipc_head_ivc[ivc] = head;
	   assign ovcc0_ipc_tail_ivc[ivc] = tail;
	   
	end
   endgenerate
   
   assign ovcc0_ipc_valid_ivc = gnt_ivc;

   wire 	ovcc0_ipc_valid_s;
   assign ovcc0_ipc_valid_s = |ovcc0_ipc_valid_ivc;

   wire 	ovcc0_ipc_valid_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   ovcc0_ipc_validq
     (.clk(clk),
      .reset(reset),
      .d(ovcc0_ipc_valid_s),
      .q(ovcc0_ipc_valid_q));
   

   wire [0:data_width-1] ovcc0_ipc_data_s;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(data_width))
   ovcc0_ipc_data_sel
     (.select(ovcc0_ipc_valid_ivc),
      .data_in(ovcc0_ipc_data_ivc),
      .data_out(ovcc0_ipc_data_s));

   wire [0:data_width-1] ovcc0_ipc_data_q;
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   ovcc0_ipc_dataq
     (.clk(clk),
      .reset(reset),
      .d(ovcc0_ipc_data_s),
      .q(ovcc0_ipc_data_q));

	     
   wire [0:vc_idx_width-1] ovcc0_ipc_ivc_s;
   encoder
     #(.num_ports(num_vcs))
   ovcc0_ipc_ivc_enc
     (.data_in(ovcc0_ipc_valid_ivc),
      .data_out(ovcc0_ipc_ivc_s));

   wire [0:vc_idx_width-1] ovcc0_ipc_ivc_q;
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   ovcc0_ipc_ivcq
     (.clk(clk),
      .reset(reset),
      .d(ovcc0_ipc_ivc_s),
      .q(ovcc0_ipc_ivc_q));

   
   wire ovcc0_ipc_head_s;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   ovcc0_ipc_head_sel
     (.select(ovcc0_ipc_valid_ivc),
      .data_in(ovcc0_ipc_head_ivc),
      .data_out(ovcc0_ipc_head_s));

   wire ovcc0_ipc_head_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   ovcc0_ipc_headq
     (.clk(clk),
      .reset(reset),
      .d(ovcc0_ipc_head_s),
      .q(ovcc0_ipc_head_q));

   
   wire ovcc0_ipc_tail_s;
   select_1ofn
     #(.num_ports(num_vcs),
       .width(1))
   ovcc0_ipc_tail_sel
     (.select(ovcc0_ipc_valid_ivc),
      .data_in(ovcc0_ipc_tail_ivc),
      .data_out(ovcc0_ipc_tail_s));

   wire ovcc0_ipc_tail_q;
   dff
     #(.width(1),
       .reset_type(reset_type))
   ovcc0_ipc_tailq
     (.clk(clk),
      .reset(reset),
      .d(ovcc0_ipc_tail_s),
      .q(ovcc0_ipc_tail_q));

   
   wire ipc_ovcc1_valid;
   wire [0:data_width-1] ipc_ovcc1_data;
   wire [0:vc_idx_width-1] ipc_ovcc1_ovc;
   wire 		   ipc_ovcc1_head;
   wire 		   ipc_ovcc1_tail;
   
   wire [0:num_vcs*num_ports-1] vc_req_ivc_op;
   wire [0:num_vcs*num_vcs-1] 	vc_req_ivc_ovc;
   wire [0:num_vcs-1] 		vc_gnt_ivc;
   wire [0:num_vcs*num_vcs-1] 	vc_gnt_ivc_ovc;
   
   wire [0:num_vcs*num_ports-1] sw_req_ivc_op;
   wire [0:num_vcs*num_ports-1] sw_req_nonspec_ivc_op;
   wire [0:num_vcs*num_vcs-1] 	sw_req_ivc_ovc;
   wire [0:num_vcs-1] 		sw_gnt_ivc;
   
   ip_ctrl
     #(.reset_type(reset_type),
       .address(address))
   ipc
     (.clk(clk),
      .reset(reset),
      .valid_in(ovcc0_ipc_valid_q),
      .data_in(ovcc0_ipc_data_q),
      .vc_in(ovcc0_ipc_ivc_q),
      .head_in(ovcc0_ipc_head_q),
      .tail_in(ovcc0_ipc_tail_q),
      .vc_req_ivc_op(vc_req_ivc_op),
      .vc_req_ivc_ovc(vc_req_ivc_ovc),
      .vc_gnt_ivc(vc_gnt_ivc),
      .vc_gnt_ivc_ovc(vc_gnt_ivc_ovc),
      .sw_req_ivc_op(sw_req_ivc_op),
      .sw_req_nonspec_ivc_op(sw_req_nonspec_ivc_op),
      .sw_req_ivc_ovc(sw_req_ivc_ovc),
      .sw_gnt_ivc(sw_gnt_ivc),
      .valid_out(ipc_ovcc1_valid),
      .data_out(ipc_ovcc1_data),
      .vc_out(ipc_ovcc1_ovc),
      .head_out(ipc_ovcc1_head),
      .tail_out(ipc_ovcc1_tail),
      .cred_valid_out(ipc_ovcc0_cred_valid_s),
      .cred_vc_out(ipc_ovcc0_cred_ivc_s));

  
   wire [0:num_ports*num_vcs*num_ports-1] vc_req_ip_ivc_op;
   assign vc_req_ip_ivc_op
     = {vc_req_ivc_op, {(num_ports-1)*num_vcs*num_ports{1'b0}}};
   
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_req_ip_ivc_ovc;
   assign vc_req_ip_ivc_ovc
     = {vc_req_ivc_ovc, {(num_ports-1)*num_vcs*num_vcs{1'b0}}};

   wire [0:num_vcs-1] 			  elig_ovc;
   wire [0:num_ports*num_vcs-1] 	  elig_op_ovc;
   assign elig_op_ovc = {{(num_ports-1)*num_vcs{1'b0}}, elig_ovc};
   
   wire [0:num_ports*num_vcs-1] 	  vc_gnt_ip_ivc;
   assign vc_gnt_ivc = vc_gnt_ip_ivc[0:num_vcs-1];
   
   wire [0:num_ports*num_vcs*num_vcs-1]   vc_gnt_ip_ivc_ovc;
   assign vc_gnt_ivc_ovc = vc_gnt_ip_ivc_ovc[0:num_vcs*num_vcs-1];
   
   wire [0:num_ports*num_vcs-1] 	  vc_gnt_op_ovc;
   wire [0:num_vcs-1] 			  vc_gnt_ovc;
   assign vc_gnt_ovc = vc_gnt_op_ovc[(num_ports-1)*num_vcs:num_ports*num_vcs-1];
   
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


   wire [0:num_ports*num_vcs*num_ports-1] sw_req_ip_ivc_op;
   assign sw_req_ip_ivc_op
     = {sw_req_ivc_op, {(num_ports-1)*num_vcs*num_ports{1'b0}}};

   wire [0:num_ports*num_vcs*num_vcs-1]   sw_req_ip_ivc_ovc;
   assign sw_req_ip_ivc_ovc
     = {sw_req_ivc_ovc, {(num_ports-1)*num_vcs*num_vcs{1'b0}}};
   
   wire [0:num_vcs-1] 			  cred_ovc;
   wire [0:num_ports*num_vcs-1] 	  cred_op_ovc;
   assign cred_op_ovc = {{(num_ports-1)*num_vcs{1'b0}}, cred_ovc};

   wire [0:num_ports*num_vcs-1] sw_gnt_ip_ivc;
   assign sw_gnt_ivc = sw_gnt_ip_ivc[0:num_vcs-1];

   wire [0:num_ports*num_ports-1] sw_gnt_ip_op_s;
   
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
      .gnt_ip_op(sw_gnt_ip_op_s));
   

   wire [0:num_ports*num_ports-1]   sw_gnt_ip_op_q;
   dff
     #(.width(num_ports*num_ports),
       .reset_type(reset_type))
   sw_gnt_ip_opq
     (.clk(clk),
      .reset(reset),
      .d(sw_gnt_ip_op_s),
      .q(sw_gnt_ip_op_q));
   
   
   wire [0:num_vcs-1] 		    empty_ovc;
   
   wire [0:num_vcs-1] 		    ipc_ovcc1_ovc_1hot;
   decoder
     #(.num_ports(num_vcs))
   ipc_ovcc1_ovc_dec
     (.data_in(ipc_ovcc1_ovc),
      .data_out(ipc_ovcc1_ovc_1hot));

   generate
      genvar 			ovc;
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs

	   integer seed = initial_seed + num_vcs + ovc;
	   
	   wire [0:data_width-1] data;
	   assign data = ipc_ovcc1_data;
	   
	   wire 		 head;
	   assign head = ipc_ovcc1_head;
	   
	   wire 		 tail;
	   assign tail = ipc_ovcc1_tail;
	   
	   wire 		 push;
	   assign push = ipc_ovcc1_valid & ipc_ovcc1_ovc_1hot[ovc];
	   
	   
	   reg 			 flag;
	   always @(posedge clk)
	     begin
		flag <= ($dist_uniform(seed, 0, 99) < rate_out);
	     end
	   
	   
	   always @(negedge clk)
	     begin
		if(push)
		  $display($time, " ovc%0d IN:  %x.", ovc, data);
	     end
	   
	   
	   wire pop;
	   
	   wire [0:count_width-1] count_s, count_q;
	   assign count_s = (count_q + push) - pop;
	   
	   dff
	     #(.width(clogb(num_buffers+1)),
	       .reset_type(reset_type))
	   countq
	     (.clk(clk),
	      .reset(reset),
	      .d(count_s),
	      .q(count_q));
	   
	   
	   wire 		  empty;
	   assign empty = ~|count_q;
	   
	   assign empty_ovc[ovc] = empty;
	   
	   assign pop = ~empty & flag;
	   
	   wire 		  alloc;
	   assign alloc = vc_gnt_ovc[ovc];
	   
	   wire 		  free;
	   assign free = push & tail;
	   
	   wire 		  elig, cred;
	   
	   ovc_ctrl
	     #(.reset_type(reset_type))
	   ovcc_out
	     (.clk(clk),
	      .reset(reset),
	      .push(push),
	      .pop(pop),
	      .alloc(alloc),
	      .free(free),
	      .elig(elig),
	      .cred(cred));
	   
	   assign elig_ovc[ovc] = elig;
	   assign cred_ovc[ovc] = cred;
	   
	end
   endgenerate
   
   
   always
   begin
      clk <= 1'b1;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end

   initial
   begin
      reset = 1'b1;
      drain = 1'b0;

      #(Tclk);

      reset = 1'b0;

      #(runtime*Tclk);

      drain = 1'b1;

      while(~&empty_ovc | ipc_ovcc1_valid)
	#(Tclk);
      
      $finish;
   end
      
endmodule
