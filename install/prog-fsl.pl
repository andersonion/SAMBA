sub fsl() {

    my $mode = shift;
    print("fsl\n");
    
    #look for $FSLDIR
    my $do_work=0;
    my $work_done=0;

    if (! defined $mode ) {$mode=0;}
    if (! looks_like_number($mode) ) {

	if ($mode =~ /quiet/x ){
	print ("$mode\t");
	    $mode=-1;
	} elsif ($mode =~ /silent/x ){
	print ("$mode\t");
	    $mode=-2;
	}
    }
    use ENV;
    if (! -z $ENV{"FSL_DIR"} ) { 
	$work_done=1; 
    } else {
	print ("\tFSL Found in ".$ENV{"FSL_DIR"}."\n");
    }
    if( looks_like_number($mode) ){
	if ($mode>0 ) {
	    print ("force\t");
	    $do_work=$mode;
	} elsif(!$work_done ) {
	    $do_work=1;
	}
    } else {
	if(!$work_done ) {
	    $do_work=1;
	}
    }
    
    
    if ( ! -d "$WKS_HOME/../fsl" && -z $ENV{"FSL_DIR"}) 
    {
	print("---\n");
	print("Running FSL installer ...... \n");
	print("---\n");
	    #get fsl script?
	my $fsl_inst_cmd="./fslinstaller.py -d $wks_home/../";
	open my $cmd_fh, "$fsl_inst_cmd |";   # <---  | at end means to make command 
	#         output available to the handle
	while (<$cmd_fh>) 
	{
	    print "A line of output from the command is: $_";
	}
	close $cmd_fh;
#    `$fsl_inst_cmd`;
	
    }
    my $fslupdate=`civm_fslupdate.pl`;
    if ( $IS_MAC && $do_work) {
	### get fsl patches. we're up to two now. 
	#tar -zxvf ~/Downloads/fsl-macosx-patch-5.0.2_from_5.0.1.tar.gz
	
	print("---\n");
	print("Inserting FSL config to ${SHELL}_profile ...... \n");
	print("---\n");
	my $HOME=$ENV{HOME};
	my @all_lines;
	print("Must run this as user to install to!\n". 
	      "Must know where to find fsl, or will install a local copy!\n".
#	      "By default that is omega\n".
	      "This only sets up the ${SHELL} environment!\n");
	
### open ${SHELL}_profile to check for source ${SHELL}rc line. 
	my  $inpath="${HOME}/.${SHELL}_profile";
	if ( -e $inpath ) { 
	    if (open SESAME, $inpath) {
		@all_lines = <SESAME>;
		close SESAME;
		print(" Opened ${SHELL}_profile\n");
	    } else {
		print STDERR "Unable to open file <$inpath> to read\n";
		exit(0);
	    } 
	}
	
	my $line_found=0;
	my $outpath="${HOME}/.${SHELL}_profile";
	my $fsl_dir="FSLDIR=$wks_home/../fsl";
	open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
	for my $line (@all_lines) {
	    if ($line =~ /FSLDIR=.*/) { # matches source<anthing>.${SHELL}rc<anything> could be to broad a match
		$line_found=1;
		$line="$fsl_dir\n";
	    }
	    print  SESAME_OUT $line;  # write out every line modified or not
	}
	if( $line_found==0){ 
	    print ("FSLDIR setting not found, fsl did not install correctly, Trying to dump fsl setup into bash_profile\n"); 
# try running this again. If that fails try running the fsl installer separetly. \n");
	    my $line='# FSL Setup'."\n".
		"FSLDIR=$wks_home/../fsl"."\n".
		'PATH=${FSLDIR}/bin:${PATH}'."\n".
		'export FSLDIR PATH'."\n".
		'. ${FSLDIR}/etc/fslconf/fsl.sh'."\n";
	    print SESAME_OUT $line;
	} else {
	    print ("\tFound fsl in $SHELL"."_profile\n");
	}
	close SESAME_OUT;
    }
    
    return;
}
1;
