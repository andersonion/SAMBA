sub legacy_system () {
    print("legacy_system\n");
    return 1;
### some legacy linking
# Legacy Link puller
    if ( $isrecon ) { 
	$infile="$wks_home/shared/radish_puller";
	{
	    $ln_source="$infile";
	    $ln_dest="$wks_home/recon/legacy/dir_puller";
	    if ( -r $ln_dest ) { 
		`unlink $ln_dest`;
	    }    
	    $ln_cmd="ln -sf $ln_source $ln_dest";
	    #print ("$ln_cmd\n");
	    `$ln_cmd`;
	}
# legacy link startup
	{
	    $ln_source="$wks_home/shared/pipeline_utilities/startup.m";
	    $ln_dest="$wks_home/recon/legacy/radish_core/startup.m";
	    if ( -r $ln_dest ) { 
		`unlink $ln_dest`;
	    }    
	    $ln_cmd="ln -sf $ln_source $ln_dest";
	    #print ("$ln_cmd\n");
	    `$ln_cmd`;
	}
# legacy link perl
	{
	    if ( ! -e "/usr/local/pipeline-link/perl" )
	    {
		`sudo ln -s /usr/bin/perl /usr/local/pipeline-link/perl`;
	    }
	}
    }
    return;
}
1;
    
