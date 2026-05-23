if {$argc < 2} {
    puts "Usage: report_timing_paths.tcl <checkpoint.dcp> <out.rpt> ?max_paths?"
    exit 1
}

set checkpoint [file normalize [lindex $argv 0]]
set out_file [file normalize [lindex $argv 1]]
set max_paths 10
if {$argc >= 3} {
    set max_paths [lindex $argv 2]
}

open_checkpoint $checkpoint
report_timing -delay_type max -max_paths $max_paths -sort_by slack -path_type full -file $out_file
puts "TIMING_PATH_REPORT=$out_file"
