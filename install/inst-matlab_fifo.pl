use warnings;
sub matlab_fifo () {
    print("matlab_fifo\n");
    my $fifo_dir="$WKS_HOME/../matlab_fifos";
    if ( ! -d $fifo_dir )  {
    	if ( ! $IS_MAC ) { 
	    print("WARNING: FIFO SUPPORT MAY BE POOR ON CLUSTER SYSTEM\n");
	    #$fifo_dir=
	}
	my $mkdir_cmd = "mkdir -p $fifo_dir" ;
	print("$mkdir_cmd\n");
	`$mkdir_cmd` or warn "could not make the fifo dir $fifo_dir";
    } else {
	print("FIFO dir found $fifo_dir\n");
    }
    print("Setting permisions for $fifo_dir\n");
    my $perm_commands=();
    my @cmd_errors=();
    push(@perm_commands,"chmod 775 $fifo_dir");
    push(@perm_commands,"chmod ug+s $fifo_dir");
    push(@perm_commands,"chgrp -R $USER_GROUP $fifo_dir");
    
    for my $cmd (@perm_commands) {
	my $output=`$cmd`;
	if ( $? ) { 
	    push (@cmd_errors,$output."$!\n");
	} 
    }
    
    
    if( $#cmd_errors>0) {
	print("fifo permission cmd errors:".join(@cmd_errors."\n"));
	return 1;
    }
    return 0;
}
1;
