#!/bin/sh

source ~/.profile

cd ${rundir}

source ./config_base.sh
source ./config.sh

srcdir=../../src

sed -i "s/\(parameter *num_ports *=\) [0-9]*/\1 ${num_ports}/" ${srcdir}/complex_alloc_sw.v
sed -i "s/\(parameter *num_vcs *=\) [0-9]*/\1 ${num_vcs}/" ${srcdir}/complex_alloc_sw.v
sed -i "s/\(parameter *reset_type *=\) [0-9]*/\1 ${reset_type}/" ${srcdir}/complex_alloc_sw.v
sed -i "s/\(parameter *architecture *=\) [0-9]*/\1 ${architecture}/" ${srcdir}/complex_alloc_sw.v

for clk_period in `seq ${clk_period_max} ${clk_period_delta} ${clk_period_min}`
  do

  echo "running synthesis for clock period ${clk_period}..."
  
  sed -i "s/\(set clk_period\) .*/\1 ${clk_period}/" synth.tcl
  
  make clean > /dev/null
  make | tail -8 | head -7
  
  mkdir results/clk${clk_period}
  cp -R build/* results/clk${clk_period}

  if cat build/rpt/*.timing | grep VIOLATED
      then
      echo "TIMING NOT MET!"
      break
  fi
done
