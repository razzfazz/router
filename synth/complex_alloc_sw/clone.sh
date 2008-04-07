#!/bin/sh

basedir=${1}

files="config_base.sh Makefile run.sh synth.tcl"

mkdir -p ${basedir}
cp -R ../../src ${basedir}
mkdir -p ${basedir}/synth
cp -R ../scripts ${basedir}/synth
mkdir -p ${basedir}/synth/run
cp ${files} ${basedir}/synth/run
mkdir -p ${basedir}/synth/run/results
