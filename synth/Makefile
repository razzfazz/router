#
# Synthesis Makefile
#
SHELL = /bin/sh

# globals
proj := router

# clear suffix rules
.SUFFIXES: 


# ----
#  Directories
# --
rpt_dir := rpt
net_dir := net
rtl_dir := ../src
# ----
#  Tools
# --
wrap := ./scripts/synWrapper.pl
# ----
#  Synthesis Targets
# --

default: $(proj)

all: $(proj)

$(proj):
	$(wrap) -module $(proj) -input $(rtl_dir)/$(proj).v\
          -output wrappers/$(proj)_syn_wrapper.v 
	dc_shell-xg-t -f $(proj).tcl > $(rpt_dir)/$(proj).lis
	rm -f command.log *-verilog.* *.mr
	scripts/getrep.pl $@
	rm -rf dwsvf_*

# ----
#  Other Targets
# --
clean:
	rm -f $(rpt_dir)/*
	rm -f $(net_dir)/*
	rm -f *~

