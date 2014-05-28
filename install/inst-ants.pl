sub ants(){
    print("ants_inst\n");
    return 1;
    if ( ! -e "../usr/bin/ANTS" ) 
    {
	print("---\n");
	print("Extracting ANTs ...... \n");
	print("---\n");
	my $scp_cmd;
	# find dmg on syros
	my $ants_dmg=`ssh syros ls -tr /Volumes/xsyros/Software/SegmentationSoftware/*dmg| grep ANT |tail -n 1`;
	chomp($ants_dmg);
	$ants_dmg=basename($ants_dmg);
	#scp dmg
	$scp_cmd="scp syros:/Volumes/xsyros/Software/SegmentationSoftware/$ants_dmg ../$ants_dmg";
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
	my $inst_cmd="sudo installer -pkg $ants_pkg -target /$wks_home/../";
	print("$inst_cmd\n");
	`$inst_cmd`;
	#unmount dmg
	$hdi_cmd="hdiutil detach $ants_pkg/../";
	print("$hdi_cmd\n");
	`$hdi_cmd`;
    }
    return;
}
1;
