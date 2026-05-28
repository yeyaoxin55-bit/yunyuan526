set project_file "D:/Verilog_prj/yunyuan3_rv64/yunyuan3_rv64.xpr"
set top "soc_top"
set reset_impl 1

for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-project"} {
        incr i
        set project_file [file normalize [lindex $argv $i]]
    } elseif {$key eq "-top"} {
        incr i
        set top [lindex $argv $i]
    } elseif {$key eq "-reset_impl"} {
        incr i
        set reset_impl [lindex $argv $i]
    } else {
        puts "ERROR: Unknown argument '$key'"
        exit 1
    }
}

if {![file exists $project_file]} {
    puts "ERROR: Missing Vivado project '$project_file'"
    exit 1
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
            puts "PROJECT_RESET_RUN_PROPERTY $run_name.$prop_name=$prop_value"
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

puts "PROJECT_RESET_PROJECT=$project_file"
open_project $project_file
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

disable_incremental_checkpoint_for_run synth_1
disable_incremental_checkpoint_for_run impl_1

if {[llength [get_runs -quiet synth_1]] > 0} {
    reset_run synth_1
    puts "PROJECT_RESET_RUN=synth_1"
}
if {$reset_impl != 0 && [llength [get_runs -quiet impl_1]] > 0} {
    reset_run impl_1
    puts "PROJECT_RESET_RUN=impl_1"
}

puts "PROJECT_RESET_COMPLETE=1"
close_project
