sub ants(){
    my $mode = shift;
    print("ants_inst\n");
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
    if ( $IS_MAC ) {
	if ( ! -e "$WKS_HOME/../usr/bin/ANTS" ) 
	{
	    print("---\n");
	    print("Extracting ANTs ...... \n");
	    print("---\n");
	    print ("install to $WKS_HOME/../usr/bin/ANTS\n" );
	    my $scp_cmd;
	    # find dmg on syros
	    my $ants_dmg=`ssh syros ls -tr /Volumes/xsyros/Software/SegmentationSoftware/*dmg| grep ANT |tail -n 1`;
	    chomp($ants_dmg);
	    $ants_dmg=basename($ants_dmg);
	    #scp dmg
	    $scp_cmd="scp syros:/Volumes/xsyros/Software/SegmentationSoftware/$ants_dmg $WKS_HOME/../$ants_dmg";
	    if ( ! -f "../$ants_dmg" ) 
	    { 
		print ("$scp_cmd\n");
		`$scp_cmd`;
	    } else { 
		print("found dmg: $ants_dmg found\n");
	    }
	    #mount dmg
	    my $hdi_cmd="hdiutil attach ../$ants_dmg";
	    print("$hdi_cmd\n");
	    `$hdi_cmd`;
	    #find pkg in dmg volume
	    my $ants_pkg=`ls -d /Volumes/ANT*/*pkg`;
	    chomp($ants_pkg);
	    # install pkg
	    my $inst_cmd="sudo installer -pkg $ants_pkg -target /$WKS_HOME/../";
	    print("$inst_cmd\n");
	    `$inst_cmd`;
	    #unmount dmg
	    $hdi_cmd="hdiutil detach $ants_pkg/../";
	    print("$hdi_cmd\n");
	    `$hdi_cmd`;
	    return 0;
	} else {
	    print ("\tAnts Found in $WKS_HOME/../usr/bin/ANTS\n" ) ;
	}
    } else { 
	print("Not mac, no ants install, check shared location in /cm/shared\n");
	return 0;
    }

}
1;
