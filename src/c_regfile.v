// $Id$

/*
 Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

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

//==============================================================================
// generic register file
//==============================================================================

module c_regfile
  (clk, write_active, write_enable, write_address, write_data, read_address, 
   read_data);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // number of entries
   parameter depth = 8;
   
   // width of each entry
   parameter width = 64;
   
   // number of write ports
   parameter num_write_ports = 1;
   
   // number of read ports
   parameter num_read_ports = 1;
   
   // select implementation variant
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   // width required to swelect an entry
   localparam addr_width = clogb(depth);
   
   input clk;
   
   input write_active;
   
   // if high, write to entry selected by write_address
   input [0:num_write_ports-1] write_enable;
   
   // entry to be written to
   input [0:num_write_ports*addr_width-1] write_address;
   
   // data to be written
   input [0:num_write_ports*width-1] 	  write_data;
   
   // entries to read out
   input [0:num_read_ports*addr_width-1]  read_address;
   
   // contents of entries selected by read_address
   output [0:num_read_ports*width-1] 	  read_data;
   wire [0:num_read_ports*width-1] 	  read_data;
   
   genvar 				  read_port;
   genvar 				  write_port;
   
   generate
      
      case(regfile_type)
	
	`REGFILE_TYPE_FF_2D:
	  begin
	     
	     reg [0:width-1] storage_2d [0:depth-1];

	     for(write_port = 0; write_port < num_write_ports; 
		 write_port = write_port + 1)
	       begin:write_ports
		  
		  wire port_write_enable;
		  assign port_write_enable = write_enable[write_port];
		  
		  wire [0:addr_width-1] port_write_address;
		  assign port_write_address
		    = write_address[write_port*addr_width:
				    (write_port+1)*addr_width-1];
		  
		  wire [0:width-1] 	port_write_data;
		  assign port_write_data
		    = write_data[write_port*width:(write_port+1)*width-1];
		  
		  always @(posedge clk)
		    if(write_active)
		      if(port_write_enable)
			storage_2d[port_write_address] <= port_write_data;
		  
	       end
	     
	     for(read_port = 0; read_port < num_read_ports; 
		 read_port = read_port + 1)
	       begin:read_ports_2d
		  
		  wire [0:addr_width-1] port_read_address;
		  assign port_read_address
		    = read_address[read_port*addr_width:
				   (read_port+1)*addr_width-1];
		  
		  wire [0:width-1] 	port_read_data;
		  assign port_read_data = storage_2d[port_read_address];
		  
		  assign read_data[read_port*width:(read_port+1)*width-1]
		    = port_read_data;
		  
	       end
	     
	  end
	
	`REGFILE_TYPE_FF_1D_MUX, `REGFILE_TYPE_FF_1D_SEL:
	  begin
	     
	     wire [0:depth*width-1] storage_1d;
	     
	     genvar level;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:levels
		  
		  reg [0:width-1] storage;
		  
		  for(write_port = 0; write_port < num_write_ports;
		      write_port = write_port + 1)
		    begin:write_ports
		       
		       wire port_write_enable;
		       assign port_write_enable = write_enable[write_port];
		       
		       wire [0:addr_width-1] port_write_address;
		       assign port_write_address
			 = write_address[write_port*addr_width:
					 (write_port+1)*addr_width-1];
		       
		       wire [0:width-1]      port_write_data;
		       assign port_write_data
			 = write_data[write_port*width:(write_port+1)*width-1];
		       
		       wire 		     port_write;
		       assign port_write
			 = port_write_enable && (port_write_address == level);
		       
		       always @(posedge clk)
			 if(write_active)
			   if(port_write)
			     storage <= port_write_data;
		       
		    end
		  
		  assign storage_1d[level*width:(level+1)*width-1] = storage;
		  
	       end
	     
	     for(read_port = 0; read_port < num_read_ports; 
		 read_port = read_port + 1)
	       begin:read_ports_1d
		  
		  wire [0:addr_width-1] port_read_address;
		  assign port_read_address
		    = read_address[read_port*addr_width:
				   (read_port+1)*addr_width-1];
		  
		  wire [0:width-1] 	port_read_data;
		  
		  case(regfile_type)
		    
		    `REGFILE_TYPE_FF_1D_SEL:
		      begin
			 
			 wire [0:depth-1] port_read_sel;
			 c_decode
			   #(.num_ports(depth))
			 port_read_sel_dec
			   (.data_in(port_read_address),
			    .data_out(port_read_sel));
			 
			 c_select_1ofn
			   #(.num_ports(depth),
			     .width(width))
			 port_read_data_sel
			   (.select(port_read_sel),
			    .data_in(storage_1d),
			    .data_out(port_read_data));
			 
		      end
		    
		    `REGFILE_TYPE_FF_1D_MUX:
		      begin
			 
			 assign port_read_data
			   = storage_1d[port_read_address*width +: width];
			 
		      end
		    
		  endcase
		  
		  assign read_data[read_port*width:(read_port+1)*width-1]
		    = port_read_data;
		  
	       end
	     
	  end
	
	`REGFILE_TYPE_FF_DW:
	  begin
	     
	     wire write_enable_b;
	     assign write_enable_b = ~write_enable;
	     
	     if((num_read_ports == 1) && (num_write_ports == 1))
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
	     else if((num_read_ports == 2) && (num_write_ports == 1))
	       begin
		  
		  wire [0:addr_width-1] read_address_1;
		  assign read_address_1
		    = read_address[0:addr_width-1];
		  
		  wire [0:addr_width-1] read_address_2;
		  assign read_address_2
		    = read_address[addr_width:2*addr_width-1];
		  
		  wire [0:width-1] 	read_data_1;
		  wire [0:width-1] 	read_data_2;
		  DW_ram_2r_w_s_dff
		    #(.data_width(width),
		      .depth(depth),
		      .rst_mode(1))
		  DW_rf_dff
		    (.clk(clk),
		     .rst_n(1'b1),
		     .cs_n(write_enable_b),
		     .wr_n(write_enable_b),
		     .rd1_addr(read_address_1),
		     .rd2_addr(read_address_2),
		     .wr_addr(write_address),
		     .data_in(write_data),
		     .data_rd1_out(read_data_1),
		     .data_rd2_out(read_data_2));
		  
		  assign read_data = {read_data_1, read_data_2};
		  
	       end
	     else
	       begin
		  
		  // synopsys translate_off
		  initial
		    begin
		       $display({"ERROR: Register file %m does not support ",
				 "DesignWare register file models with %d ",
				 "read ports and %d write ports."}, 
				num_read_ports, num_write_ports);
		       $stop;
		    end
		  // synopsys translate_on
		  
	       end
	     
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
		$display({"ERROR: Register file module %m requires a depth ", 
			  "of two or more entries."});
		$stop;
	     end
	end
      
      // synopsys translate_on
      
   endgenerate
   
endmodule
