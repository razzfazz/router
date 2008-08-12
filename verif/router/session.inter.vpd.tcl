# Begin_DVE_Session_Save_Info
# DVE wave signals session
# Saved on Tue Aug 12 11:01:55 2008
# 96 signals
# End_DVE_Session_Save_Info

# DVE version: Y-2006.06-SP1_Full64
# DVE build date: Apr 18 2007 09:55:24


set {Group1} {Group1}
if {[gui_sg_is_group -name {Group1}]} {
    set {Group1} [gui_sg_generate_new_name]
}

gui_sg_addsignal -group "${Group1}" { {testbench.flit_valid_in_ip[0:4]} {testbench.flit_vc_in_ip[0:9]} {testbench.flit_head_in_ip[0:4]} {testbench.flit_tail_in_ip[0:4]} {testbench.flit_data_in_ip[0:63]} {testbench.flit_data_in_ip[64:127]} {testbench.flit_data_in_ip[128:191]} {testbench.flit_data_in_ip[192:255]} {testbench.flit_data_in_ip[256:319]} {testbench.cred_valid_out_ip[0:4]} {testbench.cred_vc_out_ip[0:9]} }
set {Group2} {Group2}
if {[gui_sg_is_group -name {Group2}]} {
    set {Group2} [gui_sg_generate_new_name]
}

gui_sg_addsignal -group "${Group2}" { {testbench.flit_valid_out_op[0:4]} {testbench.flit_vc_out_op[0:9]} {testbench.flit_head_out_op[0:4]} {testbench.flit_tail_out_op[0:4]} {testbench.flit_data_out_op[0:63]} {testbench.flit_data_out_op[64:127]} {testbench.flit_data_out_op[128:191]} {testbench.flit_data_out_op[192:255]} {testbench.flit_data_out_op[256:319]} {testbench.cred_valid_in_op[0:4]} {testbench.cred_vc_in_op[0:9]} }
set {Group3} {Group3}
if {[gui_sg_is_group -name {Group3}]} {
    set {Group3} [gui_sg_generate_new_name]
}

gui_sg_addsignal -group "${Group3}" { {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.buff_read_addr[0:2]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.buff_write_addr[0:2]} {testbench.rtr.ips[0].ipc.fbf.write_address[0:4]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.flit_sent} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.fbc_empty} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.flit_sent} {testbench.rtr.ips[0].ipc.fbf.storage[0:31][0:63]} }
set {Group4} {Group4}
if {[gui_sg_is_group -name {Group4}]} {
    set {Group4} [gui_sg_generate_new_name]
}

gui_sg_addsignal -group "${Group4}" { {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.port_q[0:4]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.vcs_q[0:3]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.vcs_s[0:3]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.mask_ovc[0:3]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.get_next_header} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.rtl_next_vcs[0:3]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.vc_gnt_masked} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.vc_gnt_masked_ovc[0:3]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.vc_gnt_ovc[0:3]} {testbench.rtr.ops[1].opc.set_elig_ovc[0:3]} {testbench.rtr.ops[1].opc.reset_elig_ovc[0:3]} {testbench.rtr.ops[1].opc.elig_ovc_q[0:3]} {testbench.rtr.ops[1].opc.elig_ovc_s[0:3]} {testbench.rtr.ops[1].opc.elig_ovc[0:3]} {testbench.rtr.ops[1].opc.ovcs[0].head_free} {testbench.rtr.ops[1].opc.ovcs[0].hct.true_count[0:2]} {testbench.rtr.ops[1].opc.ovcs[0].hct.error} {testbench.rtr.elig_op_ovc[0:19]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.elig_ovc[0:3]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_op[0:4]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_unallocated} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_op_ovc[0:19]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_allocated} {testbench.rtr.free_op_ivc[0:19]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_ovc[0:3]} {testbench.rtr.free_op_ovc[0:19]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_plus1_allocated} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_plus1_op_ovc[0:19]} {testbench.rtr.free_plus1_op_ovc[0:19]} {testbench.rtr.ips[0].ipc.ivcs[0].ivcc.free_plus1_ovc[0:3]} }
gui_set_radix -radix {decimal} -signals {{testbench.rtr.ips[0].ipc.ivcs[0].ivcc.mask_ovc[0:3]}}
gui_set_radix -radix {unsigned} -signals {{testbench.rtr.ips[0].ipc.ivcs[0].ivcc.mask_ovc[0:3]}}
set {Group5} {Group5}
if {[gui_sg_is_group -name {Group5}]} {
    set {Group5} [gui_sg_generate_new_name]
}

