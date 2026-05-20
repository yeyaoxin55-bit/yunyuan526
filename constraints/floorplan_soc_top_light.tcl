# Light floorplan for the 100 MHz soc_top timing experiment.
# Source this after opt_design and before place_design.

set pblock_name "pblock_soc_core_dmem_light"
set pblock_cells [get_cells -quiet {u_core u_dmem}]

if {[llength $pblock_cells] == 0} {
    puts "WARNING: floorplan_soc_top_light found no u_core/u_dmem cells; skipping pblock"
    return
}

if {[llength [get_pblocks -quiet $pblock_name]] == 0} {
    create_pblock $pblock_name
}

set pblock_obj [get_pblocks $pblock_name]
add_cells_to_pblock $pblock_obj $pblock_cells

proc yl3_add_site_range {pblock_obj site_pattern x_low_frac x_high_frac y_low_frac y_high_frac} {
    set sites [get_sites -quiet $site_pattern]
    if {[llength $sites] == 0} {
        puts "WARNING: floorplan range skipped, no sites match $site_pattern"
        return
    }

    set parsed_sites {}
    set min_x 1000000
    set max_x -1
    set min_y 1000000
    set max_y -1

    foreach site $sites {
        set site_name [get_property NAME $site]
        if {![regexp {^([A-Za-z0-9]+)_X([0-9]+)Y([0-9]+)$} $site_name match site_prefix x y]} {
            continue
        }
        lappend parsed_sites [list $site_name $x $y]
        if {$x < $min_x} { set min_x $x }
        if {$x > $max_x} { set max_x $x }
        if {$y < $min_y} { set min_y $y }
        if {$y > $max_y} { set max_y $y }
    }

    if {[llength $parsed_sites] == 0} {
        puts "WARNING: floorplan range skipped, could not parse sites for $site_pattern"
        return
    }

    set x_low [expr {$min_x + int(ceil(($max_x - $min_x) * $x_low_frac))}]
    set x_high [expr {$min_x + int(floor(($max_x - $min_x) * $x_high_frac))}]
    set y_low [expr {$min_y + int(ceil(($max_y - $min_y) * $y_low_frac))}]
    set y_high [expr {$min_y + int(floor(($max_y - $min_y) * $y_high_frac))}]

    set low_name ""
    set high_name ""
    set low_score 1000000000
    set high_score -1

    foreach parsed $parsed_sites {
        set site_name [lindex $parsed 0]
        set x [lindex $parsed 1]
        set y [lindex $parsed 2]
        if {$x < $x_low || $x > $x_high || $y < $y_low || $y > $y_high} {
            continue
        }
        set low_distance [expr {abs($x - $x_low) * 10000 + abs($y - $y_low)}]
        set high_distance [expr {abs($x - $x_high) * 10000 + abs($y - $y_high)}]
        if {$low_distance < $low_score} {
            set low_score $low_distance
            set low_name $site_name
        }
        set inverted_high_score [expr {1000000000 - $high_distance}]
        if {$inverted_high_score > $high_score} {
            set high_score $inverted_high_score
            set high_name $site_name
        }
    }

    if {$low_name eq "" || $high_name eq ""} {
        puts "WARNING: floorplan range skipped, empty selected range for $site_pattern"
        return
    }

    set range "$low_name:$high_name"
    puts "Adding pblock range $range"
    resize_pblock $pblock_obj -add $range
}

# Keep the constraint broad. The aim is to reduce route spread without forcing
# a tight placement that competes with BRAM/DSP column legality.
yl3_add_site_range $pblock_obj "SLICE_X*" 0.00 0.88 0.00 1.00
yl3_add_site_range $pblock_obj "DSP48_X*" 0.00 1.00 0.00 1.00
yl3_add_site_range $pblock_obj "RAMB18_X*" 0.00 1.00 0.00 1.00
yl3_add_site_range $pblock_obj "RAMB36_X*" 0.00 1.00 0.00 1.00

puts "Applied $pblock_name to cells: $pblock_cells"
