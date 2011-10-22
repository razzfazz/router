// $Id$

/*
 Copyright (c) 2007-2011, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

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

//==============================================================================
// constants related to test chip support logic
//==============================================================================


//------------------------------------------------------------------------------
// network pseudo-node register address declarations
//------------------------------------------------------------------------------

`define CFG_ADDR_NODE_CTRL            0
`define CFG_ADDR_NODE_STATUS          1
`define CFG_ADDR_NODE_FLIT_SIG        2
`define CFG_ADDR_NODE_LFSR_SEED       3
`define CFG_ADDR_NODE_NUM_PACKETS     4
`define CFG_ADDR_NODE_ARRIVAL_THRESH  5
`define CFG_ADDR_NODE_PLENGTH_THRESHS 6
`define CFG_ADDR_NODE_PLENGTH_VALS    7
`define CFG_ADDR_NODE_MC_THRESHS      8
`define CFG_ADDR_NODE_RC_THRESHS      9


//------------------------------------------------------------------------------
// network pseudo-node controller register address declarations
//------------------------------------------------------------------------------

`define CFG_ADDR_NCTL_CTRL   0
`define CFG_ADDR_NCTL_STATUS 1


//------------------------------------------------------------------------------
// network channel tester register address declarations
//------------------------------------------------------------------------------

`define CFG_ADDR_CTST_CTRL            0
`define CFG_ADDR_CTST_STATUS          1
`define CFG_ADDR_CTST_ERRORS          2
`define CFG_ADDR_CTST_TEST_DURATION   3
`define CFG_ADDR_CTST_WARMUP_DURATION 4
`define CFG_ADDR_CTST_CAL_INTERVAL    5
`define CFG_ADDR_CTST_CAL_DURATION    6
`define CFG_ADDR_CTST_PATTERN_ADDR    7
`define CFG_ADDR_CTST_PATTERN_DATA    8
