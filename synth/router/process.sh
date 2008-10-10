#!/bin/sh

tempfile="data.`date --iso-8601=seconds`.tmp"

print_data()
{
    cat $1 \
	| grep -A 7 "num_ports=$2,num_vcs=$3,architecture=$4" \
	| sed s/"num_ports=[0-9]*,architecture=[0-9]*,use_clock_gating=[0-9]*,clk_period=\([0-9\.]*\)"/"\1"/ \
	| grep -v "Non Comb Area:" \
	| grep -v "Comb Area:" \
	| sed s/" *Total Area: *\([0-9\.]*\)"/"\1"/ \
	| grep -v "Total Power(.*):" \
	| grep -v "Data Required:" \
	| sed s/" *Data Arrival: *-*\([0-9\.]*\)"/"\1"/ \
	| sed s/" *Slack(.*): *\(-*[0-9\.]*\)"/"\1;"/ \
	| tr "\n" "," \
	| sed s/";,"/";"/g \
	| tr ";" "\n"
}

for num_ports in 5 10 15
do
  for num_vcs in 1 2 4 8
  do
    for architecture in 0 1
    do
      echo "num_ports=${num_ports},num_vcs=${num_vcs},architecture=${architecture}"
      echo "clk_period,total_area,data_arrival,slack"
      print_data $1 $num_ports $num_vcs $architecture
    done
  done
done
