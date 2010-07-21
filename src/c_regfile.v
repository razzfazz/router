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
  (clk, active, write_enable, write_address, write_data, read_enable, 
   read_address, read_data);
   
`include "c_functions.v"
`include "c_constants.v"
   
   // number of entries
   parameter depth = 8;
   
   // width of each entry
   parameter width = 64;
   
   // number of read ports
   parameter num_read_ports = 1;
   
   // select implementation variant
   parameter regfile_type = `REGFILE_TYPE_FF_2D;
   
   // width required to swelect an entry
   localparam addr_width = clogb(depth);
   
   input clk;
   input active;
   
   // if high, write to entry selected by write_address
   input write_enable;
   
   // entry to be written to
   input [0:addr_width-1] write_address;
   
   // data to be written
   input [0:width-1] 	  write_data;
   
   // if high, read from entries selected by read_address
   input [0:num_read_ports-1] read_enable;
   
   // entries to read out
   input [0:num_read_ports*addr_width-1] read_address;
   
   // contents of entries selected by read_address
   output [0:num_read_ports*width-1] 	 read_data;
   wire [0:num_read_ports*width-1] 	 read_data;
   
   wire [0:num_read_ports*width-1] 	 cell_data;
   
   genvar 				 read_port;
   
   generate
      
      case(regfile_type)
	
	`REGFILE_TYPE_FF_2D, `REGFILE_TYPE_LAT_2D:
	  begin
	     
	     reg [0:width-1] storage_2d [0:depth-1];
	     
	     case(regfile_type)
	       
	       `REGFILE_TYPE_FF_2D:
		 always @(posedge clk)
		   if(active)
		     if(write_enable)
		       storage_2d[write_address] <= write_data;
	       
	       `REGFILE_TYPE_LAT_2D:
		 always @(clk, active, write_enable, write_address, write_data)
		   if(~clk)
		     if(active)
		       if(write_enable)
			 storage_2d[write_address] <= write_data;
	       
	     endcase
	     
	     for(read_port = 0; read_port < num_read_ports; 
		 read_port = read_port + 1)
	       begin:read_ports_2d
		  
		  wire [0:addr_width-1] port_read_address;
		  assign port_read_address
		    = read_address[read_port*addr_width:
				   (read_port+1)*addr_width-1];
		  
		  wire [0:width-1] 	port_cell_data;
		  assign port_cell_data = storage_2d[port_read_address];
		  
		  assign cell_data[read_port*width:(read_port+1)*width-1]
		    = port_cell_data;
		  
	       end
	     
	  end
	
	`REGFILE_TYPE_FF_1D_MUX, `REGFILE_TYPE_LAT_1D_MUX,
	`REGFILE_TYPE_FF_1D_TRISTATE, `REGFILE_TYPE_LAT_1D_TRISTATE:
	  begin
	     
	     wire [0:depth*width-1] storage_1d;
	     
	     genvar level;
	     
	     for(level = 0; level < depth; level = level + 1)
	       begin:levels
		  
		  wire write;
		  assign write = write_enable && (write_address == level);
		  
		  reg [0:width-1] storage;
		  
		  case(regfile_type)
		    
		    `REGFILE_TYPE_FF_1D_MUX, `REGFILE_TYPE_FF_1D_TRISTATE:
		      always @(posedge clk)
			if(active)
			  if(write)
			    storage <= write_data;
		    
		    `REGFILE_TYPE_LAT_1D_MUX, `REGFILE_TYPE_LAT_1D_TRISTATE:
		      always @(clk, active, write, write_data)
			if(~clk)
			  if(active)
			    if(write)
			      storage <= write_data;
		    
		  endcase
		  
		  assign storage_1d[level*width:(level+1)*width-1] = storage;
		  
	       end
	     
	     for(read_port = 0; read_port < num_read_ports; 
		 read_port = read_port + 1)
	       begin:read_ports_1d
		  
		  wire [0:addr_width-1] port_read_address;
		  assign port_read_address
		    = read_address[read_port*addr_width:
				   (read_port+1)*addr_width-1];
		  
		  wire [0:width-1] 	port_cell_data;
		  
		  case(regfile_type)
		    
		    `REGFILE_TYPE_FF_1D_TRISTATE, `REGFILE_TYPE_LAT_1D_TRISTATE:
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
			 port_cell_data_sel
			   (.select(port_read_sel),
			    .data_in(storage_1d),
			    .data_out(port_cell_data));
			 
		      end
		    
		    `REGFILE_TYPE_FF_1D_MUX, `REGFILE_TYPE_LAT_1D_MUX:
		      begin
			 
			 assign port_cell_data
			   = storage_1d[port_read_address*width +: width];
			 
		      end
		    
		  endcase

		  assign cell_data[read_port*width:(read_port+1)*width-1]
		    = cell_data;
		  
	       end
	     
	  end
	
	`REGFILE_TYPE_FF_DW, `REGFILE_TYPE_LAT_DW:
	  begin
	     
	     wire write_enable_b;
	     assign write_enable_b = ~write_enable;
	     
	     case(num_read_ports)
	       
	       1:
		 begin
		    
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
			      .data_out(cell_data));
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
			      .data_out(cell_data));
			end
		      
		    endcase
		    
		 end
	       
	       2:
		 begin
		    
		    wire [0:addr_width-1] read_address_1;
		    assign read_address_1
		      = read_address[0:addr_width-1];
		    
		    wire [0:addr_width-1] read_address_2;
		    assign read_address_2
		      = read_address[addr_width:2*addr_width-1];
		    
		    wire [0:width-1] 	  cell_data_1;
		    wire [0:width-1] 	  cell_data_2;
		    
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
			      .rd1_addr(read_address_1),
			      .rd2_addr(read_address_2),
			      .wr_addr(write_address),
			      .data_in(write_data),
			      .data_rd1_out(cell_data_1),
			      .data_rd2_out(cell_data_2));
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
			      .rd1_addr(read_address_1),
			      .rd2_addr(read_address_2),
			      .wr_addr(write_address),
			      .data_in(write_data),
			      .data_rd1_out(cell_data_1),
			      .data_rd2_out(cell_data_2));
			end
		      
		    endcase
		    
		    assign cell_data = {cell_data_1, cell_data_2};
		    
		 end
	       
	       default:
		 begin
		    
		    // synopsys translate_off
		    initial
		    begin
		       $display({"ERROR: Register file %m does not support ",
				 "DesignWare register file models with %d ",
				 "read ports."}, num_read_ports);
		       $stop;
		    end
		    // synopsys translate_on
		    
		 end
	       
	     endcase
	     
	  end
	
      endcase
      
      for(read_port = 0; read_port < num_read_ports; read_port = read_port + 1)
	begin:read_ports
	   
	   wire [0:width-1] port_cell_data;
	   assign port_cell_data
	     = cell_data[read_port*width:(read_port+1)*width-1];
	   
	   wire [0:width-1] port_read_data;
	   
	   case(regfile_type)
	     
	     `REGFILE_TYPE_FF_2D, `REGFILE_TYPE_FF_1D_TRISTATE,
	     `REGFILE_TYPE_FF_1D_MUX, `REGFILE_TYPE_FF_DW:
	       begin
		  
		  assign port_read_data = port_cell_data;
		  
	       end
	     
	     `REGFILE_TYPE_LAT_2D, `REGFILE_TYPE_LAT_1D_TRISTATE,
	     `REGFILE_TYPE_LAT_1D_MUX, `REGFILE_TYPE_LAT_DW:
	       begin
		  
		  wire port_read_enable;
		  assign port_read_enable = read_enable[read_port];
		  
		  reg [0:width-1] port_buffered_data;
		  always @(clk, active, port_read_enable, port_cell_data)
		    if(clk)
		      if(active)
			if(port_read_enable)
			  port_buffered_data <= port_cell_data;
		  
		  assign port_read_data = port_buffered_data;
		  
	       end
	     
	   endcase
	   
	   assign read_data[read_port*width:(read_port+1)*width-1]
	     = port_read_data;
	   
	end
      
      
      //----------------------------------------------------------------------
      // check parameter validity
      //----------------------------------------------------------------------
      
      // synopsys translate_off
      
      if(depth < 2)
	begin
	   initial
	     begin
		$display({"ERROR: The register file module requires a depth ", 
			  "of two or more entries."});
		$stop;
	     end
	end
      
      // synopsys translate_on
      
   endgenerate
   
endmodule
