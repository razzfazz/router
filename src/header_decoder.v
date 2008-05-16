module header_decoder
  (header, pkt_class, pkt_address);

`include "config.v"

   input [0:head_data_width-1] header;
   output [0:class_width-1] pkt_class;
   output [0:addr_width-1] pkt_address;

   assign pkt_class = header[0:class_width-1];
   assign pkt_address = header[class_width:(class_width+addr_width)-1];

endmodule
