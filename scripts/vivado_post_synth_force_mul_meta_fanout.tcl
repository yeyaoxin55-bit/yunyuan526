proc force_max_fanout_on_net {net_pattern fanout_limit} {
    set nets [get_nets -hier -quiet $net_pattern]
    if {[llength $nets] == 0} {
        puts "POST_SYNTH_HOOK_MISSING_NET=$net_pattern"
        return
    }

    foreach net $nets {
        if {[catch {set_property FORCE_MAX_FANOUT $fanout_limit $net} msg]} {
            puts "POST_SYNTH_HOOK_FORCE_MAX_FANOUT_FAILED=[get_property NAME $net]:$msg"
        } else {
            puts "POST_SYNTH_HOOK_FORCE_MAX_FANOUT=[get_property NAME $net]:$fanout_limit"
        }
    }
}

# QoR RQS_TIMING-3 repeatedly flags the control cone launched by
# mul_meta_valid_pipe_reg[0]. Apply this only in fast timing experiments.
force_max_fanout_on_net {*mul_meta_valid_pipe_reg_n_0_*} 32
force_max_fanout_on_net {*gen_rv64_partial_pipeline.valid_pipe_reg*} 32
force_max_fanout_on_net {*u_multiplier/if_id_pred_target} 32
force_max_fanout_on_net {*u_multiplier/p_20_in} 32
force_max_fanout_on_net {*u_multiplier/fetch_pc_q} 32
