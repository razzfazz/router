module flit_buffer
  #(parameter data_width = 64,
    parameter num_vcs = 4,
    parameter num_buffers = 8,

    // see dff.v for supported values
    parameter reset_type = 1,
    parameter hold_type = 1)
   (clk, reset, push, push_vc, data_in, pop, pop_vc, data_out, vc_full,
    vc_empty, errors);

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   localparam buffer_width = clogb(num_buffers);
   
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
   
   wire [0:num_vcs*buffer_width-1] read_address_vc;
   wire [0:num_vcs*buffer_width-1] write_address_vc;
   
   generate
      
      genvar 			   ivc;
      for(ivc = 0; ivc < num_vcs; ivc = ivc + 1)
	begin:ivcs
	   
	   wire pop_this_vc;
	   assign pop_this_vc = pop && (pop_vc == ivc);

	   wire [0:buffer_width-1] read_address_q;
	   wire [0:buffer_width-1] read_address_next;
	   assign read_address_next
	     = (read_address_q == num_buffers - 1) ?
	       {buffer_width{1'b0}} :
	       read_address_q + {{buffer_width-1{1'b0}}, 1'b1};
	   
	   wire [0:buffer_width-1] read_address_s;
	   
	   if(hold_type == 0)
	     assign read_address_s
	       = pop_this_vc ? read_address_next : read_address_q;
	   else if((hold_type == 1) || (hold_type == 2))
	     assign read_address_s = read_address_next;
	   
	   assign read_address_vc[ivc*buffer_width:(ivc+1)*buffer_width-1]
		    = read_address_q & {buffer_width{pop_this_vc}};
	   
	   wire 		   push_this_vc;
	   assign push_this_vc = push && (push_vc == ivc);
	   
	   wire [0:buffer_width-1] write_address_q;
	   wire [0:buffer_width-1] write_address_next;
	   assign write_address_next
	     = (write_address_q == (num_buffers - 1)) ?
	       {buffer_width{1'b0}} :
	       write_address_q + {{buffer_width-1{1'b0}}, 1'b1};
	   
	   wire [0:buffer_width-1] write_address_s;
	   
	   if(hold_type == 0)
	     assign write_address_s
	       = push_this_vc ? write_address_next : write_address_q;
	   else if((hold_type == 1) || (hold_type == 2))
	     assign write_address_s = write_address_next;

	   assign write_address_vc[ivc*buffer_width:(ivc+1)*buffer_width-1]
		    = write_address_q & {buffer_width{push_this_vc}};
	   
	   wire 		   almost_empty;
	   assign almost_empty = (read_address_next == write_address_q);
	   
	   wire 		   empty_s, empty_q;
	   assign empty_s
	     = (empty_q | (almost_empty & pop_this_vc)) & ~push_this_vc;
	   
	   assign vc_empty[ivc] = empty_q;
	   
	   wire 		   almost_full;
	   assign almost_full = (write_address_next == read_address_q);
	   
	   wire 		   full_s, full_q;
	   assign full_s
	     = (full_q | (almost_full & push_this_vc)) & ~pop_this_vc;
	   
	   assign vc_full[ivc] = full_q;

	   assign errors[ivc] = (full_q && push_this_vc) ||
				(empty_q && pop_this_vc);
	   
	   dff
	     #(.width(buffer_width),
	       .reset_type(reset_type),
	       .hold_type(hold_type))
	   read_addressq
	     (.clk(clk),
	      .reset(reset),
	      .enable(pop_this_vc),
	      .d(read_address_s),
	      .q(read_address_q));
		
	   dff
	     #(.width(buffer_width),
	       .reset_type(reset_type),
	       .hold_type(hold_type))
	   write_addressq
	     (.clk(clk),
	      .reset(reset),
	      .enable(push_this_vc),
	      .d(write_address_s),
	      .q(write_address_q));
	   
	   dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .reset_value(1'b1),
	       .hold_type(hold_type))
	   emptyq
	     (.clk(clk),
	      .reset(reset),
	      .enable(pop_this_vc | push_this_vc),
	      .d(empty_s),
	      .q(empty_q));
	   
	   dff
	     #(.width(1),
	       .reset_type(reset_type),
	       .hold_type(hold_type))
	   fullq
	     (.clk(clk),
	      .reset(reset),
	      .enable(pop_this_vc | push_this_vc),
	      .d(full_s),
	      .q(full_q));
		
	end
      
   endgenerate

   wire [0:vc_width+buffer_width-1] read_address;
   assign read_address[0:vc_width-1] = pop_vc;
   or_nto1
     #(.width(buffer_width),
       .num_ports(num_vcs))
   read_address_vc_or
     (.data_in(read_address_vc),
      .data_out(read_address[vc_width:vc_width+buffer_width-1]));

   wire [0:vc_width+buffer_width-1] write_address;
   assign write_address[0:vc_width-1] = push_vc;
   or_nto1
     #(.width(buffer_width),
       .num_ports(num_vcs))
   write_address_vc_or
     (.data_in(write_address_vc),
      .data_out(write_address[vc_width:vc_width+buffer_width-1]));

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
