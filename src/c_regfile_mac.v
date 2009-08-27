// $Id$

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
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



// generic register file
module c_regfile_mac
  (clk, write_enable, write_address, write_data, read_enable, read_address,
   read_data);
   
`include "c_constants.v"
   
   function integer clogb(input integer argument);
      integer i;
      begin
	 clogb = 0;
	 for(i = argument - 1; i > 0; i = i >> 1)
	   clogb = clogb + 1;
      end
   endfunction
   
   // number of entries
   parameter depth = 8;
   
   // width of each entry
   parameter width = 64;
   
   // select implementation variant
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   // width required to swelect an entry
   localparam addr_width = clogb(depth);
   
   input clk;
   
   // if high, write to entry selected by write_address
   input write_enable;
   
   // entry to be written to
   input [0:addr_width-1] write_address;
   
   // data to be written
   input [0:width-1] write_data;
   
   // if high, enable read for next cycle
   input read_enable;
   
   // entry to read out
   input [0:addr_width-1] read_address;
   
   // contents of entry selected by read_address
   output [0:width-1] read_data;
   wire [0:width-1] read_data;
   
   
   //---------------------------------------------------------------------------
   // WRITE TIMING
   // ============
   // The values of 'write_enable', 'write_address' and 'write_data' at the end 
   // of cycle N determine a register file write to perform in cycle N+1; the
   // write will complete -- i.e., the value specified in 'write_data' will be 
   // available in the register file entry selected by 'write_address' -- in 
   // cycle N+2.
   //---------------------------------------------------------------------------
   // READ TIMING
   // ===========
   // The valuees of 'read_enable' and 'read_address' at the end of cycle N 
   // determine which register file entry to read out in cycle N+1; i.e., in 
   // cycle N+1, the cell selected by the value of 'read_address' at the end of 
   // cycle N will be connected to 'read_data'.
   //---------------------------------------------------------------------------
   
   
   reg 		    write_enable_q;
   reg [0:data_width-1] write_data_q;
   reg [0:addr_width-1] read_address_q;
   
   always @(posedge clk)
     begin
	write_enable_q <= write_enable;
	write_data_q <= write_data;
	if(read_enable)
	  read_address_q <= read_address;
     end
   
   genvar 		level;
   
   generate
      
      case(regfile_type)
	
	`REGFILE_TYPE_FF_2D:
	  begin
	     
	     reg [0:width-1] 	storage [0:depth-1];
	     
	     always @(posedge clk)
	       if(write_enable_q)
		 storage[write_address] <= write_data_q;
	     
	     assign read_data = storage[read_address_q];
	     
	  end
	
	`REGFILE_TYPE_FF_1D_MUX:
	  begin
	     
	     wire [0:depth*width-1] read_data_lvl;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:mux_levels
		  
		  wire write;
		  assign write = write_enable_q && (write_address == level);
		  
		  reg [0:width-1] storage;
		  
		  always @(posedge clk)
		    if(write)
		      storage <= write_data_q;
		  
		  assign read_data_lvl[level*width:(level+1)*width-1] = storage;
		  
	       end
	     
	     assign read_data = read_data_lvl[read_address_q*width +: width];
	     
	  end
	
	`REGFILE_TYPE_FF_1D_TRISTATE:
	  begin
	     
	     reg 		    read_enable_q;
	     
	     always @(posedge clk)
	       read_enable_q <= read_enable;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:tristate_levels
		  
		  wire write;
		  assign write = write_enable_q && (write_address == level);
		  
		  reg [0:width-1] storage;
		  always @(posedge clk)
		    if(write)
		      storage <= write_data_q;
		  
		  wire 		  read;
		  assign read = read_enable_q && (read_address_q == level);
		  
		  assign read_data = read ? storage : {width{1'bz}};
		  
	       end
	     
	  end
	
      endcase
      
   endgenerate
   
endmodule
