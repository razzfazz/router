function integer clogb(input integer argument);
   integer i;
   begin
      clogb = 0;
      for(i = argument - 1; i > 0; i = i >> 1)
	  clogb = clogb + 1;
      /*for(i = 0; i < 32; i = i + 1)
	if(1 << i >= argument)
	  begin
	     clogb = i;
	     exit;
	  end*/
      /*for(clogb = 0; argument > 0; clogb = clogb + 1)
	argument = argument >> 1;*/
   end
endfunction

function integer num_blocks(input integer width, input integer block_width);
   begin
      num_blocks = (width + block_width - 1) / block_width;
   end
endfunction

function integer pop_count(input integer argument);
   integer i;
   begin
      pop_count = 0;
      for(i = argument; i > 0; i = i >> 1)
	pop_count = pop_count + (i & 1);
   end
endfunction
	   
function integer encode(input integer argument);
   integer i;
   integer scale;
   begin
      encode = 0;
      scale = 0;
      for(i = argument; i > 0; i = i >> 1)
	begin
	   if(i & 1)
	     encode = encode + scale;
	   scale = scale + 1;
	end
   end
endfunction