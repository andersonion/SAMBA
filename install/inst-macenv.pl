sub macenv{
    my $mode = shift;
    my $do_work=0;

    my $work_done=0;
    if( $mode ){
	print ("force\t");
	$do_work=$mode;
    } elsif(!$work_done ) {
	$do_work=1;
    }
    print("macenv\n");
    if ( $OS =~ /^darwin$/ ){
	
# do an if mac check
# later...
###
# copy ${SHELL}_env_to_mac_gui and environment.plist
###
	if( ! -e "${HOME}/.MacOSX/environment.plist" ) { 
	    if( ! -d "${HOME}/.MacOSX/" ) { 
		`mkdir ${HOME}/.MacOSX/`;
	    }
	    `cp ${WKS_HOME}/pipeline_settings/mac/environment.plist ${HOME}/.MacOSX/.`; 
	    print(" Copied environment plist\n");
	} else { 
	    print ("environment.plist already in place\n\tHoping it is correct.");
	}
	
	if(  -e "${HOME}/.${SHELL}_env_to_mac_gui" ) {
	    `rm ${HOME}/.${SHELL}_env_to_mac_gui`;
	}
	`cp ${WKS_HOME}/pipeline_settings/${SHELL}/${SHELL}_env_to_mac_gui ${HOME}/.${SHELL}_env_to_mac_gui`;
	print (" Copied ${SHELL} to gui stub\n");
	
###
# insert home dir into environment.plist
###
	print("---\n");
	print("Inserting home dir in to ~/.MacOSX/environment.plist ...... \n");
	print("---\n");
	$inpath="${HOME}/.MacOSX/environment.plist";
	$outpath=$inpath."out";
	if (open SESAME, $inpath) {
	    @all_lines = <SESAME>;
	    close SESAME;
	print(" opened env_plist \n");
	} else {
	    print STDERR "Unable to open file <$inpath> to read\n";
	exit (0);
	} 
	
	open SESAME_OUT, ">$outpath" or warn "could not open $outpath for writing\n";
	for my $line (@all_lines) {
	    if ( $line =~ /<string>.*(.${SHELL}_env_to_mac_gui)<\/string>/x ) { 
		my $envstring="  <string>${HOME}/.${SHELL}_env_to_mac_gui<\/string>\n";
		#  <string>code_location/bash_env_to_mac_gui</string>
		print(" found ${SHELL}_envline: \n$line replacing with:\n$envstring\n");
		print(SESAME_OUT "$envstring");
	    } else { 
		print( $line );
		print SESAME_OUT $line;
	    }
	}
	print("moving $outpath to $inpath\n");
	`mv $outpath $inpath`;
	return 1;
    } else {
	print ("... Not mac\n");
	return 1;
    }

}
1;