gui_sg_addsignal -group "${Group5}" { {testbench.ips[0].ivcs[0].ps.sw_gnt} {testbench.ips[0].ivcs[0].ps.active_q} {testbench.ips[0].ivcs[0].ps.sw_req} {testbench.ips[0].ivcs[0].ps.active_s} {testbench.ips[0].ivcs[0].ps.vc_gnt} {testbench.ips[0].elig_ivc[0:3]} {testbench.ips[0].ivcs[0].ps.vc_req} {testbench.ips[0].free_ivc[0:3]} {testbench.ips[0].ivcs[0].ps.flit_count_max} {testbench.ips[0].ivcs[0].ps.flit_count_zero} {testbench.ips[0].opcc.reset_elig_ovc[0:3]} {testbench.ips[0].opcc.set_elig_ovc[0:3]} {testbench.ips[0].vc_req_ivc[0:3]} {testbench.ips[0].vc_gnt_ivc[0:3]} }
set {Group6} {Group6}
if {[gui_sg_is_group -name {Group6}]} {
    set {Group6} [gui_sg_generate_new_name]
}

gui_sg_addsignal -group "${Group6}" { {testbench.ips[0].ivcs[0].ps.active_q} {testbench.ips[0].ivcs[0].ps.active_s} {testbench.ips[0].ivcs[0].ps.vc_req} {testbench.ips[0].ivcs[0].ps.vc_gnt} {testbench.ips[0].ivcs[0].ps.sw_req} {testbench.ips[0].ivcs[0].ps.sw_gnt} {testbench.ips[0].ivcs[0].ps.packet_count_q[0:31]} {testbench.ips[0].ivcs[0].ps.packet_count_s[0:31]} {testbench.ips[0].ivcs[0].ps.packet_count_zero} {testbench.ips[0].opcc.vc_gnt_ovc[0:3]} {testbench.ips[0].ivcs[0].ps.flit_count_max} {testbench.ips[0].opcc.free_plus1_ovc[0:3]} {testbench.ips[0].ivcs[0].ps.flit_count_zero} {testbench.ips[0].opcc.reset} {testbench.ips[0].opcc.free_ovc[0:3]} {testbench.ips[0].opcc.flit_vc_in[0:1]} {testbench.ips[0].opcc.cred_vc_in[0:1]} {testbench.ips[0].opcc.free_ivc[0:3]} {testbench.ips[0].opcc.cred_valid_in} {testbench.ips[0].opcc.flit_valid_in} {testbench.ips[0].opcc.clk} {testbench.ips[0].opcc.elig_ovc[0:3]} {testbench.ips[0].opcc.flit_tail_in} }
gui_set_time_units 1ns
if {[string first "Wave" [gui_get_current_window -view]]==0} { 
set Wave.1 [gui_get_current_window -view] 
} else {
gui_open_window Wave
set Wave.1 [ gui_get_current_window -view ]
}
gui_marker_create -id ${Wave.1} M1 254
gui_marker_select -id ${Wave.1} {  M1 }
gui_marker_set_ref -id ${Wave.1}  C1
gui_wv_zoom_timerange -id ${Wave.1} 210 295
gui_list_add_group -id ${Wave.1} -after {New Group} "{${Group1}}"
gui_list_add_group -id ${Wave.1} -after {New Group} "{${Group2}}"
gui_list_add_group -id ${Wave.1} -after {New Group} "{${Group3}}"
gui_list_add_group -id ${Wave.1} -after {New Group} "{${Group4}}"
gui_list_add_group -id ${Wave.1} -after {New Group} "{${Group5}}"
gui_list_add_group -id ${Wave.1} -after {New Group} "{${Group6}}"
gui_list_collapse -id Wave.1 Group3
gui_list_collapse -id Wave.1 Group4
gui_list_collapse -id Wave.1 Group5
gui_list_select -id ${Wave.1} {{testbench.ips[0].ivcs[0].ps.sw_req} {testbench.ips[0].ivcs[0].ps.sw_gnt} }
gui_seek_criteria -id ${Wave.1} {Any Edge}


gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_valid_in_ip[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_valid_in_ip[0:4]} -index 1 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_vc_in_ip[0:9]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_vc_in_ip[0:9]} -index 2 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_head_in_ip[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_head_in_ip[0:4]} -index 3 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_tail_in_ip[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_tail_in_ip[0:4]} -index 4 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_in_ip[0:63]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_in_ip[0:63]} -index 5 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_in_ip[64:127]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_in_ip[64:127]} -index 6 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_in_ip[128:191]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_in_ip[128:191]} -index 7 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_in_ip[192:255]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_in_ip[192:255]} -index 8 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_in_ip[256:319]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_in_ip[256:319]} -index 9 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.cred_valid_out_ip[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.cred_valid_out_ip[0:4]} -index 10 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.cred_vc_out_ip[0:9]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.cred_vc_out_ip[0:9]} -index 11 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_valid_out_op[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_valid_out_op[0:4]} -index 13 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_vc_out_op[0:9]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_vc_out_op[0:9]} -index 14 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_head_out_op[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_head_out_op[0:4]} -index 15 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_tail_out_op[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_tail_out_op[0:4]} -index 16 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_out_op[0:63]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_out_op[0:63]} -index 17 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_out_op[64:127]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_out_op[64:127]} -index 18 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_out_op[128:191]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_out_op[128:191]} -index 19 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_out_op[192:255]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_out_op[192:255]} -index 20 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.flit_data_out_op[256:319]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.flit_data_out_op[256:319]} -index 21 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.cred_valid_in_op[0:4]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.cred_valid_in_op[0:4]} -index 22 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.cred_vc_in_op[0:9]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.cred_vc_in_op[0:9]} -index 23 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.active_q}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.active_q} -index 28 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.active_s}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.active_s} -index 29 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.vc_req}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.vc_req} -index 30 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.vc_gnt}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.vc_gnt} -index 31 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.sw_req}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.sw_req} -index 32 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.sw_gnt}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.sw_gnt} -index 33 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.packet_count_q[0:31]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.packet_count_q[0:31]} -index 34 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.packet_count_s[0:31]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.packet_count_s[0:31]} -index 35 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.packet_count_zero}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.packet_count_zero} -index 36 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.vc_gnt_ovc[0:3]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.vc_gnt_ovc[0:3]} -index 37 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.flit_count_max}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.flit_count_max} -index 38 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.free_plus1_ovc[0:3]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.free_plus1_ovc[0:3]} -index 39 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].ivcs[0].ps.flit_count_zero}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].ivcs[0].ps.flit_count_zero} -index 40 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.reset}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.reset} -index 41 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.free_ovc[0:3]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.free_ovc[0:3]} -index 42 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.flit_vc_in[0:1]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.flit_vc_in[0:1]} -index 43 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.cred_vc_in[0:1]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.cred_vc_in[0:1]} -index 44 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.free_ivc[0:3]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.free_ivc[0:3]} -index 45 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.cred_valid_in}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.cred_valid_in} -index 46 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.flit_valid_in}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.flit_valid_in} -index 47 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.clk}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.clk} -index 48 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.elig_ovc[0:3]}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.elig_ovc[0:3]} -index 49 
gui_set_display_scheme -id ${Wave.1} -scheme preference -signal {{testbench.ips[0].opcc.flit_tail_in}}
gui_list_set_height -id ${Wave.1} -height 25  -name {testbench.ips[0].opcc.flit_tail_in} -index 50 

gui_marker_move -id ${Wave.1} {C1} 266
