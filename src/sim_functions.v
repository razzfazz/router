//`ifndef _SIM_FUNCTIONS_V_
//`define _SIM_FUNCTIONS_V_

function is_x(input integer net);
   begin
      is_x = (^net === 1'bx);
   end
endfunction

//`endif
