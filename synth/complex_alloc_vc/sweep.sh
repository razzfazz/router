#!/bin/sh

use_clock_gating=0

for num_ports in 5 10 15
do
    for num_vcs in 1 2 4 8
    do
	for use_architecture in 0 1
	do
            for clk_period in `seq 3.0 -0.1 2.0`
            do
		echo "num_ports=${num_ports},num_vcs=${num_vcs},use_architecture=${use_architecture},use_clock_gating=${use_clock_gating},clk_period=${clk_period}"
		cat synth.template.tcl \
    		    | sed s/CLK_PERIOD/${clk_period}/ \
    		    > synth.tcl
    		cat ../../src/simple_alloc.template.v \
    		    | sed s/NUM_PORTS/${num_ports}/ \
    		    | sed s/NUM_VCS/${num_vcs}/ \
    		    | sed s/USE_CLOCK_GATING/${use_clock_gating}/ \
    		    | sed s/USE_ARCHITECTURE/${use_architecture}/ \
    		    > ../../src/simple_alloc.v
    		make clean > /dev/null
    		make | tail -8 | head -7
    		mkdir results/num_ports${num_ports}_num_vcs${num_vcs}_use_architecture${use_architecture}_use_clock_gating${use_clock_gating}_clk_period${clk_period}
    		cp -R build/* results/num_ports${num_ports}_num_vcs${num_vcs}_use_architecture${use_architecture}_use_clock_gating${use_clock_gating}_clk_period${clk_period}
	    done
    	done
    done
done
