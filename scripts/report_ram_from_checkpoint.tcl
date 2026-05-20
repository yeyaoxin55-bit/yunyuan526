set checkpoint ""
set out_file ""

for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-checkpoint"} {
        incr i
        set checkpoint [file normalize [lindex $argv $i]]
    } elseif {$key eq "-out_file"} {
        incr i
        set out_file [file normalize [lindex $argv $i]]
    } else {
        puts "ERROR: Unknown argument '$key'"
        exit 1
    }
}

if {$checkpoint eq ""} {
    puts "ERROR: Missing -checkpoint"
    exit 1
}
if {$out_file eq ""} {
    puts "ERROR: Missing -out_file"
    exit 1
}
if {![file exists $checkpoint]} {
    puts "ERROR: Missing checkpoint '$checkpoint'"
    exit 1
}

open_checkpoint $checkpoint
if {[llength [info commands report_ram_utilization]] > 0} {
    report_ram_utilization -file $out_file
} else {
    puts "ERROR: report_ram_utilization is not available in this Vivado version"
    exit 1
}
puts "RAM_REPORT=$out_file"
