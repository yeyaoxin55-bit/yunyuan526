set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set stage "synth"
set top "soc_top"
set part "xc7z020clg400-1"
set xdc_file [file join $repo_root "constraints" "tinyriscv_huoyue_uart.xdc"]
set out_dir [file join $repo_root "build" "vivado_fast_timing"]
set jobs 4
set place_directive "Quick"
set generic_overrides [list]

# Supported fast timing stages:
# stage "synth" - stop after synthesis and emit path-family reports.
# stage "place" - stop after placement and emit path-family reports.
for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-stage"} {
        incr i
        set stage [lindex $argv $i]
    } elseif {$key eq "-top"} {
        incr i
        set top [lindex $argv $i]
    } elseif {$key eq "-part"} {
        incr i
        set part [lindex $argv $i]
    } elseif {$key eq "-xdc"} {
        incr i
        set xdc_file [file normalize [lindex $argv $i]]
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
    } else {
        puts "ERROR: Unknown argument '$key'"
        exit 1
    }
}

if {$stage ne "synth" && $stage ne "place"} {
    puts "ERROR: -stage must be synth or place"
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

set rtl_sources [list \
    [file join $repo_root "rtl" "defines.vh"] \
    [file join $repo_root "rtl" "alu.v"] \
    [file join $repo_root "rtl" "regfile.v"] \
    [file join $repo_root "rtl" "decoder.v"] \
    [file join $repo_root "rtl" "hazard_unit.v"] \
    [file join $repo_root "rtl" "imem.v"] \
    [file join $repo_root "rtl" "dmem.v"] \
    [file join $repo_root "rtl" "csr_unit.v"] \
    [file join $repo_root "rtl" "branch_predictor.v"] \
    [file join $repo_root "rtl" "prefetch.v"] \
    [file join $repo_root "rtl" "divider.v"] \
    [file join $repo_root "rtl" "multiplier.v"] \
    [file join $repo_root "rtl" "uart.v"] \
    [file join $repo_root "rtl" "cpu_core.v"] \
    [file join $repo_root "rtl" "cpu_top.v"] \
    [file join $repo_root "rtl" "clk_gen_50m_to_100m.v"] \
    [file join $repo_root "rtl" "soc_top.v"] \
    [file join $repo_root "rtl" "fpga_coremark_top.v"] \
]

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root "rtl"]] [current_fileset]

read_verilog -sv $rtl_sources
read_xdc $xdc_file

if {[llength $generic_overrides] > 0} {
    puts "Generic overrides: $generic_overrides"
    synth_design -top $top -part $part -flatten_hierarchy rebuilt -generic $generic_overrides
} else {
    synth_design -top $top -part $part -flatten_hierarchy rebuilt
}

write_checkpoint -force [file join $out_dir "post_synth.dcp"]
emit_timing_reports $out_dir "post_synth"

if {$stage eq "place"} {
    opt_design
    if {$place_directive eq ""} {
        place_design
    } else {
        place_design -directive $place_directive
    }
    write_checkpoint -force [file join $out_dir "post_place.dcp"]
    emit_timing_reports $out_dir "post_place"
}

set timing_paths [get_timing_paths -max_paths 1 -quiet]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    puts "FAST_TIMING_WORST_SLACK_NS=$worst_slack"
}
puts "FAST_TIMING_STAGE=$stage"
puts "FAST_TIMING_REPORT_DIR=$out_dir"
