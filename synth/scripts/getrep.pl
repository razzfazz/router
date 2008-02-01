#!/usr/bin/perl
#getpre.pl parses report files
#usage: getrep.pl MODULENAME [path/to/report/dir (default ../rpt)]

sub usage
{
    print <<USAGE
        usage: getrep.pl MODULENAME [path/to/report/dir (default: ../rpt)]

USAGE
;
}

$module = shift;
unless ($module){
    usage;
    exit;
}

$dir = shift;
$dir = "rpt" unless $dir;

print "Using module $module in dir $dir\n";

#check list file for errors
print "checking $module.lis file for errors\n";

@errors = `grep Error $dir/$module.lis`;
if(@errors)
{
    if ($noninteractive){
        print "Errors found in $module.lis, aborting\n";
    }
    my $again = 1;
    while($again){
        print STDERR "Errors found, do you want to continue ([y]es/[n]o/[p]rint errors):";
        $_ = <STDIN>;
        $again = 0 if (substr($_, 0, 1) eq 'y');
        exit if (substr($_, 0, 1) eq 'n');
        print STDERR @errors if (substr($_, 0, 1) eq 'p');
    }
}

#get area
$areafile = $module."_syn_wrapper.area";
open (INP, "<$dir/$areafile") or die "can't open $areafile for reading\n";

$done=0;
while (<INP>){
    $comb_area = $1 if (/^Combinational area:\s+(\d+.\d+)/);
    $ncomb_area = $1 if (/^Noncombinational area:\s+(\d+.\d+)/);
    $tot_area = $1 if (/^Total cell area: \s+(\d+.\d+)/);
}

print <<AREA
    Comb Area:      $comb_area
    Non Comb Area:  $ncomb_area
    Total Area:     $tot_area
AREA
;
close (INP);

$powerfile = $module."_syn_wrapper.power";
open (INP, "<$dir/$powerfile") or die "can't open $powerfile for reading\n";

while (<INP>){
    if (/Hierarchy/){
        <INP>; <INP>;
        $_= <INP>;
        /(.{39})\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+/;
        $mname = $1;
        $tot_pow = $5;
        $mname =~ /^\s*(.*\S)\s+$/; #remove leading and trailing whitespace
        $mname = $1;
        last;
    }
}

print "    Total Power($mname): $tot_pow\n";
close (INP);

$timingfile = $module."_syn_wrapper.timing";
open (INP, "<$dir/$timingfile") or die "can't open $timingfile for reading\n";

while (<INP>){
    $drt = $1 if(/data required time\s+(\S+)/);
    $dat = $1 if(/data arrival time\s+(\S+)/);
    if(/slack \((\w+)\)\s+(\S+)/){
        $slack_status = $1 ;
        $slack = $2;
        last;
    }
}
print <<TIMING
    Data Required:  $drt
    Data Arrival:   $dat
    Slack($slack_status): $slack
TIMING
;

close (INP);
