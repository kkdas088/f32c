#!/usr/local/bin/tclsh8.6
#
# Copyright 2011 University of Zagreb.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# $Id: $


if {$argc == 0} {
    puts "Usage: ./hex2bram.tcl ifile \[ofile\]"
    exit 1
} elseif {$argc == 1} {
    set ofile bram.vhd
} else {
    set ofile [lindex $argv 1]
}

set hexfile [open "[lindex $argv 0]"]
set linenum 0
set addr 0

while {[eof $hexfile] == 0} {
    gets $hexfile line
    set line [string trim $line]
    # Does the line begin with a valid label?
    if {[string index [lindex $line 0] end] != ":"} {
	continue;
    }
    set line_addr [expr 0x[string trim [lindex $line 0] :]]
    if {$addr != $line_addr} {
	puts "WARNING: bad address $line_addr (expected $addr) at line $linenum"
	while {$addr < $line_addr} {
	    set mem($addr) 00000000
	    incr addr 4
	}
    }
    foreach entry [lrange $line 1 end] {
	set mem($addr) $entry
	incr addr 4
    }
}
close $hexfile

# Pad mem to 512 byte-block boundary
while {[expr $addr % 512] != 0} {
    set mem($addr) 00000000
    incr addr 4
}
set endaddr $addr

set bramfile [open $ofile]
set linenum 0
set section undefined
set generic 0
set buf ""
set filebuf ""


proc peek {byte_addr} {
    global mem

    set entry $mem([expr ($byte_addr / 4) * 4])
    set i [expr 6 - ($byte_addr % 4) * 2]
    return [scan [string range $entry $i [expr $i + 1]] %02x]
}


while {[eof $bramfile] == 0} {
    gets $bramfile line
    incr linenum
    if {$section == "undefined"} {
	if {[string first ": DP16KB" $line] != -1} {
	    set section [lindex [split [string trim $line] _:] 1]
	    set seqn [lindex [split [string trim $line] _:] 2]
	    set width [expr 64 / $section]
	}
    } else {
	set key [string trim $line]
	if {$section != "undefined" &&
	  [string first "generic map" $key] == 0} {
	    # Beginning of generic section detected
	    set generic 1
	} elseif {$generic == 1 && [string first INITVAL_ $key] == 0} {
	    # Prune old INITVAL_ lines
	    continue
	} elseif {$key == ")"} {
	    # Construct and dump INITVAL_xx lines!
	    set addrstep [expr $section * 16]
	    for {set addr 0} {$addr < $endaddr} {incr addr $addrstep} {
		for {set i 0} {$i < 32} {incr i} {
		    set byte_addr [expr $addr + $seqn + $i * 4]
		    set ivbuf($i) [peek $byte_addr]
		}
		set hex ""
		for {set i 0} {$i < 32} {incr i} {
		    if {[expr $i % 2] == 0} {
			set hex "[format %02X $ivbuf($i)][set hex]"
		    } else {
			set hex "[format %03X [expr $ivbuf($i) * 2]][set hex]"
		    }
		}
		set prefix "INITVAL_[format %02d [expr $addr / $addrstep]] =>"
		if {$addr < [expr $endaddr - $addrstep]} {
		    lappend filebuf "		$prefix \"0x[set hex]\","
		} else {
		    lappend filebuf "		$prefix \"0x[set hex]\""
		}
	    }
	    #
	    set section undefined
	    set generic 0
	}
    }
    lappend filebuf $line
}
close $bramfile

# Trim blank lines from the end of file
while {[lindex $filebuf end] == ""} {
    set filebuf [lreplace $filebuf end end]
}

set bramfile [open $ofile w]
foreach line $filebuf {
    puts $bramfile $line
}
close $bramfile
