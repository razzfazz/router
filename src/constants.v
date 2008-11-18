`ifndef _CONSTANTS_V_
`define _CONSTANTS_V_

//------------------------------------------------------------------------------
// network topologies
//------------------------------------------------------------------------------

// mesh
`define NETWORK_TOPOLOGY_MESH  0

// flattened butterfly
`define NETWORK_TOPOLOGY_FBFLY 1


//------------------------------------------------------------------------------
// routing function types
//------------------------------------------------------------------------------

// within a dimension, route based on relation between current and destination 
// address (one port each for greater and smaller addresses)
`define ROUTING_FUNCTION_TYPE_BY_RELATION   0

// within a dimension, route based on difference between current and destinatio
// address (one port for each address other than current one)  
`define ROUTING_FUNCTION_TYPE_BY_DIFFERENCE 1


//------------------------------------------------------------------------------
// reset handling
//------------------------------------------------------------------------------

// no reset
`define RESET_TYPE_NONE  0

// asynchronous reset
`define RESET_TYPE_ASYNC 1

// synchronous reset
`define RESET_TYPE_SYNC  2


//------------------------------------------------------------------------------
// arbiter types
//------------------------------------------------------------------------------

// round-robin arbiter
`define ARBITER_TYPE_ROUND_ROBIN 0

// matrix arbiter
`define ARBITER_TYPE_MATRIX      1


//------------------------------------------------------------------------------
// error checker capture more
//------------------------------------------------------------------------------

// don't hold errors
`define CHECKER_CAPTURE_MODE_NO_HOLD    0

// capture first error only (subsequent errors are blocked)
`define CHECKER_CAPTURE_MODE_HOLD_FIRST 1

// capture all errors
`define CHECKER_CAPTURE_MODE_HOLD_ALL   2


//------------------------------------------------------------------------------
// crossbar implementation variants
//------------------------------------------------------------------------------

// tristate-based
`define CROSSBAR_TYPE_TRISTATE 0

// mux-based
`define CROSSBAR_TYPE_MUX      1


//------------------------------------------------------------------------------
// register file implemetation variants
//------------------------------------------------------------------------------

// 2D array implemented using flipflops
`define REGFILE_TYPE_FF_2D          0

// 1D array of flipflops, read using a combinational mux
`define REGFILE_TYPE_FF_1D_MUX      1

// 1D array of flipflops, read using a tristate mux
`define REGFILE_TYPE_FF_1D_TRISTATE 2


//------------------------------------------------------------------------------
// FIFO implementation variants
//------------------------------------------------------------------------------

// shift register with moving write pointer, fixed read pointer
`define FIFO_TYPE_SHIFTING 0

// set of registers with moving read and write pointer
`define FIFO_TYPE_INDEXED  1


//------------------------------------------------------------------------------
// directions of rotation
//------------------------------------------------------------------------------
`define ROTATE_DIR_LEFT  0
`define ROTATE_DIR_RIGHT 1


//------------------------------------------------------------------------------
// wavefront allocator implementation variants
//------------------------------------------------------------------------------

// variant which uses multiplexers to permute inputs and outputs based on 
// priority
`define WF_ALLOCATOR_TYPE_MUX  0

// variant which replicates the entire allocation logic for the different 
// priorities and selects the result from the appropriate one
`define WF_ALLOCATOR_TYPE_REP  1

// variant implementing a Diagonal Propagation Arbiter as described in Hurt et 
// al, "Design and Implementation of High-Speed Symmetric Crossbar Schedulers"
`define WF_ALLOCATOR_TYPE_DPA  2

// variant which rotates inputs and outputs based on priority
`define WF_ALLOCATOR_TYPE_ROT  3

// variant which uses wraparound (forming a false combinational loop) as 
// described in Dally et al, "Principles and Practices of Interconnection 
// Networks"
`define WF_ALLOCATOR_TYPE_LOOP 4


//------------------------------------------------------------------------------
// credit handling implementation variants
//------------------------------------------------------------------------------

// indicate credit level to input side
`define CREDIT_HANDLING_TYPE_LEVEL 0

// push credits to input side one by one
`define CREDIT_HANDLING_TYPE_PUSH  1


//------------------------------------------------------------------------------
// implementation variants for credit checking
//------------------------------------------------------------------------------

// check that credit is available at all potential output VCs before issuing 
// request
`define SW_SPEC_CRED_CHECK_ALL_PRE  0

// check that credit is available at all potential output VCs in parallel with 
// allocation, then mask grants
`define SW_SPEC_CRED_CHECK_ALL_POST 1

// check that credit is available at slected output VC while doing allocation, 
// then mask grants
`define SW_SPEC_CRED_CHECK_SEL_POST 2


//------------------------------------------------------------------------------
// VC allocator implementation variants
//------------------------------------------------------------------------------

// separable, input-first
`define VC_ALLOCATOR_TYPE_SEP_IF 0

// separable, output-first
`define VC_ALLOCATOR_TYPE_SEP_OF 1


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
