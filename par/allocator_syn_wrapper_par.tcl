# ----------------------------------------------------------------------
#
#  File: allocator_syn_wrapper_par.tcl
#
# ----------------------------------------------------------------------

source ./setup_fe_libs.tcl
source ./setup_fe_mem_libs.tcl
source allocator_syn_wrapper_setup.tcl

commitConfig

# Create Power Structures
globalNetConnect vdd -type tiehi
globalNetConnect gnd -type tielo

globalNetConnect vdd -type pgpin -pin VDD -override
globalNetConnect gnd -type pgpin -pin VSS -override

# Restore floorplan
# loadFPlan allocator_syn_wrapper.floorplan

# Create Initial Floorplan
#floorplan -r 1.25 0.93 5 5 5 5 

# Initial Place and Optimization
selectObject Module allocator_syn_wrapper
ungroup

# Group IR with Modules
# createInstGroup alu0Group -density 0.75 -AR 0.8
# addInstToInstGroup alu0Group ALU0
# addInstToInstGroup alu0Group ALU0IR
# 
# createInstGroup alu1Group -density 0.75 -AR 0.8
# addInstToInstGroup alu1Group ALU1
# addInstToInstGroup alu1Group ALU1IR

#modulePlace -congestionDriven\
#  -initFP\
#  -variableCore\
#  -placeBlocksInModule\
#  -effort h\
#  -moduleHalo 2\
#  -halo 2\
#  -maxAR 1000\
#  -minAR 0.05

# Signal Groups


# Power + Gnd 
addRing -nets {gnd vdd } \
 -layer_top METAL7  -layer_bottom METAL7 \
 -layer_left METAL8 -layer_right METAL8 \
 -spacing_top 0.84  -width_top 1 \
 -spacing_bottom 0.84 -width_bottom 1 \
 -spacing_left 0.84 -width_left 1 \
 -spacing_right 0.84 -width_right 1

addStripe -block_ring_top_layer_limit METAL8\
 -xleft_offset 84\
 -max_same_layer_jog_length 0.84\
 -padcore_ring_bottom_layer_limit METAL7\
 -set_to_set_distance 84 \
 -padcore_ring_top_layer_limit METAL8\
 -spacing 0.84\
 -merge_stripes_value 0.23\
 -direction vertical\
 -layer METAL8\
 -block_ring_bottom_layer_limit METAL7\
 -width 1\
 -nets {gnd vdd }\
 -stacked_via_top_layer METAL8\
 -stacked_via_bottom_layer METAL1\
 -snap_wire_center_to_grid Either

# Specify Clock Tree
setCTSMode\
 -moveGate
# -mediumEffort\
# -optAddBuffer

createClockTreeSpec -output par.clk -routeClkNet
specifyClockTree -clkfile par.clk

# Place Design
setPlaceMode -fp -clkGateAware -assignIoPins
placeDesign


# Placement
setPlaceMode -reset
setPlaceMode\
 -doCongOpt\
 -clkGateAware\
 -assignIoPins\
 -congHighEffort
placeDesign

setOptMode -reclaimArea\
  -highEffort\
  -bufferAssignNets\
  -congOpt\
  -noOptimizeFF\
  -simplifyNetlist
optDesign -preCTS 

# Clock Tree Synthesis
setOptMode -reset 
setOptMode -highEffort\
  -noOptimizeFF\
  -reclaimArea\
  -usefulSkew
ckSynthesis

timeDesign -postCTS
setOptMode -reset 
setOptMode -highEffort\
  -reclaimArea\
  -usefulSkew
optDesign  -postCTS -hold -setup 

# Global Place and Route
setNanoRouteMode\
 -envNumberProcessor 2\
 -routeWithTimingDriven true
globalDetailRoute

# Post-Route Optimization
timeDesign -postRoute
setOptMode -reset 
setOptMode -highEffort\
  -reclaimArea\
  -fixFanoutLoad\
  -usefulSkew\
  -noFixDRC
optDesign -postRoute -setup -hold 
optDesign -postRoute -setup -hold -incr

# Output Netlist
saveNetlist allocator_syn_wrapper.v

# Output SDF
setExtractRCMode -detail -noReduce
extractRC

setUseDefaultDelayLimit 5000
delayCal -mergeSetupHold -sdf allocator_syn_wrapper.sdf 

saveDesign "allocator_syn_wrapper.enc"

