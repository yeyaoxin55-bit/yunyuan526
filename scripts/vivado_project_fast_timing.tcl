set stage "synth"
set project_file "D:/Verilog_prj/yunyuan3_rv64/yunyuan3_rv64.xpr"
set top "soc_top"
set out_dir [file normalize "build/vivado_project_fast_timing"]
set jobs 4
set place_directive "Explore"
set generic_overrides [list]
set direct_synth 0
set post_synth_tcl ""
set disable_incremental_checkpoint 1

# Project fast timing stages:
# stage "synth" - open existing project, rerun synth_1, emit reports.
# stage "place" - open existing project, rerun synth_1 and impl_1 to place_design.
for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-stage"} {
        incr i
        set stage [lindex $argv $i]
    } elseif {$key eq "-project"} {
        incr i
        set project_file [file normalize [lindex $argv $i]]
    } elseif {$key eq "-top"} {
        incr i
        set top [lindex $argv $i]
    } elseif {$key eq "-out_dir"} {
        incr i
        set out_dir [file normalize [lindex $argv $i]]
    } elseif {$key eq "-jobs"} {
        incr i
        set jobs [lindex $argv $i]
    } elseif {$key eq "-generic"} {
        incr i
        set generic_arg [lindex $argv $i]
        if {[string first "=" $generic_arg] < 0 && ($i + 1) < [llength $argv]} {
            set generic_value [lindex $argv [expr {$i + 1}]]
            if {![string match "-*" $generic_value]} {
                incr i
                lappend generic_overrides "${generic_arg}=${generic_value}"
            } else {
                lappend generic_overrides $generic_arg
            }
        } else {
            lappend generic_overrides $generic_arg
        }
    } elseif {$key eq "-place_directive"} {
        incr i
        set place_directive [lindex $argv $i]
    } elseif {$key eq "-direct_synth"} {
        incr i
        set direct_synth [lindex $argv $i]
    } elseif {$key eq "-post_synth_tcl"} {
        incr i
        set post_synth_tcl [file normalize [lindex $argv $i]]
    } elseif {$key eq "-allow_incremental_checkpoint"} {
        set disable_incremental_checkpoint 0
    } else {
        puts "ERROR: Unknown argument '$key'"
        exit 1
    }
}

if {$stage ne "synth" && $stage ne "place"} {
    puts "ERROR: -stage must be synth or place"
    exit 1
}
if {![file exists $project_file]} {
    puts "ERROR: Missing Vivado project '$project_file'"
    exit 1
}
if {$post_synth_tcl ne "" && ![file exists $post_synth_tcl]} {
    puts "ERROR: Missing post-synth Tcl hook '$post_synth_tcl'"
    exit 1
}

file mkdir $out_dir
set_param general.maxThreads $jobs

proc write_report_safe {description command fallback_command} {
    if {[catch {uplevel 1 $command} msg]} {
        puts "WARNING: $description failed: $msg"
        if {$fallback_command ne ""} {
            if {[catch {uplevel 1 $fallback_command} fallback_msg]} {
                puts "WARNING: $description fallback failed: $fallback_msg"
            }
        }
    }
}

proc emit_timing_reports {out_dir suffix} {
    report_utilization -file [file join $out_dir "utilization_${suffix}.rpt"]
    report_timing_summary -max_paths 50 -file [file join $out_dir "timing_summary_${suffix}.rpt"]
    report_timing -max_paths 80 -sort_by group -path_type full -file [file join $out_dir "timing_paths_${suffix}.rpt"]
    report_clocks -file [file join $out_dir "clocks_${suffix}.rpt"]
    write_report_safe "high fanout report" \
        {report_high_fanout_nets -fanout_greater_than 64 -max_nets 100 -file [file join $out_dir "high_fanout_${suffix}.rpt"]} \
        {report_high_fanout_nets -file [file join $out_dir "high_fanout_${suffix}.rpt"]}
    write_report_safe "control sets report" \
        {report_control_sets -file [file join $out_dir "control_sets_${suffix}.rpt"]} \
        ""
    if {[llength [info commands report_design_analysis]] > 0} {
        write_report_safe "design analysis report" \
            {report_design_analysis -timing -logic_level_distribution -file [file join $out_dir "design_analysis_${suffix}.rpt"]} \
            {report_design_analysis -file [file join $out_dir "design_analysis_${suffix}.rpt"]}
    }
    if {[llength [info commands report_qor_suggestions]] > 0} {
        write_report_safe "QoR suggestions report" \
            {report_qor_suggestions -file [file join $out_dir "qor_suggestions_${suffix}.rpt"]} \
            ""
    }
    if {[llength [info commands report_dsp_utilization]] > 0} {
        write_report_safe "DSP utilization report" \
            {report_dsp_utilization -file [file join $out_dir "dsp_utilization_${suffix}.rpt"]} \
            ""
    }
    if {[llength [info commands report_ram_utilization]] > 0} {
        write_report_safe "RAM utilization report" \
            {report_ram_utilization -file [file join $out_dir "ram_utilization_${suffix}.rpt"]} \
            ""
    }
}

