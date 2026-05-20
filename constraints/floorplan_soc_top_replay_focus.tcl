# Focused floorplan for the load-control early replay timing experiment.
# Source this after opt_design and before place_design.
#
# This deliberately avoids constraining the whole CPU or DMEM.  The previous
# broad floorplan hurt the load/EX cone.  This pblock only nudges the replay /
# redirect control cells that appeared on the WNS -0.011 ns path.

set pblock_name "pblock_replay_redirect_focus"
set pblock_cells [list]

proc yl3_collect_cells {patterns} {
    set result [list]
    foreach pattern $patterns {
        set matched [get_cells -hierarchical -quiet -filter "NAME =~ $pattern"]
        if {[llength $matched] == 0} {
            puts "INFO: replay_focus no cells matched $pattern"
        } else {
            foreach cell $matched {
                lappend result $cell
            }
        }
    }
    return [lsort -unique $result]
}

set pblock_cells [yl3_collect_cells [list \
    "*u_core/ex_mem_rd_reg*" \
    "*u_core/redirect_from_replay*" \
    "*u_core/redirect_valid*" \
    "*u_core/redirect_pc_q*" \
    "*u_core/redirect_taken_q*" \
    "*u_core/redirect_branch_mispredict*" \
    "*u_core/redirect_jump_flush*" \
    "*u_core/ctrl_replay*" \
    "*u_core/ctrl_load_pending*" \
    "*u_core/branch_taken*" \
    "*u_core/u_branch_predictor/*ctrl_replay*" \
    "*u_core/u_branch_predictor/*redirect*" \
    "*u_core/u_branch_predictor/*update_taken_q_i*" \
    "*u_core/u_branch_predictor/*update_taken_q_reg_i*" \
    "*u_core/u_branch_predictor/*control_load_resp_dep*" \
    "*u_core/u_branch_predictor/*product_uu_i*" \
    "*u_core/u_multiplier/*forward_a*" \
    "*u_core/u_multiplier/*branch_mispredict*" \
    "*u_core/u_multiplier/*redirect_from_replay*" \
]]

if {[llength $pblock_cells] == 0} {
    puts "WARNING: floorplan_soc_top_replay_focus found no cells; skipping pblock"
    return
}

if {[llength [get_pblocks -quiet $pblock_name]] == 0} {
    create_pblock $pblock_name
}

set pblock_obj [get_pblocks $pblock_name]
add_cells_to_pblock $pblock_obj $pblock_cells

# The failing path in the unconstrained ExtraNetDelay run was clustered around
# SLICE_X34..X41 and Y14..Y21.  Use a moderate box around that cluster rather
# than a tight pblock, so placer still has enough legal alternatives.
resize_pblock $pblock_obj -add {SLICE_X28Y8:SLICE_X54Y42}

puts "Applied $pblock_name to [llength $pblock_cells] cells"
