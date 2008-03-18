#!/bin/sh

reset_type=1
hold_type=1

for num_ports in 5 10 15
do
    for architecture in 0 1 2 3 4
    do
        for clk_period in `seq 3.0 -0.1 2.0`
        do
		echo "num_ports=${num_ports},architecture=${architecture},reset_type=${reset_type},hold_type=${hold_type},clk_period=${clk_period}"
		cat synth.template.tcl \
    		    | sed s/CLK_PERIOD/${clk_period}/ \
    		    > synth.tcl
    		cat ../../src/simple_alloc.template.v \
    		    | sed s/NUM_PORTS/${num_ports}/ \
    		    | sed s/RESET_TYPE/${reset_type}/ \
    		    | sed s/HOLD_TYPE/${hold_type}/ \
    		    | sed s/ARCHITECTURE/${architecture}/ \
    		    > ../../src/simple_alloc.v
    		make clean > /dev/null
    		make | tail -8 | head -7
    		mkdir results/num_ports${num_ports}_architecture${architecture}_reset_type${reset_type}_hold_type${hold_type}_clk_period${clk_period}
    		cp -R build/* results/num_ports${num_ports}_architecture${architecture}_reset_type${reset_type}_hold_type${hold_type}_clk_period${clk_period}
	    done
    	done
    done
done
