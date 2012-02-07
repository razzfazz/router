##########################################################################################
# Variables common to all RM scripts
# Script: common_setup.tcl
# Version: D-2010.03 (March 29, 2010)
# Copyright (C) 2007-2010 Synopsys, Inc. All rights reserved.
##########################################################################################

##########################################
#Ted's changes
#-src path not relative
#-tsmc library path not relative
#-dont_use.tcl is written by me, based on the tsmc library release notes
##########################################

set DESIGN_NAME                   "router_wrap"  ;#  The name of the top-level design

set DESIGN_REF_DATA_PATH          "/home/qtedq/router/trunk/src"  ;
                                       #  Absolute path prefix variable for library/design data.
                                       #  Use this variable to prefix the common absolute path to 
                                       #  the common variables defined below.
                                       #  Absolute paths are mandatory for hierarchical RM flow.

##########################################################################################
# Hierarchical Flow Design Variables
##########################################################################################

set HIERARCHICAL_DESIGNS           "" ;# List of hierarchical block design names "DesignA DesignB" ...
set HIERARCHICAL_CELLS             "" ;# List of hierarchical block cell instance names "u_DesignA u_DesignB" ...

##########################################################################################
# Library Setup Variables
##########################################################################################

# For the following variables, use a blank space to separate multiple entries
# Example: set TARGET_LIBRARY_FILES "lib1.db lib2.db lib3.db"

set ADDITIONAL_SEARCH_PATH        "/home/qtedq/router/trunk/synopsys_reference_tsmc/rm_setup /home/shared/pdks/ST/cmos045/CMOS045_SC_14_CORE_LS_SNPS-AVT-CDS_3.0/libs /home/shared/pdks/ST/cmos045/CMOS045_SC_14_CLK_LS_SNPS-AVT-CDS_4.0/libs"  ;#  Additional search path to be added to the default search path

set TARGET_LIBRARY_FILES          "CMOS045_SC_14_CORE_LS_wc_0.90V_125C.db CMOS045_SC_14_CLK_LS_wc_0.90V_125C.db "  ;#  Target technology logical libraries
set ADDITIONAL_LINK_LIB_FILES     ""  ;#  Extra link logical libraries not included in TARGET_LIBRARY_FILES

set MIN_LIBRARY_FILES             "CMOS045_SC_14_CORE_LS_wc_0.90V_125C.db CMOS045_SC_14_CORE_LS_bc_1.26V_125C.db CMOS045_SC_14_CLK_LS_wc_0.90V_125C.db CMOS045_SC_14_CLK_LS_nom_1.15V_25C.db "  ;#  List of max min library pairs "max1 min1 max2 min2 max3 min3"...

set MW_REFERENCE_LIB_DIRS         "/home/shared/pdks/ST/cmos045/CMOS045_SC_14_CORE_LS_SNPS-AVT-CDS_3.0/SYNOPSYS/PR/CMOS045_SC_14_CORE_LS/ /home/shared/pdks/ST/cmos045/CMOS045_SC_14_CLK_LS_SNPS-AVT-CDS_4.0/SYNOPSYS/PR/CMOS045_SC_14_CLK_LS/"  ;#  Milkyway reference libraries (include IC Compiler ILMs here)

set MW_REFERENCE_CONTROL_FILE     ""  ;#  Reference Control file to define the MW ref libs

set TECH_FILE                     "/home/shared/pdks/ST/cmos045-4.0/cva/TECH/tech.tf"  ;#  Milkyway technology file
set MAP_FILE                      "/home/shared/pdks/ST/cmos045-4.0/cva/TECH/mapfile"  ;#  Mapping file for TLUplus
set TLUPLUS_MAX_FILE              "/home/shared/pdks/ST/cmos045-4.0/cva/TECH/tluplus_rcmax"  ;#  Max TLUplus file
set TLUPLUS_MIN_FILE              "/home/shared/pdks/ST/cmos045-4.0/cva/TECH/tluplus_rcmin"  ;#  Min TLUplus file


set MW_POWER_NET                "VDD" ;#
set MW_POWER_PORT               "VDD" ;#
set MW_GROUND_NET               "VSS" ;#
set MW_GROUND_PORT              "VSS" ;#

set MIN_ROUTING_LAYER            "M1"   ;# Min routing layer
set MAX_ROUTING_LAYER            "M7"   ;# Max routing layer

set LIBRARY_DONT_USE_FILE        "dont_use.tcl"   ;# Tcl file with library modifications for dont_use

##########################################################################################
# Multi-Voltage Common Variables
#
# Define the following MV common variables for the RM scripts for multi-voltage flows.
# Use as few or as many of the following definitions as needed by your design.
##########################################################################################

set PD1                          ""           ;# Name of power domain/voltage area  1
set PD1_CELLS                    ""           ;# Instances to include in power domain/voltage area 1
set VA1_COORDINATES              {}           ;# Coordinates for voltage area 1
set MW_POWER_NET1                "VDD1"       ;# Power net for voltage area 1
set MW_POWER_PORT1               "VDD"        ;# Power port for voltage area 1

set PD2                          ""           ;# Name of power domain/voltage area  2
set PD2_CELLS                    ""           ;# Instances to include in power domain/voltage area 2
set VA2_COORDINATES              {}           ;# Coordinates for voltage area 2
set MW_POWER_NET2                "VDD2"       ;# Power net for voltage area 2
set MW_POWER_PORT2               "VDD"        ;# Power port for voltage area 2

set PD3                          ""           ;# Name of power domain/voltage area  3
set PD3_CELLS                    ""           ;# Instances to include in power domain/voltage area 3
set VA3_COORDINATES              {}           ;# Coordinates for voltage area 3
set MW_POWER_NET3                "VDD3"       ;# Power net for voltage area 3
set MW_POWER_PORT3               "VDD"        ;# Power port for voltage area 3

set PD4                          ""           ;# Name of power domain/voltage area  4
set PD4_CELLS                    ""           ;# Instances to include in power domain/voltage area 4
set VA4_COORDINATES              {}           ;# Coordinates for voltage area 4
set MW_POWER_NET4                "VDD4"       ;# Power net for voltage area 4
set MW_POWER_PORT4               "VDD"        ;# Power port for voltage area 4
