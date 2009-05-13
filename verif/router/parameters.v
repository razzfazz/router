// $Id: whr_constants.v 1224 2009-04-30 22:04:24Z dub $

/*
Copyright (c) 2007, Trustees of Leland Stanford Junior University
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list
of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this 
list of conditions and the following disclaimer in the documentation and/or 
other materials provided with the distribution.
Neither the name of the Stanford University nor the names of its contributors 
may be used to endorse or promote products derived from this software without 
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR 
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON 
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// router configuration options

// select network topology
parameter network_topology = `NETWORK_TOPOLOGY_MESH;

// flit buffer entries per VC
parameter num_flit_buffers = 4;

// maximum number of packets that can be in a given VC buffer simultaneously
parameter num_header_buffers = 2;

// number of message classes (e.g. request, reply)
parameter num_message_classes = 1;

// number of resource classes (e.g. minimal, adaptive)
parameter num_resource_classes = 1;

// number of VCs per class
parameter num_vcs_per_class = 1;

// total number of nodes
parameter num_nodes = 64;

// number of dimensions in network
parameter num_dimensions = 2;

// number of nodes per router (a.k.a. concentration factor)
parameter num_nodes_per_router = 4;

// select packet format
parameter packet_format = `PACKET_FORMAT_EXPLICIT_LENGTH;

// maximum payload length (in flits)
parameter max_payload_length = 4;

// minimum payload length (in flits)
parameter min_payload_length = 0;

// width of flit payload data
parameter flit_data_width = 64;

// enable performance counter
parameter perf_ctr_enable = 1;

// width of each counter
parameter perf_ctr_width = 32;

// include error checking logic
parameter checker_enable = 1;
parameter checker_capture_mode = `CHECKER_CAPTURE_MODE_NO_HOLD;

// select whether to set a packet's outgoing VC ID at the input or output 
// controller
parameter track_vcs_at_output = 1;

// select router implementation
parameter router_type = `ROUTER_TYPE_WORMHOLE;

// select order of dimension traversal
parameter dimension_order = `DIMENSION_ORDER_ASCENDING;

// select method for credit signaling from output to input controller
parameter credit_handling_type = `CREDIT_HANDLING_TYPE_PUSH;

// select implementation variant for header FIFO
parameter header_fifo_type = `FIFO_TYPE_INDEXED;

// select implementation variant for flit buffer register file
parameter fbf_regfile_type = `REGFILE_TYPE_FF_2D;

// select implementation variant for VC allocator
parameter vc_allocator_type = `VC_ALLOCATOR_TYPE_WF_BASE;

// select which arbiter type to use for VC allocator
parameter vc_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;

// select implementation variant for switch allocator
parameter sw_allocator_type = `SW_ALLOCATOR_TYPE_SEP_IF;

// select which arbiter type to use for switch allocator
parameter sw_arbiter_type = `ARBITER_TYPE_ROUND_ROBIN;

// select speculation level for switch allocator
parameter sw_spec_level = `SW_SPEC_LEVEL_CONFL_NONSPEC_REQ_MASKS;

// select implementation variant for control crossbar
parameter ctrl_crossbar_type = `CROSSBAR_TYPE_TRISTATE;

// select implementation variant for data crossbar
parameter data_crossbar_type = `CROSSBAR_TYPE_TRISTATE;

parameter reset_type = `RESET_TYPE_ASYNC;  
