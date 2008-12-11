#!/bin/sh

for restrict in 0 1
do
    for architecture in 0 1 2 3 4 5 6 7 8 9 10 11
    do
	name=sw_r${restrict}_a${architecture}
	#clk_period_range=`cat clk_ranges.csv | egrep "^${name},"`
	clk_period_min=0.0 #`echo ${clk_period_range} | cut -d "," -f 2`
	clk_period_max=4.0 #`echo ${clk_period_range} | cut -d "," -f 3`
	basedir=`pwd`/build/${name}
	./clone.sh ${basedir}
	rundir=${basedir}/synth/run
	touch ${rundir}/config.sh
	echo "rundir=${rundir}" > ${rundir}/config.sh
	echo "restrict=${restrict}" >> ${rundir}/config.sh
	echo "architecture=${architecture}" >> ${rundir}/config.sh
	echo "clk_period_min=${clk_period_min}" >> ${rundir}/config.sh
	echo "clk_period_max=${clk_period_max}" >> ${rundir}/config.sh
	echo ${rundir}/run.sh | qsub -N ${name} -v rundir=${rundir}
    done
done
