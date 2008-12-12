#!/bin/sh

source ~/.profile

cd ${rundir}

source ./config_base.sh
source ./config.sh

srcdir="../../src"

good_clk=""
bad_clk=""

case ${num_ports} in
    "5")
    echo "got 5 ports"
    sed -i "s/\(parameter *num_neighbors *=\) [^;]*/\1 2/" \
	${srcdir}/config.v
    ;;
    "10")
    echo "got 10 ports"
    sed -i \
	"s/\(parameter *num_neighbors *=\) [^;]*/\1 num_routers_per_dim - 1/" \
	${srcdir}/config.v
    ;;
esac

case ${num_vcs} in
    "2")
    sed -i "s/\(parameter *num_routing_classes *=\) [^;]*/\1 1/" \
	${srcdir}/config.v
    sed -i "s/\(parameter *num_vcs_per_class *=\) [^;]*/\1 1/" \
	${srcdir}/config.v
    ;;
    "4")
    sed -i "s/\(parameter *num_routing_classes *=\) [^;]*/\1 2/" \
	${srcdir}/config.v
    sed -i "s/\(parameter *num_vcs_per_class *=\) [^;]*/\1 1/" \
	${srcdir}/config.v
    ;;
    "8")
    sed -i "s/\(parameter *num_routing_classes *=\) [^;]*/\1 2/" \
	${srcdir}/config.v
    sed -i "s/\(parameter *num_vcs_per_class *=\) [^;]*/\1 2/" \
	${srcdir}/config.v
    ;;
esac

sed -i "s/\(parameter *architecture *=\) [^;]*/\1 ${architecture}/" \
    ${srcdir}/router.v

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
