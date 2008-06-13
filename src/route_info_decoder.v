module route_info_decoder
  (route_info, traffic_class, routing_class, next_address, final_address);

`include "config.v"

   input [0:route_info_width-1] route_info;
   output [0:traffic_class_idx_width-1] traffic_class;
   output [0:routing_class_idx_width-1] routing_class;
   output [0:addr_width-1] next_address;
   output [0:addr_width-1] final_address;

   assign traffic_class = header[0:traffic_class_idx_width-1];
   assign routing_class = header[traffic_class_idx_width:
				 (traffic_class_idx_width+
				  routing_class_idx_width)-1];
   assign next_address = header[(traffic_class_idx_width+
				 routing_class_idx_width):
				(traffic_class_idx_width+
				 routing_class_idx_width+
				 addr_width)-1];
   assign final_address = header[(traffic_class_idx_width+
				  routing_class_idx_width+
				  addr_width):
				 (traffic_class_idx_width+
				  routing_class_idx_width+
				  addr_width+
				  addr_width)-1];
   
endmodule
