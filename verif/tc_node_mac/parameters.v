// $Id$

/*
Copyright (c) 2007-2009, Trustees of The Leland Stanford Junior University
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
parameter topology = `TOPOLOGY_FBFLY;

// flit buffer entries per VC
parameter num_flit_buffers = 8;

// maximum number of packets that can be in a given VC buffer simultaneously
parameter num_header_buffers = 4;

// number of message classes (e.g. request, reply)
parameter num_message_classes = 2;

// number of resource classes (e.g. minimal, adaptive)
parameter num_resource_classes = 2;

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
parameter flit_data_width = 32;

// include error checking logic
parameter error_capture_mode = `ERROR_CAPTURE_MODE_NO_HOLD;

// filter out illegal destination ports
// (the intent is to allow synthesis to optimize away the logic associated with 
// such turns)
parameter restrict_turns = 0;

// enable lookahead routing
parameter lookahead_routing = 1;

// select routing function type
parameter routing_type = `ROUTING_TYPE_DOR;

// select order of dimension traversal
parameter dim_order = `DIM_ORDER_ASCENDING;

parameter reset_type = `RESET_TYPE_ASYNC;  
