set out_dir ""
set top "soc_top"
set route_directive ""
set post_route_phys_opt_directive ""
set jobs 4

for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-out_dir"} {
        incr i
        set out_dir [file normalize [lindex $argv $i]]
    } elseif {$key eq "-top"} {
        incr i
        set top [lindex $argv $i]
    } elseif {$key eq "-route_directive"} {
        incr i
        set route_directive [lindex $argv $i]
    } elseif {$key eq "-post_route_phys_opt_directive"} {
        incr i
        set post_route_phys_opt_directive [lindex $argv $i]
    } elseif {$key eq "-jobs"} {
        incr i
        set jobs [lindex $argv $i]
    } else {
        puts "ERROR: Unknown argument '$key'"
        exit 1
    }
}

if {$out_dir eq ""} {
    puts "ERROR: -out_dir is required"
    exit 1
}

set_param general.maxThreads $jobs

set post_place_dcp [file join $out_dir "post_place.dcp"]
if {![file exists $post_place_dcp]} {
    puts "ERROR: Missing checkpoint '$post_place_dcp'"
    exit 1
}

open_checkpoint $post_place_dcp
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
