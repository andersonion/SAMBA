sub fsl() {
    print("fsl\n");
    return 1;
	if ( ! -d "../fsl" ) 
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

	### get fsl patches. we're up to two now. 
	my $fslupdate=`civm_fslupdate.pl`;
	#tar -zxvf ~/Downloads/fsl-macosx-patch-5.0.2_from_5.0.1.tar.gz
    {
	print("---\n");
	print("Inserting FSL config to ${shell}_profile ...... \n");
	print("---\n");
	my $HOME=$ENV{HOME};
	my @all_lines;
	print("Must run this as user to install to!\n". 
	      "By default that is omega\n".
	      "This only sets up the ${shell} environment!\n");
	
### open ${shell}_profile to check for source ${shell}rc line. 
	my  $inpath="${HOME}/.${shell}_profile";
	if ( -e $inpath ) { 
	    if (open SESAME, $inpath) {
		@all_lines = <SESAME>;
		close SESAME;
		print(" Opened ${shell}_profile\n");
	    } else {
		print STDERR "Unable to open file <$inpath> to read\n";
		exit(0);
	    } 
	}
	
	my $line_found=0;
	my $outpath="${HOME}/.${shell}_profile";
	my $fsl_dir="FSLDIR=$wks_home/../fsl";
	open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
	for my $line (@all_lines) {
	    if ($line =~ /FSLDIR=.*/) { # matches source<anthing>.${shell}rc<anything> could be to broad a match
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
	}
	close SESAME_OUT;
    }

	return;
}
1;
