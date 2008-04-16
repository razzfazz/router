#!/bin/sh

use_clock_gating=0
fixed_delay=0
runtime=100000

for num_ports in 5 10 15 20
do
    for hold_requests in 0 1
    do
	echo "num_ports=${num_ports},use_clock_gating=${use_clock_gating},fixed_delay=${fixed_delay},hold_requests=${hold_requests},runtime=${runtime}"

	use_allocator_type=0
	for use_arbiter_type in 0 1
	do
	    echo "use_allocator_type=$use_allocator_type,use_arbiter_type=$use_arbiter_type"
	    for mean_delay in 1 2 4 8
	    do
		cat testbench.template.v \
		    | sed s/NUM_PORTS/$num_ports/ \
		    | sed s/USE_CLOCK_GATING/$use_clock_gating/ \
		    | sed s/USE_ALLOCATOR_TYPE/$use_allocator_type/ \
		    | sed s/USE_ARBITER_TYPE/$use_arbiter_type/ \
		    | sed s/MEAN_DELAY/$mean_delay/ \
		    | sed s/FIXED_DELAY/$fixed_delay/ \
		    | sed s/HOLD_REQUESTS/$hold_requests/ \
		    | sed s/RUNTIME/$runtime/ \
		    | sed s/OUTPUT_AS_CSV/1/ \
		    > testbench.v
		make clean all > /dev/null
		./simv | grep mean | sed s/"mean,"//
	    done
	done
	
	use_arbiter_type=0
	for use_allocator_type in 1 2
	do
	    echo "use_allocator_type=$use_allocator_type,use_arbiter_type=$use_arbiter_type"
	    for mean_delay in 1 2 4 8
	    do
		cat testbench.template.v \
		    | sed s/NUM_PORTS/$num_ports/ \
		    | sed s/USE_CLOCK_GATING/$use_clock_gating/ \
		    | sed s/USE_ALLOCATOR_TYPE/$use_allocator_type/ \
		    | sed s/USE_ARBITER_TYPE/$use_arbiter_type/ \
		    | sed s/MEAN_DELAY/$mean_delay/ \
		    | sed s/FIXED_DELAY/$fixed_delay/ \
		    | sed s/HOLD_REQUESTS/$hold_requests/ \
		    | sed s/RUNTIME/$runtime/ \
		    | sed s/OUTPUT_AS_CSV/1/ \
		    > testbench.v
		make clean all > /dev/null
		./simv | grep mean | sed s/"mean,"//
	    done
	done
    done
done