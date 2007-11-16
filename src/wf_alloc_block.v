module wf_alloc_base
   (
    input  prio,
    input  xin,
    input  yin,
    input  req,
    output xout,
    output yout,
    output gnt
    );

   wire    xprio = xin | prio;
   wire    yprio = yin | prio;
   
   assign  xout = xprio & (~yprio | ~req);
   assign  yout = yprio & (~xprio | ~req);
   assign  gnt = xprio & yprio & req;
   
endmodule
