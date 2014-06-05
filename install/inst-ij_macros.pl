use warnings;
#use strict;
sub ij_macros() {
    print("ij_macros\n");

### 
# set up imagej macro link
###
    my $infile;
    my $ln_source;
    my $ln_dest;
    my $ln_cmd;
    $infile="$WKS_HOME/analysis/";
    $ln_source="$infile"."james_imagejmacros";;
    
    if($IS_MAC  ){
	$ln_dest="/Applications/ImageJ/plugins/000_james_imagejmacros";
    } else {
	print("ImageJMacro link location?\n\tThe full path to imagej/plugins/ijmacros\n");
	$ln_dest=readline(*STDIN);
	chomp($ln_dest);
    }

    if ( ! length ($ln_dest)) {
	undef $ln_dest;
    } elsif ( -e $ln_dest ) { 
	unlink($ln_dest);
    } 
    if (! -d $ln_source  ) {
	undef $ln_source;
    }
    if ( defined($ln_source) && defined($ln_dest) ){
	$ln_cmd="ln -sf $ln_source $ln_dest";
	print ("$ln_cmd\n");
	#`$ln_cmd`;
	return 1;
    } else {
	return 0;
    }
}
1;

