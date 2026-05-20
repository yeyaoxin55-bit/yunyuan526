set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set top "cpu_top"
set part "xc7z020clg400-1"
set xdc_file [file join $repo_root "constraints" "top_100m.xdc"]
set out_dir [file join $repo_root "build" "vivado_impl"]
set jobs 4
set floorplan_tcl ""
set place_directive ""
set phys_opt_directive ""
set route_directive ""
set post_route_phys_opt_directive ""
set generic_overrides [list]

for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-top"} {
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
    } elseif {$key eq "-floorplan_tcl"} {
        incr i
        set floorplan_tcl [file normalize [lindex $argv $i]]
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
    } elseif {$key eq "-phys_opt_directive"} {
        incr i
        set phys_opt_directive [lindex $argv $i]
    } elseif {$key eq "-route_directive"} {
        incr i
        set route_directive [lindex $argv $i]
    } elseif {$key eq "-post_route_phys_opt_directive"} {
        incr i
        set post_route_phys_opt_directive [lindex $argv $i]
    } else {
        puts "ERROR: Unknown argument '$key'"
        exit 1
    }
}

file mkdir $out_dir
set_param general.maxThreads $jobs

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_root "rtl"]] [current_fileset]

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

read_verilog -sv $rtl_sources
read_xdc $xdc_file

if {[llength $generic_overrides] > 0} {
    puts "Generic overrides: $generic_overrides"
    synth_design -top $top -part $part -flatten_hierarchy rebuilt -generic $generic_overrides
} else {
    synth_design -top $top -part $part -flatten_hierarchy rebuilt
}
write_checkpoint -force [file join $out_dir "post_synth.dcp"]
report_utilization -file [file join $out_dir "utilization_post_synth.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary_post_synth.rpt"]
report_clocks -file [file join $out_dir "clocks_post_synth.rpt"]
if {[llength [info commands report_ram_utilization]] > 0} {
    report_ram_utilization -file [file join $out_dir "ram_utilization_post_synth.rpt"]
}

opt_design
if {$floorplan_tcl ne ""} {
    if {![file exists $floorplan_tcl]} {
        puts "ERROR: Missing floorplan Tcl '$floorplan_tcl'"
        exit 1
    }
    puts "Applying floorplan Tcl: $floorplan_tcl"
    source $floorplan_tcl
}
write_checkpoint -force [file join $out_dir "post_opt.dcp"]
report_timing_summary -file [file join $out_dir "timing_summary_post_opt.rpt"]

if {$place_directive eq ""} {
    place_design
} else {
    place_design -directive $place_directive
}
if {$phys_opt_directive eq ""} {
    phys_opt_design
} else {
    phys_opt_design -directive $phys_opt_directive
}
write_checkpoint -force [file join $out_dir "post_place.dcp"]
report_utilization -file [file join $out_dir "utilization_post_place.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary_post_place.rpt"]

if {$route_directive eq ""} {
    route_design
} else {
    route_design -directive $route_directive
}
if {$post_route_phys_opt_directive eq ""} {
    phys_opt_design
} else {
    phys_opt_design -directive $post_route_phys_opt_directive
}
write_checkpoint -force [file join $out_dir "post_route.dcp"]
report_utilization -file [file join $out_dir "utilization_post_route.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary_post_route.rpt"]
report_clocks -file [file join $out_dir "clocks_post_route.rpt"]
if {[llength [info commands report_ram_utilization]] > 0} {
    report_ram_utilization -file [file join $out_dir "ram_utilization_post_route.rpt"]
}
set bitstream_file [file join $out_dir "${top}.bit"]
write_bitstream -force $bitstream_file

set timing_paths [get_timing_paths -max_paths 1 -quiet]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    puts "IMPL_WORST_SLACK_NS=$worst_slack"
}
puts "IMPL_BITSTREAM=$bitstream_file"
puts "IMPL_REPORT_DIR=$out_dir"
