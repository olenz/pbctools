############################################################
#
#    This file contains procedures to wrap atoms into the central
# image of a system with periodic boundary conditions. The procedures
# required the VMD unit cell properties to be set. Use the procedure
# pbcset on this behalf.
#
# $Id$
#

package provide pbctools 3.1

namespace eval ::PBCTools:: {
    namespace export pbc*

    ############################################################
    #
    # pbcunwrap [OPTIONS...]
    #
    # OPTIONS:
    #   -molid $molid|top
    #   -first $first|first|now 
    #   -last $last|last|now
    #   -all|allframes
    #   -sel $sel
    #   -[no]verbose
    #   -[no]heuristic
    #   -[no]displacement
    #
    # AUTHORS: Martin, Olaf, Jerome, Cameron
    #
    proc pbcunwrap {args} {
	# Set the defaults
	set molid "top"
	set first "first"
	set last "last"
	set seltext "all"
	set verbose 0
	set heuristic 0
	
	# Parse options
	for { set argnum 0 } { $argnum < [llength $args] } { incr argnum } {
	    set arg [ lindex $args $argnum ]
	    set val [ lindex $args [expr {$argnum + 1}]]
	    switch -- $arg {
		"-molid" { set molid $val; incr argnum; }
		"-first" { set first $val; incr argnum }
		"-last" { set last $val; incr argnum }
		"-allframes" -
		"-all" { set last "last"; set first "first" }
		"-now" { set last "now"; set first "now" }
		"-sel" { set seltext $val; incr argnum }
		"-verbose" { set verbose 1 }
		"-noverbose" { incr verbose 0 }
		"-noheuristic" { set heuristic 0 }
		"-heuristic" { incr heuristic } 
		"-displacement" { set heuristic 0 }
		"-nodisplacement" { incr heuristic }
		default { error "pbcunwrap: unknown option: $arg" }
	    }
	}
	
	if { $molid=="top" } then { set molid [ molinfo top ] }

	# Save the current frame number
	set frame_before [ molinfo $molid get frame ]

	if { $first=="now" }   then { set first $frame_before }
	if { $first=="first" || $first=="start" || $first=="begin" } then { 
	    set first 0 
	}
	if { $last=="now" }    then { set last $frame_before }
	if { $last=="last" || $last=="end" } then {
	    set last [expr {[molinfo $molid get numframes]-1}]
	}

	if { $first == 0 } then {
	    set frame $first
	} else {
	    set frame [expr $first - 1]
	}
	molinfo $molid set frame $frame

	# get coordinates of the first reference frame
	set sel [atomselect $molid $seltext]

	set oldxs [$sel get x]
	set oldys [$sel get y]
	set oldzs [$sel get z]
	
	if { $heuristic == 0 } {
		set unwrapx $oldxs
		set unwrapy $oldys
		set unwrapz $oldzs
        set oldcell [lindex [pbcget -check -molid $molid -namd] 0]
	}
	
	set next_time [clock clicks -milliseconds]
	set show_step 1000
	set fac [expr 100.0/($last - $first + 1)]

	# loop over all frames
	# for efficiency reasons, most operations are carried out as
	# vector operations on all coordinates at once
	for {incr frame} { $frame <= $last } { incr frame } {
	    if { $verbose } then { vmdcon -info "Unwrapping frame $frame..." } 

	    molinfo $molid set frame $frame
	    $sel frame $frame

	    # get the current cell 
	    set cell [lindex [pbcget -check -molid $molid -namd] 0]
	    set A [lindex $cell 0]
	    set B [lindex $cell 1]
	    set C [lindex $cell 2]

	    # get the current coordinates 
	    set xs [$sel get x]
	    set ys [$sel get y]
	    set zs [$sel get z]

	    if { $heuristic > 0 } {
	    	# wrap the coordinates
		    pbcwrap_coordinates $A $B $C xs ys zs $oldxs $oldys $oldzs
		    
		    # set the new coordinates
		    $sel set x $xs
		    $sel set y $ys 
		    $sel set z $zs

		#This calculates unwrapping based on displacement
	    } else {
		    set vx [vecsub $xs $oldxs]
		    set vy [vecsub $ys $oldys]
		    set vz [vecsub $zs $oldzs]
		    
		    set vx2 [vecsub $oldxs $unwrapx]
		    set vy2 [vecsub $oldys $unwrapy]
		    set vz2 [vecsub $oldzs $unwrapz]

		    # unwrap the displacements
		    for {set c 0} {$c < [llength $vx]} {incr c} {
                lset vx $c [expr [lindex $vx $c]-floor([lindex $vx $c]/[lindex $cell 0 0]+0.5)*[lindex $cell 0 0]-floor(([lindex $vx2 $c])/[lindex $oldcell 0 0]+0.5)*([lindex $cell 0 0]-[lindex $oldcell 0 0])]
                lset vy $c [expr [lindex $vy $c]-floor([lindex $vy $c]/[lindex $cell 1 1]+0.5)*[lindex $cell 1 1]-floor(([lindex $vy2 $c])/[lindex $oldcell 1 1]+0.5)*([lindex $cell 1 1]-[lindex $oldcell 1 1])]
                lset vz $c [expr [lindex $vz $c]-floor([lindex $vz $c]/[lindex $cell 2 2]+0.5)*[lindex $cell 2 2]-floor(([lindex $vz2 $c])/[lindex $oldcell 2 2]+0.5)*([lindex $cell 2 2]-[lindex $oldcell 2 2])]}

		    # add displacements to previous unwrapped coordinates
		    set unwrapx [vecadd $vx $unwrapx]
			set unwrapy [vecadd $vy $unwrapy]
			set unwrapz [vecadd $vz $unwrapz]
		    
		    # set the new coordinates
		    $sel set x $unwrapx
		    $sel set y $unwrapy
		    $sel set z $unwrapz
	    }

	    # save the coordinates
		set oldxs $xs
		set oldys $ys
		set oldzs $zs
		if { $heuristic == 0 } {set oldcell $cell}

	    set time [clock clicks -milliseconds]
	    if {$verbose || $frame == $last || $time >= $next_time} then {
		set percentage [format "%3.1f" [expr $fac*($frame-$first+1)]]
		vmdcon -info "$percentage% complete (frame $frame)"
		set next_time [expr $time + $show_step]
	    }
	}
	# Rewind to original frame
	if { $verbose } then { vmdcon -info "Rewinding to frame $frame_before." }
	animate goto $frame_before
    }

}
