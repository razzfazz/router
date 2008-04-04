#!/bin/sh

tclk=2
sim_cycles=1000
warmup_cycles=100
initial_seed=0
reset_type=1
hold_type=1
output_as_csv=1

for buffer_occupancy in 25 50 75
  do
  for num_ports in 5 10 15
    do
    for num_vcs in 2 4 8
      do
      if [ ${output_as_csv} -eq 1 ]
	  then
	  echo "num_ports=${num_ports},num_vcs=${num_vcs},buffer_occupancy=${buffer_occupancy}"
      else
	  echo "SWEEP: num_ports=${num_ports},num_vcs=${num_vcs},buffer_occupancy=${buffer_occupancy}"
      fi
      cat testbench.template.v \
	  | sed s/TCLK/${tclk}/ \
	  | sed s/SIM_CYCLES/${sim_cycles}/ \
	  | sed s/WARMUP_CYCLES/${warmup_cycles}/ \
	  | sed s/INITIAL_SEED/${initial_seed}/ \
	  | sed s/RESET_TYPE/${reset_type}/ \
	  | sed s/HOLD_TYPE/${hold_type}/ \
	  | sed s/NUM_PORTS/${num_ports}/ \
	  | sed s/NUM_VCS/${num_vcs}/ \
	  | sed s/BUFFER_OCCUPANCY/${buffer_occupancy}/ \
	  | sed s/OUTPUT_AS_CSV/${output_as_csv}/ \
	  > testbench.v
      make clean all > /dev/null
      ./simv
    done
  done
done
