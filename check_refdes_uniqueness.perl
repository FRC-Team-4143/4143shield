#!/usr/bin/perl -w

# Try to ensure that all the refdes attributes that appear in the gschem file
# given as an argument are set and are unique.  The gsch2pcb program seems to
# silently behave badly (outputs only one of the elements with a common
# refdes), though its possible that at other times its necessary to depend on
# this behavior if you have for example a slotted item.

use strict;
use warnings FATAL => 'all';

@ARGV == 1 or die "wrong number of arguments";

my %rd = (); 

while ( <> ) { 
    if ( m/\s*refdes=(.*)\n$/ ) { 
        my $crd = $1;   # Current refdes.
        $crd !~ m/\?$/ or die "unset refdes '$crd'";
        not exists $rd{$crd} or die "non-unique refdes '$crd'"; 
        $rd{$crd} = 1; 
    }
}

exit 0;
