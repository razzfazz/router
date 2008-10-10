module packet_source
  (clk, reset, flit_valid, flit_head, flit_tail, flit_vc, flit_data, cred_valid,
   cred_vc, done, error);
   
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
   
   parameter packet_count = 1000;
   parameter packet_length = 1;
   parameter packet_rate = 0;
   parameter initial_seed = 0;
   parameter adaptive_rate = 0;
   parameter packet_count_width = 32;
   parameter num_flit_buffers = 8;
   parameter num_header_buffers = 8;
   parameter num_vcs = 4;
   parameter data_width = 64;
   parameter addr_width = 6;
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   parameter walk_addresses = 0;
   parameter reset_type = `RESET_TYPE_ASYNC;
   localparam vc_idx_width = clogb(num_vcs);
   localparam flit_buffer_idx_width = clogb(num_flit_buffers);
   localparam flit_count_width = clogb(packet_length);
   localparam cred_count_width = clogb(num_flit_buffers+1);
   
   
   input clk;
   input reset;
   
   output flit_valid;
   output flit_head;
   output flit_tail;
   output [0:vc_idx_width-1] flit_vc;
   output [0:data_width-1] flit_data;
   
   input cred_valid;
   input [0:vc_idx_width-1] cred_vc;
   
   output done;
   
   output error;
   
   wire flit_valid;
   wire flit_head;
   wire flit_tail;
   wire [0:vc_idx_width-1] flit_vc;
   wire [0:data_width-1]   flit_data;
   
   wire 		   done;
   
   wire 		   error;
   
   
   integer 		   seed = initial_seed;
   
   integer 		   i;
   
   reg 			   new_packet;   
   reg [0:data_width-1]    random_data;
   reg [0:vc_idx_width-1]  random_vc;
   reg [0:addr_width-1]    random_next_addr;
   reg [0:addr_width-1]    random_final_addr;
   always @(posedge clk, posedge reset)
     begin
	new_packet
	  = ($dist_uniform(seed, 0, 99) < (packet_rate / packet_length)) &&
	    !reset;
	for(i = 0; i < data_width; i = i + 1)
	  random_data[i] = $dist_uniform(seed, 0, 1);
	random_vc = $dist_uniform(seed, 0, num_vcs-1);
	if(walk_addresses)
	  random_next_addr
	    = reset ?
	      0 :
	      (random_next_addr + 1 + (random_next_addr + 1 == address));
	else
	  begin
	     random_next_addr = {addr_width{1'b0}};
	     random_next_addr[0:addr_width-1]
	       = address[0:addr_width-1] +
		 $dist_uniform(seed, 1, 2**addr_width-1);
	  end
	random_final_addr = address + $dist_uniform(seed, 1, 2**addr_width-1);
     end
   
   wire waiting_packet_count_zero;
   
   wire packet_ready;
   assign packet_ready = new_packet & ~waiting_packet_count_zero;
   
   generate
      if(packet_count >= 0)
	begin
	   
	   wire [0:packet_count_width-1] waiting_packet_count_s,
					 waiting_packet_count_q;
	   assign waiting_packet_count_s
	     = waiting_packet_count_q - packet_ready;
	   dff
	     #(.width(packet_count_width),
	       .reset_type(reset_type),
	       .reset_value(packet_count))
	   waiting_packet_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(waiting_packet_count_s),
	      .q(waiting_packet_count_q));
	   
	   assign waiting_packet_count_zero = ~|waiting_packet_count_q;
	   
	end
      else
	begin
	   assign waiting_packet_count_zero = 1'b0;
	end
   endgenerate
   
   wire 			  packet_sent;
   
   wire [0:packet_count_width-1]  ready_packet_count_s, ready_packet_count_q;
   assign ready_packet_count_s
     = ready_packet_count_q - packet_sent + packet_ready;
   dff
     #(.width(packet_count_width),
       .reset_type(reset_type))
   ready_packet_countq
     (.clk(clk),
      .reset(reset),
      .d(ready_packet_count_s),
      .q(ready_packet_count_q));
   
   wire 			  ready_packet_count_zero;
   assign ready_packet_count_zero = ~|ready_packet_count_q;
   
   assign done = waiting_packet_count_zero & ready_packet_count_zero;
   
   wire 			  flit_count_max;
   wire 			  flit_count_zero;
   wire 			  flit_sent;
   
   wire [0:vc_idx_width-1] 	  vc_q;
   
   wire [0:num_vcs-1] 		  free_ovc;
   wire [0:num_vcs-1] 		  head_free_ovc;
   
   wire [0:num_vcs-1] 		  error_hct_ovc;
   wire [0:num_vcs*2-1] 	  error_cred_ovc;
   
   genvar 			  ovc;
   
   generate
      
      for(ovc = 0; ovc < num_vcs; ovc = ovc + 1)
	begin:ovcs
	   
	   wire credit;
	   assign credit = cred_valid && (cred_vc == ovc);
	   
	   wire debit;
	   assign debit = flit_sent && (vc_q == ovc);
	   
	   wire head_credit;
	   wire [0:cred_count_width-1] cred_count_s;
	   
	   if(num_header_buffers > 1)
	     begin
		
		wire [0:num_flit_buffers-1] push_mask;
		wire [0:num_flit_buffers-1] pop_mask;
		
		wire [0:num_flit_buffers-1] tail_queue_s, tail_queue_q;
		assign tail_queue_s
		  = (tail_queue_q & ~({num_flit_buffers{credit}} & pop_mask)) |
		    ({num_flit_buffers{debit & flit_tail}} & push_mask);
		dff
		  #(.width(num_flit_buffers),
		    .reset_type(reset_type))
		tail_queueq
		  (.clk(clk),
		   .reset(reset),
		   .d(tail_queue_s),
		   .q(tail_queue_q));
		
		wire [0:flit_buffer_idx_width-1] push_ptr, push_ptr_next;
		mod_ctr
		  #(.num_values(num_flit_buffers),
		    .reset_type(reset_type))
		push_ptr_ctr
		  (.clk(clk),
		   .reset(reset),
		   .incr(debit),
		   .value(push_ptr),
		   .next_value(push_ptr_next));
		
		decoder
		  #(.num_ports(num_flit_buffers))
		push_mask_dec
		  (.data_in(push_ptr),
		   .data_out(push_mask));
		
		wire [0:flit_buffer_idx_width-1] pop_ptr, pop_ptr_next;
		mod_ctr
		  #(.num_values(num_flit_buffers),
		    .reset_type(reset_type))
		pop_ptr_ctr
		  (.clk(clk),
		   .reset(reset),
		   .incr(credit),
		   .value(pop_ptr),
		   .next_value(pop_ptr_next));
		
		decoder
		  #(.num_ports(num_flit_buffers))
		pop_mask_dec
		  (.data_in(pop_ptr),
		   .data_out(pop_mask));
		
		assign head_credit = |(tail_queue_q & pop_mask) & credit;
		
	     end
	   else
	     begin

		// if we can only have one packet per buffer, we can accept the
		// next one once the buffer has been emptied
		assign head_credit = credit &&
				     (cred_count_s == num_flit_buffers);
		
	     end
	   
	   wire 			    head_debit;
	   assign head_debit = debit & flit_count_max;
	   
	   // track header credits using stock credit tracker module
	   wire 			    head_free;
	   wire 			    head_free_early;
	   wire 			    error_hct;
	   credit_tracker
	     #(.num_credits(num_header_buffers),
	       .checker_enable(1),
	       .checker_capture_mode(0),
	       .reset_type(reset_type))
	   hct
	     (.clk(clk),
	      .reset(reset),
	      .credit(head_credit),
	      .debit(head_debit),
	      .free(head_free),
	      .free_early(head_free_early),
	      .error(error_hct));

	   assign head_free_ovc[ovc] = head_free;
	   assign error_hct_ovc[ovc] = error_hct;
	   
	   wire [0:cred_count_width-1] cred_count_q;
	   assign cred_count_s = cred_count_q + credit - debit;
	   dff
	     #(.width(cred_count_width),
	       .reset_type(reset_type),
	       .reset_value(num_flit_buffers))
	   cred_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(cred_count_s),
	      .q(cred_count_q));
	   
	   assign free_ovc[ovc] = |cred_count_q;
	   
	   wire [0:1] 		       error_cred;
	   assign error_cred = {(cred_count_q == num_flit_buffers) && credit,
				(cred_count_q == 0) && debit};
	   
	   assign error_cred_ovc[ovc*2:(ovc+1)*2-1] = error_cred;
	   
	end
      
   endgenerate
   
   wire 			       free;
   mux_nto1
     #(.num_ports(num_vcs),
       .width(1))
   free_mux
     (.select(vc_q),
      .data_in(free_ovc),
      .data_out(free));

   wire 			       head_free;
   mux_nto1
     #(.num_ports(num_vcs),
       .width(1))
   head_free_mux
     (.select(vc_q),
      .data_in(head_free_ovc),
      .data_out(head_free));
   
   assign flit_sent
     = ~ready_packet_count_zero & free & (head_free | ~flit_count_max);
   
   assign packet_sent = flit_count_zero & flit_sent;
   
   generate
      
      if(packet_length > 1)
	begin
	   wire [0:flit_count_width-1] flit_count_s, flit_count_q;
	   assign flit_count_s = packet_sent ?
				 (packet_length - 1'b1) :
				 (flit_count_q - flit_sent);
	   dff
	     #(.width(flit_count_width),
	       .reset_type(reset_type),
	       .reset_value(packet_length - 1'b1))
	   flit_countq
	     (.clk(clk),
	      .reset(reset),
	      .d(flit_count_s),
	      .q(flit_count_q));
	   
	   assign flit_count_max = (flit_count_q == (packet_length - 1'b1));
	   assign flit_count_zero = ~|flit_count_q;
	end
      else
	begin
	   assign flit_count_max = 1'b1;
	   assign flit_count_zero = 1'b1;
	end
      
   endgenerate
   
   wire [0:vc_idx_width-1] 	  vc_s;
   assign vc_s = packet_sent ? random_vc : vc_q;
   dff
     #(.width(vc_idx_width),
       .reset_type(reset_type))
   vcq
     (.clk(clk),
      .reset(reset),
      .d(vc_s),
      .q(vc_q));
   
   wire [0:data_width-1] 	  data_s, data_q;
   assign data_s[0:addr_width-1]
	    = flit_sent ?
	      (packet_sent ?
	       random_next_addr :
	       random_data[0:addr_width-1]) :
	      data_q[0:addr_width-1];
   assign data_s[addr_width:2*addr_width-1]
	    = flit_sent ?
	      (packet_sent ?
	       random_final_addr :
	       random_data[addr_width:2*addr_width-1]) :
	      data_q[addr_width:2*addr_width-1];
   assign data_s[2*addr_width:data_width-1]
	    = flit_sent ?
	      random_data[2*addr_width:data_width-1] :
	      data_q[2*addr_width:data_width-1];
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   
   assign flit_valid = flit_sent;
   assign flit_head = flit_count_max;
   assign flit_tail = flit_count_zero;
   assign flit_vc = vc_q;
   assign flit_data = data_q;
   
   assign error = |error_hct_ovc | |error_cred_ovc;
   
endmodule
