module packet_source
  (clk, reset, valid, data, head, tail, cred_valid);
   
   parameter initial_seed = 0;
   parameter max_length = 8;
   parameter max_delay = 2;
   
`include "config.v"
`include "constants.v"
   
   parameter reset_type = reset_type_async;
   parameter [0:addr_width-1] address = {addr_width{1'b0}};
   localparam ctr_width = clogb(max(max_length, max_delay));
   
   input clk;
   input reset;
   output wire valid;
   output wire [0:data_width-1] data;
   output wire 			head;
   output wire 			tail;
   input cred_valid;
   
   integer 			seed = initial_seed;

   localparam [0:1] state_idle = 2'h0;
   localparam [0:1] state_head = 2'h1;
   localparam [0:1] state_body = 2'h2;

   reg [0:1] 			state_s;
   wire [0:1] 			state_q;
   reg [0:ctr_width-1] 		ctr_s;
   wire [0:ctr_width-1] 	ctr_q;
   reg [0:data_width-1] 	data_s;
   wire [0:data_width-1] 	data_q;
   reg 				valid_s;
   wire 			valid_q;
   reg 				head_s;
   wire 			head_q;
   reg 				tail_s;
   wire 			tail_q;
   wire 			elig;
   wire 			cred;
   integer 			i;

   always @(state_q, ctr_q, head_q, tail_q, data_q, elig, cred)
     begin
	case(state_q)
	  state_idle:
	    begin
	       if(~|ctr_q)
		 begin
		    if(elig & cred)
		      begin
			 state_s = state_head;
			 ctr_s = $dist_uniform(seed, 0, max_length-1);
			 valid_s = 1'b1;
			 head_s = 1'b1;
			 tail_s = ~|ctr_s;
			 data_s = set_route_info({data_width{1'b0}},
						 create_route_info(address,
								   address));
		      end
		    else
		      begin
			 state_s = state_q;
			 ctr_s = ctr_q;
			 valid_s = 1'b0;
			 head_s = head_q;
			 tail_s = tail_q;
			 data_s = data_q;
		      end
		 end
	       else
		 begin
		    state_s = state_q;
		    ctr_s = ctr_q - 1'b1;
		    valid_s = 1'b0;
		    head_s = head_q;
		    tail_s = tail_q;
		    data_s = data_q;
		 end
	    end
	  state_head:
	    begin
	       if(cred)
		 begin
		    if(~|ctr_q)
		      begin
			 state_s = state_idle;
			 ctr_s = $dist_uniform(seed, 0, max_delay-1);
			 valid_s = 1'b0;
			 head_s = 1'b0;//head_q;
			 tail_s = 1'b0;//tail_q;
			 data_s = {data_width{1'b0}};//data_q;
		      end
		    else
		      begin
			 state_s = state_body;
			 ctr_s = ctr_q - 1'b1;
			 valid_s = 1'b1;
			 head_s = 1'b0;
			 tail_s = ~|ctr_s;
			 for(i = 0; i < data_width; i = i + 1)
			   data_s[i] = $dist_uniform(seed, 0, 1);
		      end
		 end
	       else
		 begin
		    state_s = state_q;
		    ctr_s = ctr_q;
		    valid_s = 1'b0;
		    head_s = head_q;
		    tail_s = tail_q;
		    data_s = data_q;
		 end
	    end
	  state_body:
	    begin
	       if(cred)
		 begin
		    if(~|ctr_q)
		      begin
			 state_s = state_idle;
			 ctr_s = $dist_uniform(seed, 0, max_delay-1);
			 valid_s = 1'b0;
			 head_s = 1'b0;//head_q;
			 tail_s = 1'b0;//tail_q;
			 data_s = {data_width{1'b0}};//data_q;
		      end
		    else
		      begin
			 state_s = state_q;
			 ctr_s = ctr_q - 1'b1;
			 valid_s = 1'b1;
			 head_s = head_q;
			 tail_s = ~|ctr_s;
			 for(i = 0; i < data_width; i = i + 1)
			   data_s[i] = $dist_uniform(seed, 0, 1);
		      end
		 end
	       else
		 begin
		    state_s = state_q;
		    ctr_s = ctr_q;
		    valid_s = 1'b0;
		    head_s = head_q;
		    tail_s = tail_q;
		    data_s = data_q;
		 end
	    end
	  default:
	    begin
	       state_s = state_idle;
	       ctr_s = {ctr_width{1'b0}};
	       valid_s = 1'b0;
	       head_s = 1'b0;
	       tail_s = 1'b0;
	       data_s = {data_width{1'b0}};
	    end
	endcase
     end
   
   ovc_ctrl
     #(.reset_type(reset_type))
   ovcc_in
     (.clk(clk),
      .reset(reset),
      .push(valid_s),
      .pop(cred_valid),
      .alloc(valid_s & head_s),
      .free(valid_s & tail_s),
      .elig(elig),
      .cred(cred));
   
   dff
     #(.width(2),
       .reset_type(reset_type))
   stateq
     (.clk(clk),
      .reset(reset),
      .d(state_s),
      .q(state_q));

   dff
     #(.width(ctr_width),
       .reset_type(reset_type))
   ctrq
     (.clk(clk),
      .reset(reset),
      .d(ctr_s),
      .q(ctr_q));
   
   dff
     #(.width(1),
       .reset_type(reset_type))
   validq
     (.clk(clk),
      .reset(reset),
      .d(valid_s),
      .q(valid_q));
   
   assign valid = valid_q;
   
   dff
     #(.width(1),
       .reset_type(reset_type))
   headq
     (.clk(clk),
      .reset(reset),
      .d(head_s),
      .q(head_q));
   
   assign head = head_q;
   
   dff
     #(.width(1),
       .reset_type(reset_type))
   tailq
     (.clk(clk),
      .reset(reset),
      .d(tail_s),
      .q(tail_q));
   
   assign tail = tail_q;
   
   dff
     #(.width(data_width),
       .reset_type(reset_type))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   
   assign data = data_q;
   
endmodule
