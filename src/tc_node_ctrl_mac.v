// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list
of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this 
list of conditions and the following disclaimer in the documentation and/or 
other materials provided with the distribution.
Neither the name of the Stanford University nor the names of its contributors 
may be used to endorse or promote products derived from this software without 
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR 
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON 
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// network pseudo-node controller 
module tc_node_ctrl_mac
  (clk, reset, io_write, io_read, io_addr, io_write_data, io_read_data, io_done,
   cfg_req, cfg_write, cfg_addr, cfg_write_data, cfg_read_data, cfg_done);
   
`include "c_constants.v"
   
   // width of configuration bus addresses
   parameter cfg_addr_width = 16;
   
   // width of configuration bus datapath
   parameter cfg_data_width = 32;
   
   // number of bits in delay counter for acknowledgement (i.e., log2 of 
   // interval before acknowledgement is sent)
   parameter done_delay_width = 6;
   
   parameter reset_type = `RESET_TYPE_ASYNC;
   
   input clk;
   input reset;
   
   // write request indicator from chip controller
   input io_write;
   
   // read request indicator from chip controller
   input io_read;
   
   // register address
   input [0:cfg_addr_width-1] io_addr;
   
   // input data
   input [0:cfg_data_width-1] io_write_data;
   
   // result data to chip controller
   output [0:cfg_data_width-1] io_read_data;
   wire [0:cfg_data_width-1] io_read_data;
   
   // completion indicator to chip controller
   output io_done;
   wire io_done;
   
   // config register access pending
   output cfg_req;
   wire cfg_req;
   
   // config register access is write access
   output cfg_write;
   wire cfg_write;
   
   // select config register to access
   output [0:cfg_addr_width-1] cfg_addr;
   wire [0:cfg_addr_width-1] cfg_addr;
   
   // data to be written to selected config register for write accesses
   output [0:cfg_data_width-1] cfg_write_data;
   wire [0:cfg_data_width-1] cfg_write_data;
   
   // contents of selected config register for read accesses
   input [0:cfg_data_width-1] cfg_read_data;
   
   // config register access complete
   input cfg_done;
   
   wire 		     io_req;
   assign io_req = io_write | io_read;
   
   wire [0:2] 		     req_s, req_q;
   assign req_s = {io_req, req_q[0:1]};
   c_dff
     #(.width(3),
       .reset_type(reset_type))
   reqq
     (.clk(clk),
      .reset(reset),
      .d(req_s),
      .q(req_q));
   
   wire 		     req_active;
   assign req_active = req_q[1] | req_q[2];
   
   wire 		     req_rise;
   assign req_rise = req_q[1] & ~req_q[2];
   
   assign cfg_req = req_rise;
   
   wire 		     req_fall;
   assign req_fall = ~req_q[1] & req_q[2];
   
   wire 		     write_s, write_q;
   assign write_s = req_active ? 
		    (req_rise ? io_write : write_q) : 
		    write_q;
   c_dff
     #(.width(1),
       .reset_type(`RESET_TYPE_NONE /*reset_type*/))
   writeq
     (.clk(clk),
      .reset(reset),
      .d(write_s),
      .q(write_q));
   
   assign cfg_write = write_q;
   
   wire [0:cfg_addr_width-1] addr_s, addr_q;
   assign addr_s = req_active ? 
		   (req_rise ? io_addr : addr_q) : 
		   addr_q;
   c_dff
     #(.width(cfg_addr_width),
       .reset_type(`RESET_TYPE_NONE /*reset_type*/))
   addrq
     (.clk(clk),
      .reset(reset),
      .d(addr_s),
      .q(addr_q));
   
   assign cfg_addr = addr_q;
   
   wire 		     done_s, done_q;
   assign done_s = req_active ? cfg_done : done_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   doneq
     (.clk(clk),
      .reset(reset),
      .d(done_s),
      .q(done_q));
   
   wire [0:cfg_data_width-1] data_s, data_q;
   assign data_s = req_active ? 
		   (req_rise ? io_write_data : cfg_read_data) : 
		   data_q;
   c_dff
     #(.width(cfg_data_width),
       .reset_type(`RESET_TYPE_NONE /*reset_type*/))
   dataq
     (.clk(clk),
      .reset(reset),
      .d(data_s),
      .q(data_q));
   
   assign cfg_write_data = data_q;
   assign io_read_data = data_q;
   
   wire 		     done_pending_q;
   
   wire [0:done_delay_width-1] done_delay_s, done_delay_q;
   assign done_delay_s = req_active ? 
			 (done_q ? 
			  {done_delay_width{1'b1}} : 
			  (done_delay_q - done_pending_q)) : 
			 done_delay_q;
   c_dff
     #(.width(done_delay_width),
       .reset_type(`RESET_TYPE_NONE /*reset_type*/))
   done_delayq
     (.clk(clk),
      .reset(reset),
      .d(done_delay_s),
      .q(done_delay_q));
   
   wire 		       done_delay_elapsed;
   assign done_delay_elapsed = ~|done_delay_q;
   
   wire 		       done_pending_s;
   assign done_pending_s = req_active ?
			   ((done_pending_q & ~done_delay_elapsed) | done_q) :
			   done_pending_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   done_pendingq
     (.clk(clk),
      .reset(reset),
      .d(done_pending_s),
      .q(done_pending_q));
   
   wire 		  io_done_s, io_done_q;
   assign io_done_s
     = req_active ? 
       ((io_done_q & ~req_fall) | (done_pending_q & done_delay_elapsed)) : 
       io_done_q;
   c_dff
     #(.width(1),
       .reset_type(reset_type))
   io_doneq
     (.clk(clk),
      .reset(reset),
      .d(io_done_s),
      .q(io_done_q));
   
   assign io_done = io_done_q;
   
endmodule
