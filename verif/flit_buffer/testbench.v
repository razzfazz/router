module testbench
  #(parameter Tclk = 4,
    parameter sim_cycles = 1000,
    parameter initial_seed = 0,
    parameter flit_generate_rate = 80,
    parameter flit_sink_rate = 80,
    parameter flit_width = 64,
    parameter num_vcs = 4,
    parameter num_buffers = 8,
    parameter reset_type = 1,
    parameter hold_type = 1)
   ();

`include "functions.v"

   localparam vc_width = clogb(num_vcs);
   
   reg clk;
   reg reset;
   wire push;
   wire [0:vc_width-1] push_vc;
   wire [0:flit_width-1] flit_data_in;
   wire 		 pop;
   wire [0:vc_width-1] 	 pop_vc;
   wire [0:flit_width-1] flit_data_out;
   wire [0:num_vcs-1] 	 vc_full;
   wire [0:num_vcs-1] 	 vc_empty;
   
   flit_buffer
     #(.flit_width(flit_width),
       .num_vcs(num_vcs),
       .num_buffers(num_buffers),
       .reset_type(reset_type),
       .hold_type(hold_type))
   fbf
     (.clk(clk),
      .reset(reset),
      .push(push),
      .push_vc(push_vc),
      .flit_data_in(flit_data_in),
      .pop(pop),
      .pop_vc(pop_vc),
      .flit_data_out(flit_data_out),
      .vc_full(vc_full),
      .vc_empty(vc_empty));

   wire [0:num_vcs-1] 	 cred;
   port_state
     #(.num_vcs(num_vcs),
       .num_buffers(num_buffers),
       .reset_type(reset_type),
       .hold_type(hold_type))
   pst
     (.clk(clk),
      .reset(reset),
      .push(push),
      .push_vc(push_vc),
      .pop(pop),
      .pop_vc(pop_vc),
      .cred(cred));
   
   flit_source
     #(.initial_seed(initial_seed),
       .flit_rate(flit_generate_rate),
       .flit_width(flit_width),
       .num_vcs(num_vcs))
   source
     (.clk(clk),
      .reset(reset),
      .ready(~vc_full),
      .valid(push),
      .vc(push_vc),
      .data(flit_data_in));

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
	   wire [0:flit_width-1] in_data_s, in_data_q;
	   assign in_data_s = capture_in ? flit_data_in : in_data_q;
	   dff
	     #(.width(flit_width),
	       .reset_type(1))
	   in_dataq
	     (.clk(clk),
	      .reset(reset),
	      .d(in_data_s),
	      .q(in_data_q));
	   
	   wire 		 capture_out;
	   assign capture_out = pop && (pop_vc == vc);
	   wire [0:flit_width-1] out_data_s, out_data_q;
	   assign out_data_s = capture_out ? flit_data_out : out_data_q;
	   dff
	     #(.width(flit_width),
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
