use warnings;
use strict; 
sub OptionOrder {
    #either input file or prefix.
    my $fileorprefix = shift @_;
    my $file='';
#    ! -f $fileorprefix
    my @f_try;
    push(@f_try,$fileorprefix);
    push(@f_try,"$fileorprefix-order.txt" );  
    push(@f_try,"install/$fileorprefix-order.txt");
    push(@f_try,"$fileorprefix.txt");
    push(@f_try,"install/$fileorprefix.txt");

    do {
	$file = shift @f_try;
    } while (! -f $file && $#f_try>0) ;
    print("using order : $file\n");
    if ( ! -f $file ) {
	print("ERROR getting an install order for therjigger <$fileorprefix>\n");
    }
    
    my $FH;
    my $openfail=0;
    open ($FH, "< $file") or ( warn "Can't open $file for read: $!" and $openfail=1 );
    my @lines;
    if (! $openfail) 
    {
	while (<$FH>) {
	    push (@lines, $_);
	}
	close $FH or die "Cannot close $file: $!";
    }
    chomp @lines;
    
    return @lines;
}
1;
