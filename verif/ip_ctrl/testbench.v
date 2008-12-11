module testbench
  #(parameter Tclk = 4,
    parameter sim_cycles = 1000,
    parameter initial_seed = 0,
    parameter flit_generate_rate = 80,
    parameter flit_sink_rate = 80,
    parameter num_buffers = 8,
    parameter reset_type = 1)
   ();

`include "functions.v"

   localparam buff_addr_width = clogb(num_buffers);
   
   reg clk;
   reg reset;
   wire push;
   wire push_head;
   wire push_tail;
   wire pop;
   wire pop_valid;
   wire pop_head;
   wire pop_tail;
   wire [0:buff_addr_width-1] write_address;
   wire [0:buff_addr_width-1] read_address;
   
   ivcc
     #(.num_buffers(num_buffers),
       .reset_type(reset_type))
   ivc_ctrl
     (.clk(clk),
      .reset(reset),
      .push(push),
      .push_head(push_head),
      .push_tail(push_tail),
      .pop(pop),
      .pop_valid(pop_valid),
      .pop_head(pop_head),
      .pop_tail(pop_tail),
      .read_address(read_address),
      .write_address(write_address));

   flit_source
     #(.initial_seed(initial_seed),
       .flit_rate(flit_generate_rate),
       .data_width(data_width),
       .num_vcs(num_vcs))
   source
     (.clk(clk),
      .reset(reset),
      .ready(~vc_full),
      .valid(push),
      .vc(push_vc),
      .data(data_in));

   flit_sink
     #(.initial_seed(initial_seed),
       .flit_rate(flit_sink_rate),
       .num_vcs(num_vcs))
   sink
     (.clk(clk),
      .reset(reset),
      .valid(~vc_empty),
      .ready(pop),
      .vc(pop_vc));

   generate

      genvar 		 vc;
      for(vc = 0; vc < num_vcs; vc = vc + 1)
	begin:vcs
	   
	   wire capture_in;
	   assign capture_in = push && (push_vc == vc);
	   wire [0:data_width-1] in_data_s, in_data_q;
	   assign in_data_s = capture_in ? data_in : in_data_q;
	   dff
	     #(.width(data_width),
	       .reset_type(1))
	   in_dataq
	     (.clk(clk),
	      .reset(reset),
	      .d(in_data_s),
	      .q(in_data_q));
	   
	   wire 		 capture_out;
	   assign capture_out = pop && (pop_vc == vc);
	   wire [0:data_width-1] out_data_s, out_data_q;
	   assign out_data_s = capture_out ? data_out : out_data_q;
	   dff
	     #(.width(data_width),
	       .reset_type(1))
	   out_dataq
	     (.clk(clk),
	      .reset(reset),
	      .d(out_data_s),
	      .q(out_data_q));
	   
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
      #(2*Tclk);
      reset = 1'b0;
      #(sim_cycles*Tclk);
      $finish;
      
   end
   
endmodule
