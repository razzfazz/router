#!/usr/bin/perl

#
# cellArea.pl : This script can be used to process the cell report from
#               design compiler to determine the area of the modules
#               in the hierarchy
#
# arguments :   <path to input file> [<top-level module name>]

# ----------------------------------------------------------------------
# RCS Information:
#  $Author: dub $
#  $Date: 2008-02-01 02:13:58 $
#  $Id: cellArea.pl,v 1.1 2008-02-01 02:13:58 dub Exp $
# ----------------------------------------------------------------------

open( IN, $ARGV[0]) or die "Could not open $ARGV[0]\n" ;
my $area = 0 ;
my $instance = "" ;
my $reference = "" ;


for ( $n=0 ; $n < 70 ; $n=$n+1) {
    $longLine = $longLine . "-" ;
}
print "#$longLine\n" ;

$module = "# Instance" ;
print $module ;
for ( $n=length($module) ; $n < 32 ; $n=$n+1 ) {
    print " " ;
}
print "Area\n" ;
print "#$longLine\n" ;

while ($line = <IN>) {

    @fields = split(/ +/g, $line) ;

    $instance  = $fields[0] ;
    
    @hier = split( /\//, $instance ) ;

    if ( @hier eq 1 ) {
	$totalArea = $fields[2] ;
    }

    if ( @hier eq 2 && $line =~ m/ h/ ) {
	$module = $hier[0] . "/" . $hier[1] ;
	$n = length($module) ;
	print "  " . $module ;
	while ($n < 30) {
	    print " " ;
	    $n=$n+1 ;
	}
	$area = $fields[2] ;
	$fraction = $area / $totalArea * 100.0 ;
	print "$area ($fraction %)\n" ;
	$totalFrac = $totalFrac + $fraction ;
    }
}

print "#$longLine\n" ;
print "# Fraction of Area accounted for: $totalFrac\n" ;
