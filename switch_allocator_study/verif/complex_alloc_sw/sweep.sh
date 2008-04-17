#!/bin/sh

for num_ports in 5 10 15
  do
  for num_vcs in 2 4 8
    do
    for buffer_occupancy in 25 75
      do
      name=p${num_ports}_v${num_vcs}_o${buffer_occupancy}
      basedir=`pwd`/build/${name}
      ./clone.sh ${basedir}
      rundir=${basedir}/verif/run
      touch ${rundir}/config.sh
      echo "rundir=${rundir}" > ${rundir}/config.sh
      echo "num_ports=${num_ports}" >> ${rundir}/config.sh
      echo "num_vcs=${num_vcs}" >> ${rundir}/config.sh
      echo "buffer_occupancy=${buffer_occupancy}" >> ${rundir}/config.sh
      echo ${rundir}/run.sh | qsub -N ${name} -v rundir=${rundir}
    done
  done
done
