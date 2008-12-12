#!/bin/sh

source ~/.profile

cd ${rundir}

source ./config_base.sh
source ./config.sh

srcdir="../../src"

good_clk=""
bad_clk=""

sed -i "s/\(parameter *ignore_same_port *=\) [^;]*/\1 ${restrict}/" \
    ${srcdir}/config.v
sed -i "s/\(parameter *restrict_vcs *=\) [^;]*/\1 ${restrict}/" \
    ${srcdir}/config.v

sed -i "s/\(parameter *architecture *=\) [^;]*/\1 ${architecture}/" \
    ${srcdir}/complex_alloc_sw.v

for clk_period in `seq ${clk_period_max} ${clk_period_delta} ${clk_period_min}`
do
    
    echo "running synthesis for clock period ${clk_period}..."
    
    sed -i "s/\(set clk_period\) .*/\1 ${clk_period}/" prolog.tcl
    
    make clean > /dev/null
    make | tail -8 | head -7
    
    mkdir results/clk${clk_period}
    cp -R build/* results/clk${clk_period}
    
    if cat build/rpt/*.timing | grep VIOLATED
    then
	echo "timing not met."
	bad_clk=${clk_period}
	break
    else
	echo "timing met."
	good_clk=${clk_period}
    fi
done

if test ${good_clk}
then
    if test ${bad_clk}
    then
	echo "minimum clock period is ${good_clk}."
    else
	echo "minimum clock period is smaller then ${clk_period_min}."
    fi
else
    echo "minimum clock period is larger then ${clk_period_max}."
fi
