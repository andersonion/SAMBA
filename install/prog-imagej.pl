sub imagej (){
    my $c_cmd="curl http://imagej.nih.gov/ij/download/zips/ | grep zip | tail -n 1";
    my @output=`$c_cmd`; 
    chomp(@output);
    #print("c_cmd:$c_cmd > ".join("\n",@output)."\n");
    my $ij_latest_html_table_entry=join("\n",@output);
    my $ij_zip_name=$ij_latest_html_table_entry;
    #$ij_latest_html_table_entry=~ /.*<[ ]+a[ ]+href[ ]+=[ ]+>"(ij[0-9]+\.zip)">.*/x;
    my( $ij_zip_name) = $ij_latest_html_table_entry=~ /.*<a[ ]+href[ ]*=[ ]*"(ij[0-9]+\.zip)".*/x;
    my $ij_zip_url="http://imagej.nih.gov/ij/download/zips/".$ij_zip_name;
    print("Found ij zip name $ij_zip_name from output: $ij_latest_html_table_entr\n");
    
    ### check older ij zip in  zips/ij*zip 
    ### if newest wget and extract to someplace
    if (! -f "zips/$ij_zip_name" ) {
	if ( !  -d "zips" ) {
	    mkdir ("zips");
	}
	`wget $ij_zip_url`;
	rename( "$ij_zip_name", "zips/$ij_zip_name");
    } else {
	print("ijzip already in place");
    }
    if ( 0 ) {
    chdir ("zips");
    `unzip $ij_zip_name`;
    rename("ImageJ","/cm/shared/apps/ImageJ");
    }
    
    return 0;

    my $output=`which matlab`;
    if ( ! $? ) {
	#when true matlab found.
	print("\tMatlab found, at $output\n");
	return 0;
    } else {
	print("ERROR: Matlab not found, it should be linked into place on the path. path <$ENV{PATH}>\n");
	if ( $IS_MAC ) {
	    my @matlabs=`find /Applications -iname "MATLAB*" -type d -maxdepth 1`;
	    chomp @matlabs;
	    my $mat_path=`find $matlabs[$#matlabs] -name matlab -type f -maxdepth 3`;
	    chomp $mat_path;
	    my $sudo_ln="sudo ln -sf $mat_path /usr/bin/matlab";
	    if ( $IS_ADMIN ) {
		print("\t$sudo_ln\n");
		`$sudo_ln`;
		return $?;
	    } else {
		print("tell your administator you cant access matlab on the command line, and they should run the following command. \n\t$sudo_ln\n");
		return 1;
	    }
	}
	# didtn find matlab, but not mac
	print("Didnt find required software, matlab\n");
	return 1;
    }

}
1;
