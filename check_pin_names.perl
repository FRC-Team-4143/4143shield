#!/usr/bin/perl -w

# Try to ensure that all the pin names and labels that appear in the gschem
# symbol file given as an argument are valid.  The gsch2pcb program seems
# to silently behave badly for pin names that end in things like 'n+',
# so we insist on simple numbers fo these attribute values.

use strict;
use warnings FATAL => 'all';

@ARGV == 1 or die "wrong number of arguments";
my $ftc = $ARGV[0];

open(FTC, "<$ftc") or die "couldn't open file '$ftc' for input";

my $ln = 1;

# Pin listing order.  We give each pin our own number as we encounter them
# in the symbol file.  Note that this number isn't necesarilly related to
# the pin number or label or anything else outside this script.
my $plord = 0;

# Pin attributes we've seen, keyed by our $plord value.
my %pa = ();

# Given an attribute hash from %pa, verify that any pinnumber and pinlabel
# values recorded for that plord crosscheck ok (see comments in sub for
# what that means).
sub crosscheck_attributes
{
    @_ == 1 or die "wrong number of arguments";
    my $ah = shift;

    my ($pn, $pl, $psl)
        = ($ah->{pinnumber}, $ah->{pinlabel}, $ah->{start_line});

    # If we have a pinlabel and its a number or starts with a number followed
    # by a space, that number better match the pinnumber.
    if ( $pl =~ m/^(\d+)(?:\s+.*)?$/ ) {
        $pn == $1 
            or die "pinlabel attribute '$pl' is a number or starts with a ".
                   "number followed by a space but doesn't match pinnumber ".
                   "attribute value '$pl' for a pin in file '$ftc' which ".
                   "starts on line $psl";
    }
}

while ( <FTC> ) { 
    
    $ln++;

    # If we have a pinlabel and its a number or starts with a number followed
    # by a space, that number better match the pinnumber.
    if ( m/^\s*P\s+(?:\d+\s?)+\s*$/ ) {
        $plord++;
        $pa{$plord}{start_line} = $ln;
    }

    # Look for attributes of interest and verify them (crosscheck between
    # attributes is handled below).
    if ( m/\s*(pinnumber|pinlabel)=(.*)\n$/ ) { 
        my $an = $1;   # Attribute name.
        my $plonav = $2;   # pinlabel or pinnumber attribute value.
        if ( $an eq 'pinnumber' ) {
          $plonav =~ m/^\d+$/
              or die "malformed $an value '$plonav' in file '$ftc' line $ln";
          $pa{$plord}{pinnumber} = $plonav;
        }
        elsif ( $an eq 'pinlabel' ) {
          $pa{$plord}{pinlabel} = $plonav;
        }
    }
}

foreach ( values(%pa) ) {
    crosscheck_attributes($_);
}

exit 0;
