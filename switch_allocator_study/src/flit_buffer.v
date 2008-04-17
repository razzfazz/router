module flit_buffer
  #(parameter data_width = 64,
    parameter num_vcs = 4,
    parameter num_buffers = 8,

    // see dff.v for supported values
    parameter reset_type = 1,
    
    parameter gate_clocks = 1)
   (clk, reset, push, push_vc, data_in, pop, pop_vc, data_out, vc_full,
    vc_empty, errors);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   localparam buff_addr_width = clogb(num_buffers);
   
   input                        clk;
   input                        reset;
   input                        push;
   input [0:vc_width-1]         push_vc;
   input [0:data_width-1]       data_in;
   input                        pop;
   input [0:vc_width-1]         pop_vc;
   output wire [0:data_width-1] data_out;
   output wire [0:num_vcs-1]    vc_full;
   output wire [0:num_vcs-1]    vc_empty;
   output wire [0:num_vcs-1] 	errors;
   
   wire [0:num_vcs*buff_addr_width-1] read_address_vc;
   wire [0:num_vcs*buff_addr_width-1] write_address_vc;

   wire [0:num_vcs-1] 		      pop_vc_1hot;
   wire [0:num_vcs-1] 		      push_vc_1hot;
   
   wire 			      clk_addr;
   wire 			      clk_rf;

   generate

      if(gate_clocks == 1)
	begin
	   wire act;
	   assign act = push | pop;
	   clkgate
	     (.clk(clk),
	      .act(act),
	      .clk_gated(clk_addr));
	   assign clk_rf = clk_addr;
	end
      else
	begin
	   assign clk_addr = clk;
	   assign clk_rf = clk;
	end
      
      genvar 			   ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   assign pop_vc_1hot[ivc] = pop && (pop_vc == ivc);
	   
	   wire [0:buff_addr_width-1] read_address_q;
	   wire [0:buff_addr_width-1] read_address_next;
	   if(2 ** clogb(num_buffers) == num_buffers)
	     begin
		// in this case, we have natural wraparound
		assign read_address_next = read_address_q + 1'b1;
	     end
	   else
	     begin
		// here we need explicit wraparound
		assign read_address_next
		  = (read_address_q == num_buffers - 1) ?
		    {buff_addr_width{1'b0}} :
		    (read_address_q + 1'b1);
	     end
	   
	   wire [0:buff_addr_width-1] read_address_s;
	   assign read_address_s
	     = pop_vc_1hot[ivc] ? read_address_next : read_address_q;
	   
	   assign read_address_vc[ivc*buff_addr_width:
				  (ivc+1)*buff_addr_width-1]
		    = read_address_q;
	   
	   assign push_vc_1hot[ivc] = push && (push_vc == ivc);
	   
	   wire [0:buff_addr_width-1] write_address_q;
	   wire [0:buff_addr_width-1] write_address_next;
	   if(2 ** clogb(num_buffers) == num_buffers)
	     begin
		// in this case, we have natural wraparound
		assign write_address_next = write_address_q + 1'b1;
	     end
	   else
	     begin
		// here we need explicit wraparound
		assign write_address_next
		  = (write_address_q == (num_buffers - 1)) ?
		    {buff_addr_width{1'b0}} :
		    (write_address_q + 1'b1);
	     end
	   
	   wire [0:buff_addr_width-1] write_address_s;
	   assign write_address_s
	     = push_vc_1hot[ivc] ? write_address_next : write_address_q;

	   assign write_address_vc[ivc*buff_addr_width:
				   (ivc+1)*buff_addr_width-1]
		    = write_address_q;
	   
	   wire 		   almost_empty;
	   assign almost_empty = (read_address_next == write_address_q);
	   
	   wire 		   empty_s, empty_q;
	   assign empty_s
	     = (empty_q | (almost_empty & pop_vc_1hot[ivc])) &
	       ~push_vc_1hot[ivc];
	   
	   assign vc_empty[ivc] = empty_q;
	   
	   wire 		   almost_full;
	   assign almost_full = (write_address_next == read_address_q);
	   
	   wire 		   full_s, full_q;
	   assign full_s
	     = (full_q | (almost_full & push_vc_1hot[ivc])) &
	       ~pop_vc_1hot[ivc];
	   
	   assign vc_full[ivc] = full_q;

	   assign errors[ivc] = (full_q && push_vc_1hot[ivc]) ||
				(empty_q && pop_vc_1hot[ivc]);
	   
	   dff
	     #(.width(buff_addr_width),
	       .reset_type(reset_type))
	   read_addressq
	     (.clk(clk_addr),
	      .reset(reset),
	      .d(read_address_s),
	      .q(read_address_q));
		
	   dff
	     #(.width(buff_addr_width),
	       .reset_type(reset_type))
	   write_addressq
	     (.clk(clk_addr),
	      .reset(reset),
	      .d(write_address_s),
	      .q(write_address_q));
	   
	   dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .reset_value(1'b1))
	   emptyq
	     (.clk(clk_addr),
	      .reset(reset),
	      .d(empty_s),
	      .q(empty_q));
	   
	   dff
	     #(.width(1),
	       .reset_type(reset_type))
	   fullq
	     (.clk(clk_addr),
	      .reset(reset),
	      .d(full_s),
	      .q(full_q));
		
	end
      
   endgenerate

   wire [0:vc_width+buff_addr_width-1] read_address;
   assign read_address[0:vc_width-1] = pop_vc;
   select_1ofn
     #(.width(buff_addr_width),
       .num_ports(num_vcs))
   read_address_vc_or
     (.select(pop_vc_1hot),
      .data_in(read_address_vc),
      .data_out(read_address[vc_width:vc_width+buff_addr_width-1]));

   wire [0:vc_width+buff_addr_width-1] write_address;
   assign write_address[0:vc_width-1] = push_vc;
   select_1ofn
     #(.width(buff_addr_width),
       .num_ports(num_vcs))
   write_address_vc_or
     (.select(push_vc_1hot),
      .data_in(write_address_vc),
      .data_out(write_address[vc_width:vc_width+buff_addr_width-1]));

   regfile
     #(.width(data_width),
       .depth(num_vcs*num_buffers),
       .sync_rf_output(0))
   flit_rf
     (.clk(clk),
      .write_enable(push),
      .write_address(write_address),
      .write_data(data_in),
      .read_address(read_address),
      .read_data(data_out));
   
endmodule
