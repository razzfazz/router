function integer clogb(input integer argument)
		 begin
		    argument = argument - 1;
		    for(clogb = 0; argument > 0; clogb = clogb + 1)
		      begin
			 argument = argument >> 1;
		      end
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

function integer num_blocks(input integer width, input integer block_width)
		 begin
		    num_blocks = (width + block_width - 1) / block_width;
		 end
endfunction

function integer pop_count(input integer argument)
		 begin
		    for(pop_count = 0;
			argument > 0;
			pop_count = pop_count + argument % 2)
		      argument = argument >> 1;
		 end
endfunction
	   
