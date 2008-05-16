#!/usr/bin/perl

# -----
#  Extract command-line arguments
# --
for ( $i = 0 ; $i < $#ARGV ; $i=$i+1 ) {
    if ( $ARGV[$i] eq "-module" ) {
	$i=$i+1 ;
	$module_name=$ARGV[$i] ;
    }
    if ( $ARGV[$i] eq "-input" ) {
	$i=$i+1 ;
	$input_file=$ARGV[$i] ;
    }
    if ( $ARGV[$i] eq "-output" ) {
	$i=$i+1 ;
	$output_file=$ARGV[$i] ;
    }
}

if ( length($input_file) == 0  || length($output_file) == 0 ||
     length($module_name) == 0 ) 
{
    print( STDOUT "Usage: -module <string> -input <file> -output <file>\n" );
}

# Open input and output files 
open ( IN , '<' , "$input_file" ) 
    or die "ERROR: could not open $input_file\n" ;

open ( OUT , '>' , "$output_file" )
    or die "ERROR: could not create $output_file\n" ;

# ----
#  Create Wrapper Module
# --
print( OUT "// AUTOMATICALLY GENERATED\n" ) ;
$output_file =~ m/\/?(\w+)(\.v)?$/ ;
$wrapper_name = $1 ;

# ----
#  Scan the input file to locate the module and extract its ports
# -- 
print ( STDOUT "Searching for module $module_name\n" ) ;
$done = 0 ;
while ( ($line = <IN>) && ($done == 0) ) {

    if ( $line =~ m/module/ ) {
	$has_clock = 0 ;
	# Replace the module name with the wrapper name and then
	# copy the port list into the wrapper module
	if ( $line =~ m/ $module_name[ +|\(]/ ) {
	    print ( STDOUT "Found module\n" ) ;
	    $line =~ s/$module_name/$wrapper_name/ ;
	    if ( $line =~ m/\)/ ) {
		if ( $line =~ m/CLK/ ) {
		    $has_clock = 1 ;
		    print ( STDOUT "Found CLK\n" ) ;
		}
	    } else {
		while ( !($line =~ m/\)/) ) {
		    if ( $line =~ m/CLK/ ) {
			$has_clock = 1 ;
			print ( STDOUT "Found CLK\n" ) ;
		    }
		    printf ( OUT $line ) ;
		    $line = <IN> ;
		}
	    }
	    if ( $has_clock == 0 ) {
		$line =~ s/\)/, CLK\)/ ;
		printf( OUT $line ) ;
		printf( OUT "  input CLK ; // AUTOMATICALLY ADDED CLK\n" ) ;
	    } else {
		printf( OUT $line ) ;
	    }

	} 
    }
    else {
	next ; 
    }
	
    print ( STDOUT "Reading ports\n" ) ;

    while ( ($line = <IN>) && ($done == 0) ) {

	if ( $line =~ m/`include/ ) {
	    $line =~ m/`include\s+\"([a-z0-9-_.]*)\"/ ;
	    push( @include_list, $1 ) ;
	    print( OUT $line ) ;
	    next ;
	}

	if ( $line =~ m/parameter/ ) {
	    $line =~ m/parameter\s+(\w+)\s*=\s*([0-9]+)/ ;
	    push( @param_list, $1 ) ;
	    $param_val{$1}=$2 ;
	    print( OUT $line ) ;
	    next ;
	}

	if ( $line =~ m/^\s*(input|output)/ ) {

		$line =~ s/\breg\b//;	#remove 'reg' from outputs (it shouldn't be there on inputs)

	    # Transfer the port definition to the wrapper module
	    printf( OUT $line ) ;

	    # Capture all the input ports and output ports
	    if ( $line =~ m/ input / ) {

		if ( $line =~ m/\sCLK[\s|\;]/ ) {
		    $has_clock = 1 ;
		    next ;
		}

		$line =~ m/input\s+(\[.+\])?\s*(\w+)/g ;
		push(@input_ports, $2) ;
		$width{$2} = $1 ;

		if ( $line =~ m/,/) {
		    printf( STDOUT "ERROR: only one port def per line allowed\n") ;
		    printf( STDOUT $line ) ;
		    exit ;
		}
	    }
	    
	    if ( $line =~ m/ output / ) {

		$line =~ m/output(?:\s+reg\b)?(\s*\[.+\]\s*)?\s*(\w+)/g ;
		push(@output_ports, $2) ;
		$width{$2} = $1 ;
	
		if ( $line =~ m/,/) {
		    printf( STDOUT "ERROR: only one port def per line allowed\n") ;
		    printf( STDOUT $line ) ;
		    exit ;
		}
	    }
	}
	if ( $line =~ m/endmodule/ ) {
	    $done = 1 ;
	}
    }
}

printf( OUT "\n" ) ;
foreach $port ( @input_ports ) {
    $reg_name = "reg_in_" . $port ;
    print( OUT "  reg $width{$port} $reg_name ; \n" ) ;
}

print( OUT "\n" ) ;
foreach $port ( @output_ports ) {
    $reg_name = "reg_out_" . $port ;
    print( OUT "  reg $width{$port} $reg_name ; \n" ) ;
}

print( OUT "\n" ) ;
foreach $port ( @output_ports ) { 
    $wire_name = "n_" . $port ;
    print( OUT "  wire $width{$port} $wire_name ; \n" ) ;
}

# Create Input registers
printf( OUT "\n" ) ;
print( OUT "  always @(posedge CLK) begin\n" ) ;
foreach $port ( @input_ports ) {
    $reg_name = "reg_in_" . $port ;
    print( OUT "    $reg_name <= $port ;\n" ) ;
}
print( OUT "  end\n" ) ;
# Create Output registers
print( OUT "\n" ) ;
print( OUT "  always @(posedge CLK) begin\n" ) ;
foreach $port ( @output_ports ) { 
    $wire_name = "n_" . $port ;
    $reg_name  = "reg_out_" . $port ;
    print( OUT "    $reg_name <= $wire_name ;\n" ) ;
}
print( OUT "  end\n" ) ;
print( OUT "\n" ) ;
foreach $port ( @output_ports ) { 
    $reg_name = "reg_out_" . $port ;
    print( OUT "  assign $port = $reg_name ;\n" ) ;
}

# Create Module Instance
print( OUT "\n" ) ;
$instance_name = "I_" . $module_name ;
print( OUT "  $module_name $instance_name ( \n" ) ;
$first = 1 ;
foreach $port ( @input_ports ) {
    $reg_name = "reg_in_" . $port ;
    if ( $first == 1 ) {
	print( OUT "    .$port ( $reg_name )" ) ;
	$first = 0 ;
    } else {
	print( OUT ",\n    .$port ( $reg_name )" ) ;
    }
}
foreach $port ( @output_ports ) {
    $wire_name = "n_" . $port ;
    if ( $first == 1 ) {
	print( OUT "    .$port ( $wire_name )" ) ;
	$first = 0 ;
    } else {
	print( OUT ",\n    .$port ( $wire_name )" ) ;
    }
}
if ( $has_clock ) {
    if ( $first == 1 ) {
	print( OUT "    .CLK ( CLK )" ) ;
	$first = 0 ;
    } else {
	print( OUT ",\n    .CLK ( CLK )" ) ;
    } 
}
print( OUT ") ;\n" ) ;
print( OUT "endmodule\n") ;

close( IN ) ;
close( OUT ) ; 
