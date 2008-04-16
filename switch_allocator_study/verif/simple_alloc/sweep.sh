#!/bin/sh

tclk=6
hold_type=1
reset_type=1
fixed_delay=0
runtime=100000
output_as_csv=1

for num_ports in 5 10 15
do
    for hold_requests in 0 1
    do
	echo "tclk=${tclk},num_ports=${num_ports},hold_type=${hold_type},reset_type=${reset_type},fixed_delay=${fixed_delay},hold_requests=${hold_requests},runtime=${runtime}"

	for architecture in 0 1 2 3 4
	do
	    echo "architecture=${architecture}"
	    for mean_delay in 1 2 4 8
	    do
		cat testbench.template.v \
		    | sed s/TCLK/$tclk/ \
		    | sed s/NUM_PORTS/$num_ports/ \
		    | sed s/HOLD_TYPE/$hold_type/ \
		    | sed s/RESET_TYPE/$reset_type/ \
		    | sed s/ARCHITECTURE/$architecture/ \
		    | sed s/MEAN_DELAY/$mean_delay/ \
		    | sed s/FIXED_DELAY/$fixed_delay/ \
		    | sed s/HOLD_REQUESTS/$hold_requests/ \
		    | sed s/RUNTIME/$runtime/ \
		    | sed s/OUTPUT_AS_CSV/$output_as_csv/ \
		    > testbench.v
		make clean all > /dev/null
		./simv | grep mean | sed s/"mean,"//
	    done
	done
    done
done
