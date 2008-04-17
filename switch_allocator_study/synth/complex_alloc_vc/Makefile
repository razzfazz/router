#
# Synthesis Makefile
#
SHELL = /bin/sh

# globals
proj := complex_alloc_vc

# clear suffix rules
.SUFFIXES: 


# ----
#  Directories
# --
build_dir := build
root_dir := ../..
script_dir := ../scripts
rpt_dir := $(build_dir)/rpt
net_dir := $(build_dir)/net
wrp_dir := $(build_dir)/wrp
rtl_dir := $(root_dir)/src
# ----
#  Tools
# --
wrap := $(script_dir)/synWrapper.pl
get_rep := $(script_dir)/getrep.pl
# ----
#  Synthesis Targets
# --

default: $(proj)

all: $(proj)

$(proj):
	mkdir -p $(wrp_dir)
	$(wrap) -module $(proj) -input $(rtl_dir)/$(proj).v \
          -output $(wrp_dir)/$(proj)_syn_wrapper.v
	mkdir -p $(rpt_dir) $(net_dir)
	dc_shell-xg-t -64 -topo -f synth.tcl | tee $(rpt_dir)/$(proj).out
	rm -f command.log *-verilog.pvl *-verilog.syn *.mr default.svf
	$(get_rep) $@ $(rpt_dir)
	rm -rf dwsvf_*

# ----
#  Other Targets
# --
clean:
	rm -f $(rpt_dir)/$(proj).out
	rm -f $(rpt_dir)/$(proj)_syn_wrapper.*
	rm -f $(wrp_dir)/*
	rm -f $(net_dir)/$(proj)_syn_wrapper.*
	rm -f *.mr *.syn *.pvl default.svf *.log
	rm -f *~

