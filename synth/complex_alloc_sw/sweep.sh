#!/bin/sh

reset_type=1
hold_type=1

for num_ports in 5 10 15
do
    for num_vcs in 2 4 8
    do
	for architecture in 0 1 2 3 4 5 6 7 8 9
	do
            for clk_period in `seq 5.0 -0.2 0.0`
            do
		echo "num_ports=${num_ports},num_vcs=${num_vcs},architecture=${architecture},reset_type=${reset_type},hold_type=${hold_type},clk_period=${clk_period}"
		cfg=num_ports${num_ports}_num_vcs${num_vcs}_architecture${architecture}_reset_type${reset_type}_hold_type${hold_type}_clk_period${clk_period}
		cat synth.template.tcl \
    		    | sed s/CLK_PERIOD/${clk_period}/ \
    		    > synth.tcl
    		cat ../../src/complex_alloc_sw.template.v \
    		    | sed s/NUM_PORTS/${num_ports}/ \
    		    | sed s/NUM_VCS/${num_vcs}/ \
    		    | sed s/RESET_TYPE/${reset_type}/ \
    		    | sed s/HOLD_TYPE/${hold_type}/ \
    		    | sed s/ARCHITECTURE/${architecture}/ \
    		    > ../../src/complex_alloc_sw.v
    		make clean > /dev/null
    		make | tail -8 | head -7
    		mkdir results/${cfg}
    		cp -R build/* results/${cfg}
		if cat build/rpt/*.timing | grep VIOLATED
		then
		    echo "TIMING NOT MET!"
		    break
		fi
	    done
    	done
    done
done
