	#--with-oracle-lib-path
	chdir $wks_home;
# % whence perl  # or whatever command returns the version of perl first in your path.   
#                 # Verify this is the version you intent to install DBD::Oracle to  
#  % gzip -dc DBD-Oracle-1.40.tar.gz | tar xf - 
#  % cd DBD-Oracle-1.17 
#  % perl Makefile.PL -V 10.2 
#  % make 
#  % make install 

	my $OS='mac';
	my $base_path="/Volumes/xsyros/software/oracle/";
	if ( ! -d "$oracle_inst" ) 
	{
	    print("---\n");
	    print("Extracting Oracle ...... \n");
	    print("---\n");
	    my @oracle_parts=qw(basic sqlplus sdk);
	    my $scp_cmd;
	    # find dmg on syros
	    if ( ! -d "../zip" ) 
	    {
		`mkdir ../zip`;
	    }
	    for my $part (@oracle_parts)  { 
		my $ls_cmd="ssh syros ls ${base_path}/*${OS}*${arch}/*client*$part*${oracle_version}*${OS}*${arch}*.zip";
		my $oracle_zip=`$ls_cmd` or print("cmd_fail $ls_cmd\n");
		chomp($oracle_zip);
		#scp dmg
		$scp_cmd="scp syros:$oracle_zip ../zip/".basename($oracle_zip);
		if ( ! -f "../zip".basename($oracle_zip) ) 
		{ 
		    print ("$scp_cmd\n");
		    `$scp_cmd`;
		} else { 
		    print("found zip: ".basename($oracle_zip)." found\n");
		}
		# 
		chdir "../zip/";
		my $cmd="unzip ".basename($oracle_zip)." -d $oracle_inst";
		open my $cmd_fh, "$cmd |";   # <---  | at end means to make command 
		#         output available to the handle
		while (<$cmd_fh>) 
		{
		    print "A line of output from the command is: $_";
		}
		chdir $wks_home;
	    }
	    `mv $oracle_inst/*/* $oracle_inst`;
	}
	if ( 1 ) { 
	    print("creating oracle_cpaninst.bash for root to run\n");
	    my $outpath="$wks_home/oracle_cpaninst.bash";
	    open SESAME_OUT, ">$outpath"; 
	    print SESAME_OUT "#!/bin/bash\n".
		"declare -x ORACLE_HOME=$oracle_inst\n".
		"declare -x DYLD_LIBRARY_PATH=$oracle_inst\n".
		"cpan YAML\n".
		"cpan DBI\n".
		"cpan DBD::Oracle\n";
	    close SESAME_OUT;
	    
	    my $cmd="sudo bash $outpath && unlink $outpath";
	    open my $cmd_fh, "$cmd |";   # <---  | at end means to make command 
	    #         output available to the handle
	    while (<$cmd_fh>) 
	    {
		print "$_";
	    }
	}
