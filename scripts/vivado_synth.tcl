set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ".."]]

set top "cpu_top"
set part "xc7z020clg400-1"
set xdc_file [file join $repo_root "constraints" "top_125m.xdc"]
set out_dir [file join $repo_root "build" "vivado_synth"]
set jobs 4
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
    synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt -generic $generic_overrides
} else {
    synth_design -top $top -part $part -mode out_of_context -flatten_hierarchy rebuilt
}

report_utilization -file [file join $out_dir "utilization_synth.rpt"]
report_timing_summary -file [file join $out_dir "timing_summary_synth.rpt"]
report_clocks -file [file join $out_dir "clocks_synth.rpt"]
if {[llength [info commands report_dsp_utilization]] > 0} {
    report_dsp_utilization -file [file join $out_dir "dsp_utilization_synth.rpt"]
} else {
    puts "INFO: report_dsp_utilization is not available in this Vivado version; DSP usage is included in utilization_synth.rpt"
}
if {[llength [info commands report_ram_utilization]] > 0} {
    report_ram_utilization -file [file join $out_dir "ram_utilization_synth.rpt"]
} else {
    puts "INFO: report_ram_utilization is not available in this Vivado version; RAM usage is included in utilization_synth.rpt"
}
write_checkpoint -force [file join $out_dir "synth.dcp"]

set timing_paths [get_timing_paths -max_paths 1 -quiet]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    puts "SYNTH_WORST_SLACK_NS=$worst_slack"
}
puts "SYNTH_REPORT_DIR=$out_dir"
