#!/bin/sh

for num_ports in 5 10 #15
  do
  for num_vcs in 2 4 #8
    do
    for architecture in 0 1 2 3
      do
      name=vc_p${num_ports}_v${num_vcs}_a${architecture}
      clk_period_range=`cat clk_ranges.csv | egrep "^${name},"`
      clk_period_min=`echo ${clk_period_range} | cut -d "," -f 2`
      clk_period_max=`echo ${clk_period_range} | cut -d "," -f 3`
      basedir=`pwd`/build/${name}
      ./clone.sh ${basedir}
      rundir=${basedir}/synth/run
      touch ${rundir}/config.sh
      echo "rundir=${rundir}" > ${rundir}/config.sh
      echo "num_ports=${num_ports}" >> ${rundir}/config.sh
      echo "num_vcs=${num_vcs}" >> ${rundir}/config.sh
      echo "architecture=${architecture}" >> ${rundir}/config.sh
      echo "clk_period_min=${clk_period_min}" >> ${rundir}/config.sh
      echo "clk_period_max=${clk_period_max}" >> ${rundir}/config.sh
      echo ${rundir}/run.sh | qsub -N ${name} -v rundir=${rundir}
    done
  done
done
