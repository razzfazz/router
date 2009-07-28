// $Id: vcr_constants.v 1145 2009-03-06 18:57:25Z qtedq $

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

// global constant definitions

`ifndef _VCR_CONSTANTS_V_
`define _VCR_CONSTANTS_V_

//------------------------------------------------------------------------------
// credit handling implementation variants
//------------------------------------------------------------------------------

// indicate credit level to input side
`define CREDIT_HANDLING_TYPE_LEVEL 0

// push credits to input side one by one
`define CREDIT_HANDLING_TYPE_PUSH  1


//------------------------------------------------------------------------------
// VC allocator implementation variants
//------------------------------------------------------------------------------

// separable, input-first
`define VC_ALLOCATOR_TYPE_SEP_IF  0

// separable, output-first
`define VC_ALLOCATOR_TYPE_SEP_OF  1

// wavefront-based
// (note: add WF_ALLOCATOR_TYPE_* constant to select wavefront variant)
`define VC_ALLOCATOR_TYPE_WF_BASE 2


//------------------------------------------------------------------------------
// switch allocator implementation variants
//------------------------------------------------------------------------------

// separable, input-first
`define SW_ALLOCATOR_TYPE_SEP_IF  0

// separable, output-first
`define SW_ALLOCATOR_TYPE_SEP_OF  1

// wavefront-based
// (note: add WF_ALLOCATOR_TYPE_* constant to select wavefront variant)
`define SW_ALLOCATOR_TYPE_WF_BASE 2


//------------------------------------------------------------------------------
// speculation levels for switch allocator
//------------------------------------------------------------------------------

// disable speculative switch allocation
`define SW_SPEC_LEVEL_NONE                    0

// only use speculative grants if no non-speculative requests/grants present
`define SW_SPEC_LEVEL_ANY_NONSPEC_MASKS       1

// use speculative grants when not conflicting with non-spec requests
`define SW_SPEC_LEVEL_CONFL_NONSPEC_REQ_MASKS 2

// use speculative grants when not conflicting with non-spec grants
`define SW_SPEC_LEVEL_CONFL_NONSPEC_GNT_MASKS 3


`endif
