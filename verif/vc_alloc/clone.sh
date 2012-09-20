#!/bin/sh

basedir=${1}

files="config_base.sh Makefile run.sh testbench.v c_constants.v vcr_constants.v"

rm -rf ${basedir}

mkdir -p ${basedir}
cp -R ../../src ${basedir}
mkdir -p ${basedir}/verif/run
cp ${files} ${basedir}/verif/run
