sub OptionOrder() {

    my $file = "install/inst-order.txt";
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
