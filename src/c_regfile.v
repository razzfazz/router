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



// generic register file
module c_regfile
  (clk, write_enable, write_address, write_data, read_address, read_data);
   
`include "c_functions.v"
`include "c_constants.v"
   
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
   
   // entry to read out
   input [0:addr_width-1] read_address;
   
   // contents of entry selected by read_address
   output [0:width-1] read_data;
   wire [0:width-1] read_data;
   
   genvar 	    level;
   
   generate
      
      case(regfile_type)
	
	`REGFILE_TYPE_FF_2D, `REGFILE_TYPE_LAT_2D:
	  begin
	     
	     reg [0:width-1] storage [0:depth-1];
	     
	     case(regfile_type)
	       
	       `REGFILE_TYPE_FF_2D:
		 always @(posedge clk)
		   if(write_enable)
		     storage[write_address] <= write_data;
	       
	       `REGFILE_TYPE_LAT_2D:
		 always @(clk, write_enable, write_address, write_data)
		   if(~clk & write_enable)
		     storage[write_address] <= write_data;
	       
	     endcase
	     
	     assign read_data = storage[read_address];
	     
	  end
	
	`REGFILE_TYPE_FF_1D_MUX, `REGFILE_TYPE_LAT_1D_MUX:
	  begin
	     
	     wire [0:depth*width-1] read_data_lvl;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:mux_levels
		  
		  wire write;
		  assign write = write_enable && (write_address == level);
		  
		  reg [0:width-1] storage;
		  
		  case(regfile_type)
		    
		    `REGFILE_TYPE_FF_1D_MUX:
		      always @(posedge clk)
			if(write)
			  storage <= write_data;
		    
		    `REGFILE_TYPE_LAT_1D_MUX:
		      always @(clk, write, write_data)
			if(~clk & write)
			  storage <= write_data;
		    
		  endcase
		  
		  assign read_data_lvl[level*width:(level+1)*width-1] = storage;
		  
	       end
	     
	     assign read_data = read_data_lvl[read_address*width +: width];
	     
	  end
	
	`REGFILE_TYPE_FF_1D_TRISTATE, `REGFILE_TYPE_LAT_1D_TRISTATE:
	  begin
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:tristate_levels
		  
		  wire write;
		  assign write = write_enable && (write_address == level);
		  
		  reg [0:width-1] storage;
		  
		  case(regfile_type)
		    
		    `REGFILE_TYPE_FF_1D_TRISTATE:
		      always @(posedge clk)
			if(write)
			  storage <= write_data;
		    
		    `REGFILE_TYPE_LAT_1D_TRISTATE:
		      always @(clk, write, write_data)
			if(~clk & write)
			  storage <= write_data;
		    
		  endcase
		  
		  wire 		  read;
		  assign read = (read_address == level);
		  
		  assign read_data = read ? storage : {width{1'bz}};
		  
	       end
	     
	  end
	
	`REGFILE_TYPE_FF_DW, `REGFILE_TYPE_LAT_DW:
	  begin
	     
	     wire write_enable_b;
	     assign write_enable_b = ~write_enable;
	     
	     case(regfile_type)
	       
	       `REGFILE_TYPE_FF_DW:
		 begin
		    DW_ram_r_w_s_dff
		      #(.data_width(width),
			.depth(depth),
			.rst_mode(1))
		    DW_rf_dff
		      (.clk(clk),
		       .rst_n(1'b1),
		       .cs_n(write_enable_b),
		       .wr_n(write_enable_b),
		       .rd_addr(read_address),
		       .wr_addr(write_address),
		       .data_in(write_data),
		       .data_out(read_data));
		 end
	
	       `REGFILE_TYPE_LAT_DW:
		 begin
		    DW_ram_r_w_s_lat
		      #(.data_width(width),
			.depth(depth))
		    DW_rf_lat
		      (.clk(clk),
		       .cs_n(write_enable_b),
		       .wr_n(write_enable_b),
		       .rd_addr(read_address),
		       .wr_addr(write_address),
		       .data_in(write_data),
		       .data_out(read_data));
		 end
	       
	     endcase
	     
	  end
	
      endcase
      
      
      //----------------------------------------------------------------------
      // check parameter validity
      //----------------------------------------------------------------------
      
      // synopsys translate_off
      if(depth < 2)
      begin
	 initial
	 begin
	    $display("ERROR: The register file module requires a depth of " +
		     "two or more entries.");
	    $stop;
	     end
      end
      // synopsys translate_on
      
   endgenerate
   
endmodule
