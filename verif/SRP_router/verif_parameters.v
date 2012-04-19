// packet injection rate (percentage of cycles)
//cmesh 2.5X
//mesh  1.3X
//fbfly 1.0X
//kn    1.0X
//ftree 0.75X
parameter packet_rate   =25;
parameter extern_rate   =25;


parameter packet_ratio  = 99;

initial begin : main
 //  $dumpfile("router.vcd");
 //  $dumpvars(0, testbench.rtr);
 //  $sdf_annotate("router_wrap.sdf",testbench.rtr); 
end  
 