proc ensure_run_complete {run_name} {
    set run_obj [get_runs $run_name]
    set progress [get_property PROGRESS $run_obj]
    set status [get_property STATUS $run_obj]
    puts "${run_name}_STATUS=$status"
    puts "${run_name}_PROGRESS=$progress"
    if {$progress ne "100%"} {
        puts "ERROR: $run_name did not complete"
        exit 1
    }
}

proc run_post_synth_hook {post_synth_tcl} {
    if {$post_synth_tcl ne ""} {
        puts "PROJECT_FAST_TIMING_POST_SYNTH_TCL=$post_synth_tcl"
        source $post_synth_tcl
    }
}

proc set_run_property_if_present {run_name prop_name prop_value} {
    set run_obj [get_runs -quiet $run_name]
    if {[llength $run_obj] == 0} {
        return
    }
    set props [list_property $run_obj]
    if {[lsearch -exact $props $prop_name] >= 0} {
        if {[catch {set_property $prop_name $prop_value $run_obj} msg]} {
            puts "WARNING: Failed to set $run_name.$prop_name: $msg"
        } else {
            puts "PROJECT_FAST_TIMING_RUN_PROPERTY $run_name.$prop_name=$prop_value"
        }
    }
}

proc disable_incremental_checkpoint_for_run {run_name} {
    set_run_property_if_present $run_name "AUTO_INCREMENTAL_CHECKPOINT" 0
    set_run_property_if_present $run_name "INCREMENTAL_CHECKPOINT" ""
    set_run_property_if_present $run_name "STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_MODE" off
    set_run_property_if_present $run_name "WRITE_INCREMENTAL_SYNTH_CHECKPOINT" 0
    set_run_property_if_present $run_name "WRITE_INCREMENTAL_SYNTH_DCP" 0
    set_run_property_if_present $run_name "STEPS.SYNTH_DESIGN.ARGS.INCREMENTAL_CHECKPOINT" ""
}

puts "PROJECT_FAST_TIMING_PROJECT=$project_file"
open_project $project_file
set_property top $top [current_fileset]
if {[llength $generic_overrides] > 0} {
    puts "Generic overrides: $generic_overrides"
    set_property generic $generic_overrides [current_fileset]
}
update_compile_order -fileset sources_1

if {$disable_incremental_checkpoint != 0} {
    disable_incremental_checkpoint_for_run synth_1
    disable_incremental_checkpoint_for_run impl_1
}

if {$direct_synth != 0} {
    set part [get_property PART [current_project]]
    puts "PROJECT_FAST_TIMING_DIRECT_SYNTH=1"
    synth_design -top $top -part $part
    run_post_synth_hook $post_synth_tcl
    emit_timing_reports $out_dir "post_synth"

    if {$stage eq "place"} {
        opt_design
        if {$place_directive ne ""} {
            place_design -directive $place_directive
        } else {
            place_design
        }
        emit_timing_reports $out_dir "post_place"
    }

    set timing_paths [get_timing_paths -max_paths 1 -quiet]
    if {[llength $timing_paths] > 0} {
        set worst_slack [get_property SLACK [lindex $timing_paths 0]]
        puts "PROJECT_FAST_TIMING_WORST_SLACK_NS=$worst_slack"
    }
    puts "PROJECT_FAST_TIMING_STAGE=$stage"
    puts "PROJECT_FAST_TIMING_REPORT_DIR=$out_dir"
    return
}

reset_run synth_1
if {$stage eq "place"} {
    reset_run impl_1
}

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
ensure_run_complete synth_1
open_run synth_1
run_post_synth_hook $post_synth_tcl
emit_timing_reports $out_dir "post_synth"

if {$stage eq "place"} {
    close_design
    if {$place_directive ne ""} {
        set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $place_directive [get_runs impl_1]
    }
    launch_runs impl_1 -to_step place_design -jobs $jobs
    wait_on_run impl_1
    ensure_run_complete impl_1
    open_run impl_1
    emit_timing_reports $out_dir "post_place"
}

set timing_paths [get_timing_paths -max_paths 1 -quiet]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    puts "PROJECT_FAST_TIMING_WORST_SLACK_NS=$worst_slack"
}
puts "PROJECT_FAST_TIMING_STAGE=$stage"
puts "PROJECT_FAST_TIMING_REPORT_DIR=$out_dir"
