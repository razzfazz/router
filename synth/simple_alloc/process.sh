#!/bin/sh

tempfile="data.`date --iso-8601=seconds`.tmp"

print_data()
{
    cat $1 \
	| grep -A 7 "num_ports=$2,architecture=$3" \
	| sed s/"num_ports=[0-9]*,architecture=[0-9]*,reset_type=[0-9]*,hold_type=[0-9]*,clk_period=\([0-9\.]*\)"/"\1"/ \
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
  for architecture in 0 1 2 3
  do
    echo "num_ports=${num_ports},architecture=${architecture}"
    echo "clk_period,total_area,data_arrival,slack"
    print_data $1 $num_ports $architecture
  done
done
